import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/context_builder_service.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:aura_mobile/domain/services/llm_intent_classifier.dart';
import 'package:aura_mobile/domain/services/memory_service.dart';
import 'package:aura_mobile/domain/services/scraper_service.dart';
import 'package:aura_mobile/domain/services/study_service.dart';
import 'package:aura_mobile/domain/services/workflow_splitter_service.dart';
import 'package:aura_mobile/domain/models/workflow_plan.dart';
import 'package:aura_mobile/core/services/app_control_service.dart';
import 'package:aura_mobile/core/services/smart_app_actions_service.dart';
import 'package:aura_mobile/core/services/web_service.dart';
import 'package:aura_mobile/features/orchestrator/orchestrator_service.dart';

// Feature: multi-engine-ai-models, Property 14: Tool-calling vs rule-based routing
//
// "For any active model, the orchestrator selects the native function-calling
//  path if and only if the model's supportsToolCalling field is true, and
//  otherwise uses the existing rule-based intent detection."
//
// Validates: Requirements 2.5, 5.4
//
// The orchestrator branch under test is in OrchestratorService.processMessage:
//
//     if (_llmService.supportsToolCalling) {
//       yield* _handleFunctionCalling(...);   // function-calling path
//       return;
//     }
//     ... await _intentService.detectIntent(...) ...   // rule-based path
//
// We mock LLMService (toggling supportsToolCalling) and IntentDetectionService
// so we can observe which path the orchestrator actually runs:
//   - the function-calling path calls _llmService.chat with the tool system
//     prompt (which contains "can call tools") and never calls detectIntent;
//   - the rule-based path calls _intentService.detectIntent and never hands the
//     model the tool system prompt.
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. The
// property runs >= 100 generated cases over random (supportsToolCalling,
// message, isVoiceQuery, hasDocuments) tuples.

const int _iterations = 200;

/// Fake LLMService whose [supportsToolCalling] is fixed at construction.
///
/// Records whether [chat] was ever handed the tool system prompt — the
/// observable signature of the orchestrator's function-calling path. The chat
/// stream yields plain prose (no JSON), so the function-call coordinator treats
/// it as a non-tool emission and the orchestrator simply streams it back,
/// keeping the path self-contained.
class _FakeLLMService extends Fake implements LLMService {
  _FakeLLMService({required this.supportsToolCallingValue});

  final bool supportsToolCallingValue;

  bool toolPromptSeen = false;
  int chatCallCount = 0;

  @override
  bool get supportsToolCalling => supportsToolCallingValue;

  @override
  bool get isModelLoaded => true;

  // Large so the rule-based normalChat branch never redirects small models to
  // web search (irrelevant here, but keeps the fake free of extra deps).
  @override
  ModelTier get modelTier => ModelTier.large;

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) async* {
    chatCallCount++;
    if (systemPrompt != null && systemPrompt.contains('can call tools')) {
      toolPromptSeen = true;
    }
    yield 'This is a plain conversational answer with no tool call.';
  }
}

/// Fake IntentDetectionService that records whether [detectIntent] was invoked
/// — the observable signature of the rule-based path. Returns an intent whose
/// orchestrator branch only yields a string, so no further dependencies are
/// exercised.
class _FakeIntentDetectionService extends Fake
    implements IntentDetectionService {
  bool detectCalled = false;

  @override
  Future<IntentType> detectIntent(
    String message, {
    List<Map<String, String>>? history,
    bool hasDocuments = false,
  }) async {
    detectCalled = true;
    return IntentType.readNotifications;
  }
}

/// Workflow splitter that never finds a compound command, so the rule-based
/// path falls straight through to detectIntent regardless of the voice flag.
class _FakeWorkflowSplitter extends Fake implements WorkflowSplitterService {
  @override
  Future<WorkflowPlan?> splitWorkflow(String message) async => null;
}

// Dependencies the routing branch never touches on either observed path.
class _FakeMemoryService extends Fake implements MemoryService {}

class _FakeContextBuilder extends Fake implements ContextBuilderService {
  @override
  ModelTier modelTier = ModelTier.large;
  @override
  String? personaSystemPrompt;
}

class _FakeWebService extends Fake implements WebService {}

class _FakeScraperService extends Fake implements ScraperService {}

class _FakeAppControlService extends Fake implements AppControlService {}

class _FakeLLMIntentClassifier extends Fake implements LLMIntentClassifier {}

class _FakeStudyService extends Fake implements StudyService {}

class _FakeSmartAppActions extends Fake implements SmartAppActionsService {}

OrchestratorService _buildOrchestrator({
  required _FakeLLMService llm,
  required _FakeIntentDetectionService intent,
}) {
  return OrchestratorService(
    intent,
    _FakeMemoryService(),
    _FakeContextBuilder(),
    llm,
    _FakeWebService(),
    _FakeScraperService(),
    _FakeAppControlService(),
    _FakeLLMIntentClassifier(),
    _FakeWorkflowSplitter(),
    _FakeStudyService(),
    _FakeSmartAppActions(),
  );
}

const _words = [
  'hello', 'open', 'youtube', 'remind', 'me', 'tomorrow', 'call', 'mom',
  'weather', 'today', 'play', 'music', 'search', 'flutter', 'turn', 'torch',
  'on', 'note', 'idea', 'random', 'text', 'message', 'a', 'the', 'quantum',
];

String _randomMessage(Random rng) {
  final n = 1 + rng.nextInt(8);
  return [for (var i = 0; i < n; i++) _words[rng.nextInt(_words.length)]]
      .join(' ');
}

void main() {
  group('Property 14: Tool-calling vs rule-based routing (multi-engine-ai-models)',
      () {
    test(
        'function-calling path is taken iff supportsToolCalling is true '
        '(>= $_iterations generated cases)', () async {
      final rng = Random(20240714);
      for (var i = 0; i < _iterations; i++) {
        final supportsTC = rng.nextBool();
        final llm = _FakeLLMService(supportsToolCallingValue: supportsTC);
        final intent = _FakeIntentDetectionService();
        final orchestrator = _buildOrchestrator(llm: llm, intent: intent);

        final message = _randomMessage(rng);
        final isVoice = rng.nextBool();
        final hasDocs = rng.nextBool();

        // Drain the stream so the routing logic actually executes.
        await orchestrator
            .processMessage(
              message: message,
              chatHistory: const [],
              hasDocuments: hasDocs,
              isVoiceQuery: isVoice,
            )
            .toList();

        if (supportsTC) {
          expect(llm.toolPromptSeen, isTrue,
              reason: 'supportsToolCalling=true must take the function-calling '
                  'path (tool system prompt handed to the model) for '
                  'message="$message", isVoice=$isVoice, hasDocs=$hasDocs');
          expect(intent.detectCalled, isFalse,
              reason: 'supportsToolCalling=true must NOT run rule-based intent '
                  'detection for message="$message"');
        } else {
          expect(intent.detectCalled, isTrue,
              reason: 'supportsToolCalling=false must take the rule-based '
                  'intent-detection path for message="$message", '
                  'isVoice=$isVoice, hasDocs=$hasDocs');
          expect(llm.toolPromptSeen, isFalse,
              reason: 'supportsToolCalling=false must NOT hand the model the '
                  'tool system prompt for message="$message"');
        }
      }
    });

    // --- Focused both-directions checks, holding inputs fixed so only the
    // supportsToolCalling flag differs. ---
    test('toggling only supportsToolCalling flips the chosen path', () async {
      const message = 'open youtube and play lofi';

      final tcLlm = _FakeLLMService(supportsToolCallingValue: true);
      final tcIntent = _FakeIntentDetectionService();
      await _buildOrchestrator(llm: tcLlm, intent: tcIntent)
          .processMessage(message: message, chatHistory: const [])
          .toList();
      expect(tcLlm.toolPromptSeen, isTrue);
      expect(tcIntent.detectCalled, isFalse);

      final rbLlm = _FakeLLMService(supportsToolCallingValue: false);
      final rbIntent = _FakeIntentDetectionService();
      await _buildOrchestrator(llm: rbLlm, intent: rbIntent)
          .processMessage(message: message, chatHistory: const [])
          .toList();
      expect(rbIntent.detectCalled, isTrue);
      expect(rbLlm.toolPromptSeen, isFalse);
    });
  });
}
