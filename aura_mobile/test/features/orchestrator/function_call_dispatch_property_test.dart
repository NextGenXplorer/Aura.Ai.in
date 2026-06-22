import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:aura_mobile/domain/services/memory_service.dart';
import 'package:aura_mobile/domain/services/context_builder_service.dart';
import 'package:aura_mobile/domain/services/scraper_service.dart';
import 'package:aura_mobile/domain/services/llm_intent_classifier.dart';
import 'package:aura_mobile/domain/services/workflow_splitter_service.dart';
import 'package:aura_mobile/domain/services/study_service.dart';
import 'package:aura_mobile/core/services/web_service.dart';
import 'package:aura_mobile/core/services/app_control_service.dart';
import 'package:aura_mobile/core/services/smart_app_actions_service.dart';
import 'package:aura_mobile/features/orchestrator/orchestrator_service.dart';
import 'package:aura_mobile/features/orchestrator/function_call_coordinator.dart';
import 'package:aura_mobile/features/orchestrator/tool_definition.dart';

// Feature: multi-engine-ai-models, Property 13: Valid function-call dispatch
//
// "For any parsed function-call request that names a registered tool and
//  supplies all of that tool's required parameters, the orchestrator invokes
//  exactly the handler associated with that tool name and passes it exactly the
//  parsed parameter values."
//
// Validates: Requirements 5.3
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. The
// property runs >= 100 generated cases.
//
// Approach: the dispatch logic under test is OrchestratorService._dispatchToolCall
// (a private switch keyed by tool name). We exercise the *real* dispatch through
// the public entry point: a fake LLMService reports supportsToolCalling == true
// and emits a serialized function call, so processMessage routes into the
// function-calling path, the production FunctionCallCoordinator parses/validates
// the emission to FunctionCallParsed, and the orchestrator dispatches it. The
// orchestrator's handler collaborators (MemoryService, AppControlService) are
// recording fakes; every other dependency is an isolation fake that throws if
// touched. We then assert that exactly one collaborator method — the one
// associated with the tool name — was invoked, with exactly the parsed argument
// values.

const int _iterations = 200;

/// A single recorded collaborator invocation observed during dispatch.
class _Call {
  final String target;
  final String method;
  final List<Object?> args;
  const _Call(this.target, this.method, this.args);

  @override
  bool operator ==(Object other) =>
      other is _Call &&
      other.target == target &&
      other.method == method &&
      _listEq(other.args, args);

  @override
  int get hashCode => Object.hash(target, method, Object.hashAll(args));

  @override
  String toString() => '$target.$method(${args.join(', ')})';
}

bool _listEq(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The tools whose dispatch maps a parsed request to a single, directly
/// observable collaborator call. Each spec generates a valid arguments map and
/// the expected collaborator invocation for that tool name.
class _ToolCase {
  final String toolName;
  final Map<String, Object?> arguments;
  final _Call expected;
  const _ToolCase(this.toolName, this.arguments, this.expected);
}

const String _alphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

const List<String> _interestingFragments = [
  'hello',
  'My Special Memory',
  'gmail',
  '你好世界',
  '🚀 launch',
  'wifi',
  'John Doe',
  'New York City',
  'a.b-c_d',
  'Buy milk',
];

/// Generates a non-empty value that is invariant under `String.trim()` (no
/// leading/trailing whitespace), so it flows verbatim to the collaborator and
/// the "exact parameter values" assertion is precise.
String _genValue(Random rng) {
  if (rng.nextBool()) {
    return _interestingFragments[rng.nextInt(_interestingFragments.length)];
  }
  final len = 1 + rng.nextInt(12);
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    // Allow interior spaces but never at the ends.
    final pickSpace = i != 0 && i != len - 1 && rng.nextInt(5) == 0;
    sb.write(pickSpace ? ' ' : _alphabet[rng.nextInt(_alphabet.length)]);
  }
  final s = sb.toString().trim();
  return s.isEmpty ? 'x' : s;
}

const List<String> _torchOffWords = ['off', 'false', 'disable'];
const List<String> _torchOnWords = ['on', 'true', 'enable', 'toggle', 'light'];

/// Produces a valid tool case (registered tool + all required params present).
_ToolCase _genToolCase(Random rng) {
  const tools = [
    'store_memory',
    'retrieve_memory',
    'open_app',
    'open_settings',
    'open_camera',
    'dial_contact',
    'navigation',
    'toggle_torch',
  ];
  final tool = tools[rng.nextInt(tools.length)];

  switch (tool) {
    case 'store_memory':
      final content = _genValue(rng);
      return _ToolCase(tool, {'content': content},
          _Call('memory', 'saveMemory', [content]));
    case 'retrieve_memory':
      final query = _genValue(rng);
      return _ToolCase(tool, {'query': query},
          _Call('memory', 'retrieveRelevantMemories', [query]));
    case 'open_app':
      final appName = _genValue(rng);
      return _ToolCase(tool, {'appName': appName},
          _Call('appControl', 'openApp', [appName]));
    case 'open_settings':
      final type = _genValue(rng);
      return _ToolCase(tool, {'type': type},
          _Call('appControl', 'openSettings', [type]));
    case 'open_camera':
      return _ToolCase(tool, const {},
          const _Call('appControl', 'openCamera', []));
    case 'dial_contact':
      final contactName = _genValue(rng);
      return _ToolCase(tool, {'contactName': contactName},
          _Call('appControl', 'resolveContacts', [contactName]));
    case 'navigation':
      final destination = _genValue(rng);
      return _ToolCase(tool, {'destination': destination},
          _Call('appControl', 'openApp', ['navigate:$destination']));
    case 'toggle_torch':
      final on = rng.nextBool();
      final word = on
          ? _torchOnWords[rng.nextInt(_torchOnWords.length)]
          : _torchOffWords[rng.nextInt(_torchOffWords.length)];
      // Dispatch lowercases the arg; expected bool = NOT an explicit off word.
      final expected = !_torchOffWords.contains(word.toLowerCase());
      return _ToolCase(tool, {'state': word},
          _Call('appControl', 'toggleTorch', [expected]));
    default:
      throw StateError('unreachable');
  }
}

OrchestratorService _buildOrchestrator(
  List<_Call> log,
  _FakeLLM llm,
) {
  return OrchestratorService(
    _FakeIntent(),
    _RecordingMemory(log),
    _FakeContextBuilder(),
    llm,
    _FakeWeb(),
    _FakeScraper(),
    _RecordingAppControl(log),
    _FakeClassifier(),
    _FakeWorkflowSplitter(),
    _FakeStudy(),
    _FakeSmartAppActions(),
  );
}

void main() {
  group('Property 13: Valid function-call dispatch (multi-engine-ai-models)',
      () {
    test(
        'a valid parsed call invokes exactly the tool\'s handler with the '
        'parsed parameter values', () async {
      final rng = Random(20240926);

      for (var i = 0; i < _iterations; i++) {
        final toolCase = _genToolCase(rng);
        final request = FunctionCallRequest(
          toolName: toolCase.toolName,
          arguments: toolCase.arguments,
        );

        // Precondition: the production coordinator must classify this emission
        // as a valid, dispatchable parsed request (known tool + required params).
        final coordinator = FunctionCallCoordinator.fromDefinitions(
          _orchestratorToolDefinitions,
        );
        final emission = FunctionCallCoordinator.serialize(request);
        final parsed = coordinator.parse(emission);
        expect(parsed, isA<FunctionCallParsed>(),
            reason: 'Property 13 precondition failed: emission for '
                '${toolCase.toolName} did not parse to FunctionCallParsed\n'
                '  emission = $emission\n  result = $parsed');

        final log = <_Call>[];
        final llm = _FakeLLM()..emission = emission;
        final orchestrator = _buildOrchestrator(log, llm);

        // Drain the dispatch stream so all handler side effects run.
        await orchestrator
            .processMessage(message: 'drive $i', chatHistory: const [])
            .toList();

        // Exactly one collaborator handler was invoked...
        expect(log.length, 1,
            reason: 'Property 13 counterexample (expected exactly one handler '
                'invocation)\n  tool = ${toolCase.toolName}\n'
                '  arguments = ${toolCase.arguments}\n  observed = $log');

        // ...and it was the handler associated with this tool name, receiving
        // exactly the parsed parameter values.
        expect(log.single, equals(toolCase.expected),
            reason: 'Property 13 counterexample (wrong handler or arguments)\n'
                '  tool = ${toolCase.toolName}\n'
                '  arguments = ${toolCase.arguments}\n'
                '  expected = ${toolCase.expected}\n'
                '  observed = ${log.single}');
      }
    });

    test('example: store_memory dispatches saveMemory with the exact content',
        () async {
      final log = <_Call>[];
      final llm = _FakeLLM()
        ..emission = FunctionCallCoordinator.serialize(
          const FunctionCallRequest(
            toolName: 'store_memory',
            arguments: {'content': 'Remember the milk'},
          ),
        );
      final orchestrator = _buildOrchestrator(log, llm);

      await orchestrator
          .processMessage(message: 'x', chatHistory: const [])
          .toList();

      expect(log, [
        const _Call('memory', 'saveMemory', ['Remember the milk'])
      ]);
    });

    test('example: open_app dispatches openApp with the exact app name',
        () async {
      final log = <_Call>[];
      final llm = _FakeLLM()
        ..emission = FunctionCallCoordinator.serialize(
          const FunctionCallRequest(
            toolName: 'open_app',
            arguments: {'appName': 'Spotify'},
          ),
        );
      final orchestrator = _buildOrchestrator(log, llm);

      await orchestrator
          .processMessage(message: 'x', chatHistory: const [])
          .toList();

      expect(log, [const _Call('appControl', 'openApp', ['Spotify'])]);
    });

    test('example: navigation prefixes the destination for openApp', () async {
      final log = <_Call>[];
      final llm = _FakeLLM()
        ..emission = FunctionCallCoordinator.serialize(
          const FunctionCallRequest(
            toolName: 'navigation',
            arguments: {'destination': 'Central Park'},
          ),
        );
      final orchestrator = _buildOrchestrator(log, llm);

      await orchestrator
          .processMessage(message: 'x', chatHistory: const [])
          .toList();

      expect(log, [
        const _Call('appControl', 'openApp', ['navigate:Central Park'])
      ]);
    });
  });
}

/// The orchestrator's registered tool set, mirrored here only to validate the
/// dispatch precondition (the orchestrator builds this same set internally).
const List<ToolDefinition> _orchestratorToolDefinitions = [
  ToolDefinition(name: 'store_memory', parameters: [
    ToolParameter(name: 'content', required: true),
  ]),
  ToolDefinition(name: 'retrieve_memory', parameters: [
    ToolParameter(name: 'query', required: true),
  ]),
  ToolDefinition(name: 'web_search', parameters: [
    ToolParameter(name: 'query', required: true),
  ]),
  ToolDefinition(name: 'scrape_url', parameters: [
    ToolParameter(name: 'url', required: true),
  ]),
  ToolDefinition(name: 'open_app', parameters: [
    ToolParameter(name: 'appName', required: true),
  ]),
  ToolDefinition(name: 'open_settings', parameters: [
    ToolParameter(name: 'type'),
  ]),
  ToolDefinition(name: 'open_camera'),
  ToolDefinition(name: 'dial_contact', parameters: [
    ToolParameter(name: 'contactName', required: true),
  ]),
  ToolDefinition(name: 'send_sms', parameters: [
    ToolParameter(name: 'name', required: true),
    ToolParameter(name: 'message'),
  ]),
  ToolDefinition(name: 'set_reminder', parameters: [
    ToolParameter(name: 'time', required: true),
    ToolParameter(name: 'title'),
  ]),
  ToolDefinition(name: 'navigation', parameters: [
    ToolParameter(name: 'destination', required: true),
  ]),
  ToolDefinition(name: 'toggle_torch', parameters: [
    ToolParameter(name: 'state'),
  ]),
];

// ── Fakes ──────────────────────────────────────────────────────────────────

/// Tool-calling LLM whose `chat` replays a fixed serialized function call.
class _FakeLLM implements LLMService {
  String emission = '';

  @override
  bool get supportsToolCalling => true;

  @override
  bool get isModelLoaded => true;

  @override
  ModelTier get modelTier => ModelTier.large;

  @override
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) async* {
    yield emission;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {}
}

/// Records the memory-handler collaborator calls reachable from dispatch.
class _RecordingMemory implements MemoryService {
  _RecordingMemory(this.log);
  final List<_Call> log;

  @override
  Future<void> saveMemory(String content) async {
    log.add(_Call('memory', 'saveMemory', [content]));
  }

  @override
  Future<List<String>> retrieveRelevantMemories(String query,
      {int limit = 3}) async {
    log.add(_Call('memory', 'retrieveRelevantMemories', [query]));
    return const []; // empty → handler reports "no memories" and stops.
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected MemoryService.${invocation.memberName}');
}

/// Records the app-control collaborator calls reachable from dispatch.
class _RecordingAppControl implements AppControlService {
  _RecordingAppControl(this.log);
  final List<_Call> log;

  @override
  Future<void> openApp(String appName) async {
    log.add(_Call('appControl', 'openApp', [appName]));
  }

  @override
  Future<void> openSettings(String type) async {
    log.add(_Call('appControl', 'openSettings', [type]));
  }

  @override
  Future<void> openCamera() async {
    log.add(const _Call('appControl', 'openCamera', []));
  }

  @override
  Future<List<Contact>> resolveContacts(String name) async {
    log.add(_Call('appControl', 'resolveContacts', [name]));
    return const []; // empty → handler reports "not found" and stops.
  }

  @override
  Future<void> toggleTorch(bool state) async {
    log.add(_Call('appControl', 'toggleTorch', [state]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected AppControlService.${invocation.memberName}');
}

/// Context builder fake: only the mutable `modelTier` field (set by
/// processMessage) is exercised; everything else must not be reached.
class _FakeContextBuilder implements ContextBuilderService {
  @override
  ModelTier modelTier = ModelTier.large;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected ContextBuilderService.${invocation.memberName}');
}

class _FakeIntent implements IntentDetectionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected IntentDetectionService.${invocation.memberName}');
}

class _FakeWeb implements WebService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected WebService.${invocation.memberName}');
}

class _FakeScraper implements ScraperService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected ScraperService.${invocation.memberName}');
}

class _FakeClassifier implements LLMIntentClassifier {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected LLMIntentClassifier.${invocation.memberName}');
}

class _FakeWorkflowSplitter implements WorkflowSplitterService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected WorkflowSplitterService.${invocation.memberName}');
}

class _FakeStudy implements StudyService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected StudyService.${invocation.memberName}');
}

class _FakeSmartAppActions implements SmartAppActionsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected SmartAppActionsService.${invocation.memberName}');
}
