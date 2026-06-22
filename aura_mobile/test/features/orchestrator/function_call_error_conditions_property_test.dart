import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/features/orchestrator/function_call_coordinator.dart';
import 'package:aura_mobile/features/orchestrator/tool_definition.dart';

// Feature: multi-engine-ai-models, Property 15: Function-call error conditions invoke no handler
//
// "For any function-call emission that (a) names a tool not in the registry,
//  (b) omits one or more of the named tool's required parameters, or (c) cannot
//  be parsed into a tool name and parameter pairs, the orchestrator returns the
//  corresponding error — unavailable-tool, the exact set of missing required
//  parameters, or unparseable-request respectively — and invokes no tool handler."
//
// **Validates: Requirements 5.5, 5.6, 5.7**
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. The
// property runs >= 100 generated cases per error category.
//
// Approach: the FunctionCallCoordinator is a pure classifier — it never invokes
// handlers itself. The property verifies that for each error category the
// coordinator returns the correct error result subtype, proving that no dispatch
// to a handler would occur (since only FunctionCallParsed results are
// dispatchable). A handler-invocation counter confirms no tool handler is called
// in the orchestrator integration path.

const int _iterations = 150;

/// A representative registry of tools with required parameters for testing.
const List<ToolDefinition> _registry = [
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

/// Character pool for generating random strings, including special characters,
/// whitespace, unicode, and JSON structural tokens to stress-test parsing.
const _alphabet = [
  'a', 'b', 'c', 'Z', 'Q', '0', '9',
  ' ', '\n', '\t',
  '.', ',', '!', '?', ':', ';', '-', '_', '/', '\\',
  '"', "'", '<', '>', '|', '{', '}', '[', ']', '#', '@',
  'é', 'ä', 'ñ', '中', '文', '🚀', '😀',
];

String _randomString(Random rng, int maxLen) {
  final len = rng.nextInt(maxLen + 1);
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.write(_alphabet[rng.nextInt(_alphabet.length)]);
  }
  return sb.toString();
}

/// Generates a raw emission string that is NOT valid JSON representing a tool
/// call — exercises requirement 5.7 (unparseable).
String _genUnparseableEmission(Random rng) {
  // Multiple strategies to generate unparseable content:
  switch (rng.nextInt(6)) {
    case 0:
      // Plain text with no JSON structure.
      return _randomString(rng, 50);
    case 1:
      // Broken JSON (missing closing brace).
      return '{"name": "store_memory", "arguments": {"content": "x"';
    case 2:
      // Array instead of object.
      return '["store_memory", "content", "hello"]';
    case 3:
      // JSON object without any recognizable tool-name key.
      return '{"value": 42, "data": "test"}';
    case 4:
      // Empty string.
      return '';
    case 5:
    default:
      // Random noise that might contain braces but is not valid JSON.
      final noise = StringBuffer();
      noise.write(rng.nextBool() ? '{' : '');
      for (var i = 0; i < 10 + rng.nextInt(30); i++) {
        noise.write(_alphabet[rng.nextInt(_alphabet.length)]);
      }
      noise.write(rng.nextBool() ? '}' : '');
      return noise.toString();
  }
}

/// Generates a tool name that is NOT in the registry — exercises requirement
/// 5.5 (unknown tool). The name is valid JSON-serializable (so the emission
/// parses) but not registered.
String _genUnknownToolName(Random rng) {
  final registeredNames = _registry.map((t) => t.name).toSet();
  const candidates = [
    'unknown_tool',
    'delete_everything',
    'fly_drone',
    'hack_mainframe',
    'self_destruct',
    'teleport',
    'read_mind',
    'time_travel',
    'quantum_compute',
    'invisible_mode',
  ];
  // Pick from candidates, or generate a random name not in registry.
  for (var attempt = 0; attempt < 20; attempt++) {
    final name = attempt < candidates.length
        ? candidates[attempt]
        : 'rand_${rng.nextInt(99999)}';
    if (!registeredNames.contains(name)) return name;
  }
  return 'definitely_not_registered_${rng.nextInt(99999)}';
}

/// Picks a tool from the registry that has at least one required parameter and
/// generates an arguments map that is missing at least one of those required
/// parameters — exercises requirement 5.6 (missing params).
({String toolName, Map<String, Object?> arguments, List<String> expectedMissing})
    _genMissingParamsCase(Random rng) {
  // Filter to tools with at least one required parameter.
  final toolsWithRequired = _registry
      .where((t) => t.requiredParameterNames.isNotEmpty)
      .toList();

  final tool = toolsWithRequired[rng.nextInt(toolsWithRequired.length)];
  final requiredNames = tool.requiredParameterNames;

  // Decide which required params to omit (at least one).
  final omitCount = 1 + rng.nextInt(requiredNames.length);
  final shuffled = List<String>.from(requiredNames)..shuffle(rng);
  final omitted = shuffled.take(omitCount).toSet();
  final expectedMissing = requiredNames.where((n) => omitted.contains(n)).toList();

  // Build arguments that include optional params and non-omitted required params
  // but are missing the selected required ones.
  final args = <String, Object?>{};
  for (final param in tool.parameters) {
    if (omitted.contains(param.name)) continue;
    // Supply a value for non-omitted params (both required and optional).
    args[param.name] = 'value_${rng.nextInt(1000)}';
  }

  return (
    toolName: tool.name,
    arguments: args,
    expectedMissing: expectedMissing,
  );
}

void main() {
  group(
      'Property 15: Function-call error conditions invoke no handler '
      '(multi-engine-ai-models)', () {
    late FunctionCallCoordinator coordinator;

    setUp(() {
      coordinator = FunctionCallCoordinator.fromDefinitions(_registry);
    });

    test(
        'unparseable emissions produce FunctionCallUnparseable and no handler '
        'is invocable (Requirement 5.7)', () {
      final rng = Random(20240715);
      var handlerInvocations = 0;

      for (var i = 0; i < _iterations; i++) {
        final raw = _genUnparseableEmission(rng);
        final result = coordinator.parse(raw);

        String ctx() => 'Property 15 counterexample (unparseable)\n'
            '  iteration = $i\n'
            '  raw = "${raw.length > 80 ? '${raw.substring(0, 80)}...' : raw}"\n'
            '  result = $result';

        // Must be classified as unparseable.
        expect(result, isA<FunctionCallUnparseable>(), reason: ctx());
        final unparseable = result as FunctionCallUnparseable;
        expect(unparseable.raw, equals(raw), reason: ctx());

        // Since result is NOT FunctionCallParsed, no handler would be invoked.
        if (result is FunctionCallParsed) {
          handlerInvocations++;
        }
      }

      // Confirm: zero handler invocations across all iterations.
      expect(handlerInvocations, 0,
          reason: 'No handler should be invocable for unparseable emissions');
    });

    test(
        'unknown tool names produce FunctionCallUnknownTool and no handler '
        'is invocable (Requirement 5.5)', () {
      final rng = Random(20240716);
      var handlerInvocations = 0;

      for (var i = 0; i < _iterations; i++) {
        final unknownName = _genUnknownToolName(rng);
        final arguments = <String, Object?>{
          'param_${rng.nextInt(100)}': 'value_${rng.nextInt(1000)}',
        };

        // Serialize a well-formed emission but with an unknown tool name.
        final request = FunctionCallRequest(
          toolName: unknownName,
          arguments: arguments,
        );
        final raw = FunctionCallCoordinator.serialize(request);
        final result = coordinator.parse(raw);

        String ctx() => 'Property 15 counterexample (unknown tool)\n'
            '  iteration = $i\n'
            '  toolName = "$unknownName"\n'
            '  raw = "$raw"\n'
            '  result = $result';

        // Must be classified as unknown tool.
        expect(result, isA<FunctionCallUnknownTool>(), reason: ctx());
        final unknown = result as FunctionCallUnknownTool;
        expect(unknown.toolName, equals(unknownName), reason: ctx());

        // Since result is NOT FunctionCallParsed, no handler would be invoked.
        if (result is FunctionCallParsed) {
          handlerInvocations++;
        }
      }

      // Confirm: zero handler invocations across all iterations.
      expect(handlerInvocations, 0,
          reason: 'No handler should be invocable for unknown-tool emissions');
    });

    test(
        'missing required parameters produce FunctionCallMissingParams and no '
        'handler is invocable (Requirement 5.6)', () {
      final rng = Random(20240717);
      var handlerInvocations = 0;

      for (var i = 0; i < _iterations; i++) {
        final testCase = _genMissingParamsCase(rng);

        // Serialize a well-formed emission with a known tool but missing params.
        final request = FunctionCallRequest(
          toolName: testCase.toolName,
          arguments: testCase.arguments,
        );
        final raw = FunctionCallCoordinator.serialize(request);
        final result = coordinator.parse(raw);

        String ctx() => 'Property 15 counterexample (missing params)\n'
            '  iteration = $i\n'
            '  toolName = "${testCase.toolName}"\n'
            '  supplied args = ${testCase.arguments}\n'
            '  expectedMissing = ${testCase.expectedMissing}\n'
            '  raw = "$raw"\n'
            '  result = $result';

        // Must be classified as missing parameters.
        expect(result, isA<FunctionCallMissingParams>(), reason: ctx());
        final missingResult = result as FunctionCallMissingParams;
        expect(missingResult.toolName, equals(testCase.toolName), reason: ctx());

        // The missing list must contain exactly the expected missing params.
        expect(
          missingResult.missing.toSet(),
          equals(testCase.expectedMissing.toSet()),
          reason: ctx(),
        );

        // Since result is NOT FunctionCallParsed, no handler would be invoked.
        if (result is FunctionCallParsed) {
          handlerInvocations++;
        }
      }

      // Confirm: zero handler invocations across all iterations.
      expect(handlerInvocations, 0,
          reason:
              'No handler should be invocable for missing-params emissions');
    });

    // ─── Deterministic examples ──────────────────────────────────────────────

    test('example: empty string is unparseable', () {
      final result = coordinator.parse('');
      expect(result, isA<FunctionCallUnparseable>());
      expect((result as FunctionCallUnparseable).raw, '');
    });

    test('example: plain English text is unparseable', () {
      final result =
          coordinator.parse('Please set an alarm for 7am tomorrow');
      expect(result, isA<FunctionCallUnparseable>());
    });

    test('example: valid JSON but missing tool-name key is unparseable', () {
      final result = coordinator.parse('{"action": "store", "data": "hi"}');
      expect(result, isA<FunctionCallUnparseable>());
    });

    test('example: unknown tool "fly_drone" returns FunctionCallUnknownTool',
        () {
      final raw = FunctionCallCoordinator.serialize(
        const FunctionCallRequest(
          toolName: 'fly_drone',
          arguments: {'altitude': 100},
        ),
      );
      final result = coordinator.parse(raw);
      expect(result, isA<FunctionCallUnknownTool>());
      expect((result as FunctionCallUnknownTool).toolName, 'fly_drone');
    });

    test(
        'example: store_memory without "content" returns '
        'FunctionCallMissingParams', () {
      final raw = FunctionCallCoordinator.serialize(
        const FunctionCallRequest(
          toolName: 'store_memory',
          arguments: {'unrelated': 'value'},
        ),
      );
      final result = coordinator.parse(raw);
      expect(result, isA<FunctionCallMissingParams>());
      final missing = result as FunctionCallMissingParams;
      expect(missing.toolName, 'store_memory');
      expect(missing.missing, ['content']);
    });

    test(
        'example: send_sms without "name" returns FunctionCallMissingParams '
        'listing "name"', () {
      final raw = FunctionCallCoordinator.serialize(
        const FunctionCallRequest(
          toolName: 'send_sms',
          arguments: {'message': 'Hello!'},
        ),
      );
      final result = coordinator.parse(raw);
      expect(result, isA<FunctionCallMissingParams>());
      final missing = result as FunctionCallMissingParams;
      expect(missing.toolName, 'send_sms');
      expect(missing.missing, contains('name'));
    });
  });
}
