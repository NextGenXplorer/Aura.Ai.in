import 'package:aura_mobile/domain/models/workflow_plan.dart';
import 'package:aura_mobile/domain/models/workflow_step.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:aura_mobile/domain/services/workflow_engine_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'workflow_engine_test.mocks.dart';

// Mock SharedPreferences for workflow state persistence
class MockSharedPreferences extends Fake
    with MockPlatformInterfaceMixin
    implements SharedPreferencesStorePlatform {
  final Map<String, Object> _store = {};

  @override
  bool get isMock => true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _store[key] = value;
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map.from(_store);

  @override
  Future<bool> remove(String key) async {
    _store.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _store.clear();
    return true;
  }
}

@GenerateNiceMocks([
  MockSpec<LLMService>(),
])
void main() {
  group('WorkflowEngineService', () {
    late WorkflowEngineService engine;
    late MockLLMService mockLLM;
    late List<String> executionLog;
    late List<String> yieldedMessages;

    setUpAll(() {
      // Register mock SharedPreferences for workflow state persistence
      SharedPreferencesStorePlatform.instance = MockSharedPreferences();
    });

    setUp(() {
      executionLog = [];
      yieldedMessages = [];
      mockLLM = MockLLMService();

      // Mock processStep function
      Stream<String> mockProcessStep({
        required String message,
        required List<String> chatHistory,
        bool hasDocuments = false,
        bool isVoiceQuery = false,
        bool forceNormalChat = false,
      }) async* {
        executionLog.add('executed: $message');
        if (message == 'fail_me') {
          throw Exception('Simulated step failure');
        }
        if (message == 'Search meeting info') {
          yield 'Found a link: https://zoom.us/j/123';
        } else if (message.contains('Add link:')) {
          yield 'Added to calendar: ${message.split(':').last}';
        } else if (message == 'Search weather') {
          yield 'Weather is 25C and sunny';
        } else {
          yield 'Done: $message';
        }
      }

      engine = WorkflowEngineService(mockProcessStep, mockLLM);
    });

    test('executes sequentially and yields progress headers', () async {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(rawMessage: 'step 1'),
        WorkflowStep(rawMessage: 'step 2'),
      ]);

      await for (final msg in engine.execute(plan, [])) {
        yieldedMessages.add(msg);
      }

      expect(executionLog, [
        'executed: step 1',
        'executed: step 2',
      ]);
      expect(yieldedMessages.last, contains('✅ Workflow complete'));
    });

    test('performs variable interpolation and entity extraction', () async {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(
          rawMessage: 'Search meeting info',
          hintType: IntentType.webSearch,
          outputKey: 'zoomLink',
          extractionRequirement: 'Extract the URL',
        ),
        WorkflowStep(
          rawMessage: 'Add link: {zoomLink}',
          hintType: IntentType.reminderSet,
        ),
      ]);

      // Mock LLM plucking result
      when(mockLLM.chat(any, systemPrompt: anyNamed('systemPrompt'), maxTokens: anyNamed('maxTokens')))
          .thenAnswer((_) async* {
            yield 'https://zoom.us/j/123';
          });

      await for (final msg in engine.execute(plan, [])) {
        yieldedMessages.add(msg);
      }

      // Step 1: Executed message as is
      expect(executionLog[0], 'executed: Search meeting info');
      
      // Step 2: Executed message WITH interpolated value
      expect(executionLog[1], 'executed: Add link: https://zoom.us/j/123');

      expect(yieldedMessages.any((m) => m.contains('*🔍 Extracting zoomLink...*')), isTrue);
    });

    test('passes context fallback for "it" or "that"', () async {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(rawMessage: 'Search weather', hintType: IntentType.webSearch),
        WorkflowStep(rawMessage: 'remind me about that', hintType: IntentType.reminderSet),
      ]);

      await for (final msg in engine.execute(plan, [])) {
        yieldedMessages.add(msg);
      }

      expect(executionLog[0], 'executed: Search weather');
      expect(
        executionLog[1],
        contains('remind me about that\n\n[Context from previous step: Weather is 25C and sunny]'),
      );
    });

    test('aborts workflow when failFast is true', () async {
      final plan = WorkflowPlan(
        steps: const [
          WorkflowStep(rawMessage: 'fail_me'),
          WorkflowStep(rawMessage: 'step 2'),
        ],
        failFast: true,
      );

      await for (final msg in engine.execute(plan, [])) {
        yieldedMessages.add(msg);
      }

      // With retry logic: 1 initial attempt + 3 retries = 4 executions
      expect(executionLog, [
        'executed: fail_me',
        'executed: fail_me',
        'executed: fail_me',
        'executed: fail_me',
      ]);
      expect(yieldedMessages.last, contains('⛔ Workflow aborted'));
    });
  });
}
