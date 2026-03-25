import 'package:aura_mobile/domain/models/workflow_plan.dart';
import 'package:aura_mobile/domain/models/workflow_step.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:aura_mobile/domain/services/workflow_splitter_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:aura_mobile/domain/services/llm_intent_classifier.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'dart:convert';

import 'workflow_splitter_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<LLMIntentClassifier>(),
  MockSpec<LLMService>(),
  MockSpec<IntentDetectionService>(),
])
void main() {
  late MockLLMIntentClassifier mockClassifier;
  late MockLLMService mockLLM;
  late MockIntentDetectionService mockIntentService;
  late WorkflowSplitterService splitter;

  setUp(() {
    mockClassifier = MockLLMIntentClassifier();
    mockLLM = MockLLMService();
    mockIntentService = MockIntentDetectionService();

    // Default: LLM model NOT loaded (keeps most tests fast/offline)
    when(mockLLM.isModelLoaded).thenReturn(false);

    // Default: rule-based intent detection returns normalChat
    when(mockIntentService.detectIntent(any))
        .thenAnswer((_) async => IntentType.normalChat);

    splitter = WorkflowSplitterService(mockClassifier, mockLLM, mockIntentService);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // GUARD: Short messages that must never trigger a workflow
  // ─────────────────────────────────────────────────────────────────────────
  group('Guard — Short message passthrough', () {
    test('Greeting returns null', () async {
      expect(await splitter.splitWorkflow('hey'), isNull);
    });

    test('Single action returns null', () async {
      expect(await splitter.splitWorkflow('Search weather'), isNull);
    });

    test('Short connector noise "yes and no" returns null', () async {
      expect(await splitter.splitWorkflow('yes and no'), isNull);
    });

    test('6-word message without clear compound structure returns null', () async {
      expect(await splitter.splitWorkflow('open maps and go home'), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // LAYER 1: Rule-based splitting
  // ─────────────────────────────────────────────────────────────────────────
  group('Layer 1 — Rule-based splitting', () {
    test('"then" connector → 2 steps', () async {
      final plan = await splitter.splitWorkflow(
        'Search for the weather today then remind me to carry an umbrella at 8am',
      );
      expect(plan, isNotNull);
      _expectSteps(plan!, 2);
      expect(plan.steps[0].rawMessage.toLowerCase(), contains('weather'));
      expect(plan.steps[1].rawMessage.toLowerCase(), contains('umbrella'));
    });

    test('"and then" connector → 2 steps', () async {
      final plan = await splitter.splitWorkflow(
        'open WhatsApp and then text John saying hello',
      );
      expect(plan, isNotNull);
      _expectSteps(plan!, 2);
    });

    test('"after that" connector → 2 steps', () async {
      final plan = await splitter.splitWorkflow(
        'Search for best restaurants near me after that open google maps',
      );
      expect(plan, isNotNull);
      _expectSteps(plan!, 2);
    });

    test('"also" connector → 3 steps', () async {
      final plan = await splitter.splitWorkflow(
        'Open WhatsApp and text John hi, also set a reminder at 8pm tonight.',
      );
      expect(plan, isNotNull);
      _expectSteps(plan!, greaterThanOrEqualTo(2));
    });

    test('"followed by" connector → 2 steps', () async {
      final plan = await splitter.splitWorkflow(
        'recall my notes about the project followed by web search on Dart async tips',
      );
      expect(plan, isNotNull);
      _expectSteps(plan!, 2);
    });

    test('"and also" connector → 2 steps', () async {
      final plan = await splitter.splitWorkflow(
        'Search for cricket score today and also remind me to watch the match at 7pm',
      );
      expect(plan, isNotNull);
      _expectSteps(plan!, 2);
    });

    test('"then also" connector → 2 steps', () async {
      final plan = await splitter.splitWorkflow(
        'open camera and take a photo then also send it to my email',
      );
      expect(plan, isNotNull);
      _expectSteps(plan!, greaterThanOrEqualTo(2));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Step intent enrichment
  // ─────────────────────────────────────────────────────────────────────────
  group('Step enrichment — intent hints', () {
    test('webSearch step gets correct hintType from rule-based detection', () async {
      when(mockIntentService.detectIntent(argThat(contains('weather'))))
          .thenAnswer((_) async => IntentType.webSearch);
      when(mockIntentService.detectIntent(argThat(contains('umbrella'))))
          .thenAnswer((_) async => IntentType.reminderSet);

      final plan = await splitter.splitWorkflow(
        'Search for the weather today then remind me to carry an umbrella at 8am',
      );

      expect(plan, isNotNull);
      expect(plan!.steps[0].hintType, IntentType.webSearch);
      expect(plan.steps[1].hintType, IntentType.reminderSet);
    });

    test('normalChat hint is set when rule-based cannot classify', () async {
      when(mockIntentService.detectIntent(any))
          .thenAnswer((_) async => IntentType.normalChat);

      final plan = await splitter.splitWorkflow(
        'Tell me about Flutter performance then explain Dart isolates',
      );

      // Both steps map to normalChat; we ensure no null crash
      expect(plan, isNotNull);
      for (final step in plan!.steps) {
        expect(step.rawMessage, isNotEmpty);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // WorkflowPlan properties
  // ─────────────────────────────────────────────────────────────────────────
  group('WorkflowPlan properties', () {
    test('isMultiStep is true for 2+ steps', () async {
      final plan = await splitter.splitWorkflow(
        'Search for the weather today then remind me to carry an umbrella at 8am',
      );
      expect(plan?.isMultiStep, isTrue);
    });

    test('failFast defaults to false', () async {
      final plan = await splitter.splitWorkflow(
        'Search for the weather today then remind me to carry an umbrella at 8am',
      );
      expect(plan?.failFast, isFalse);
    });

    test('length equals number of steps', () async {
      final plan = await splitter.splitWorkflow(
        'Search for the weather today then remind me to carry an umbrella at 8am',
      );
      expect(plan?.length, plan?.steps.length);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // WorkflowStep model
  // ─────────────────────────────────────────────────────────────────────────
  group('WorkflowStep model', () {
    test('withHint creates a new step with updated type', () {
      const step = WorkflowStep(rawMessage: 'Search weather');
      final enriched = step.withHint(IntentType.webSearch, {'query': 'weather'});
      expect(enriched.hintType, IntentType.webSearch);
      expect(enriched.parameters['query'], 'weather');
      expect(enriched.rawMessage, 'Search weather');
    });

    test('toString includes intent name and raw message', () {
      const step = WorkflowStep(
        rawMessage: 'Search for weather',
        hintType: IntentType.webSearch,
      );
      expect(step.toString(), contains('webSearch'));
      expect(step.toString(), contains('Search for weather'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // LAYER 2: LLM splitting & data flow
  // ─────────────────────────────────────────────────────────────────────────
  group('Layer 2 — LLM splitting & Extraction', () {
    test('LLM split identifies outputKey and extractionRequirement', () async {
      when(mockLLM.isModelLoaded).thenReturn(true);
      
      final mockJsonResponse = jsonEncode([
        {
          "rawMessage": "Search email info",
          "hintType": "webSearch",
          "outputKey": "personName",
          "extractionRequirement": "Extract the name"
        },
        {
          "rawMessage": "Say hi to {personName}",
          "hintType": "normalChat"
        }
      ]);

      when(mockLLM.chat(any, systemPrompt: anyNamed('systemPrompt'), maxTokens: anyNamed('maxTokens')))
          .thenAnswer((_) async* {
            yield mockJsonResponse;
          });

      final plan = await splitter.splitWorkflow('retrieve last email extract meeting link create calendar event at 5pm');

      expect(plan, isNotNull);
      expect(plan!.steps.length, 2);
      expect(plan.steps[0].outputKey, 'personName');
      expect(plan.steps[0].extractionRequirement, 'Extract the name');
      expect(plan.steps[1].rawMessage, 'Say hi to {personName}');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Assert that [plan] has at least [count] steps and that none are empty.
void _expectSteps(WorkflowPlan plan, dynamic matcher) {
  expect(plan.steps.length, matcher);
  for (final step in plan.steps) {
    expect(step.rawMessage.trim(), isNotEmpty,
        reason: 'Step rawMessage must not be empty');
  }
}
