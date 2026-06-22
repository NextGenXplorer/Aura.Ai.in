import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/data/datasources/engine_router.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';

// Feature: multi-engine-ai-models, Property 28: Chat failure is contained and non-destructive
//
// "For any chat call delegated to the LiteRtService that raises an error, the
//  Engine_Router returns a handled chat-failure error (it does not propagate an
//  uncaught exception that would terminate the application) and keeps the active
//  model loaded and available for subsequent chat calls."
//
// **Validates: Requirements 10.4, 10.5**
//
// The test uses a fake LiteRtService that alternately succeeds and fails during
// chat to verify containment over many iterations. Each property run uses the
// generator-based approach (Random + iterations >= 100), NOT glados.

const int _iterations = 150;

// ---------------------------------------------------------------------------
// Fake GGUF engine — simple pass-through, always succeeds.
// ---------------------------------------------------------------------------

class _FakeGgufEngine extends Fake implements LLMService {
  bool _loaded = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {
    _loaded = true;
  }

  @override
  bool get isModelLoaded => _loaded;

  @override
  ModelTier get modelTier => ModelTier.large;

  @override
  bool get supportsToolCalling => false;

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    return Stream.value('gguf:$prompt');
  }
}

// ---------------------------------------------------------------------------
// Fake LiteRtService — controllable chat failure behavior.
// ---------------------------------------------------------------------------

/// A fake LiteRtService whose [chat] can be configured to throw on specific
/// invocations. When [shouldFailNext] is true, the next chat call throws an
/// exception (simulating an engine crash). Otherwise it yields tokens normally.
class _FailableLiteRtService extends Fake implements LiteRtService {
  bool _loaded = false;
  bool _initialized = false;

  /// When true, the next [chat] call will throw an exception.
  bool shouldFailNext = false;

  /// Tracks the total number of successful chat calls.
  int successCount = 0;

  /// Tracks the total number of failed chat calls (from this fake's perspective).
  int failCount = 0;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> loadModel(String modelPath) async {
    _loaded = true;
  }

  @override
  bool get isModelLoaded => _loaded;

  @override
  ModelTier get modelTier => _tier;

  ModelTier _tier = ModelTier.medium;

  @override
  set modelTier(ModelTier tier) => _tier = tier;

  @override
  bool get supportsToolCalling => false;

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    if (shouldFailNext) {
      failCount++;
      // Throw synchronously — simulates an engine that fails before producing
      // a stream. The router's _litertChatGuarded wraps this in try/catch.
      throw Exception('Simulated LiteRT engine crash during inference');
    }
    successCount++;
    return Stream.value('litert:$prompt');
  }
}

// ---------------------------------------------------------------------------
// Fake DeviceService — always reports plenty of RAM.
// ---------------------------------------------------------------------------

class _FakeDeviceService extends DeviceService {
  @override
  Future<DeviceInfo> analyzeDevice() async {
    return DeviceInfo(
      totalRamMB: 16384,
      availableRamMB: 12000,
      totalStorageMB: 128000,
      availableStorageMB: 64000,
      androidVersion: '14',
      isArm64: true,
    );
  }
}

// ---------------------------------------------------------------------------
// Test models
// ---------------------------------------------------------------------------

final List<ModelInfo> _litertModels = [
  ModelInfo(
    id: 'test-litert-1b',
    name: 'Test LiteRT 1B',
    description: 'test',
    url: 'https://example.com/test-1b.task',
    sizeBytes: 800000000,
    ramRequirement: '2GB',
    speed: 'Fast',
    fileName: 'test-1b.task',
    minRamMB: 2048,
    engine: AIEngine.litert,
  ),
  ModelInfo(
    id: 'test-litert-e2b',
    name: 'Test LiteRT E2B',
    description: 'test',
    url: 'https://example.com/test-e2b.task',
    sizeBytes: 1500000000,
    ramRequirement: '4GB',
    speed: 'Medium',
    fileName: 'test-e2b.task',
    minRamMB: 3072,
    engine: AIEngine.litert,
  ),
  ModelInfo(
    id: 'test-litert-e4b',
    name: 'Test LiteRT E4B',
    description: 'test',
    url: 'https://example.com/test-e4b.litertlm',
    sizeBytes: 3200000000,
    ramRequirement: '6GB',
    speed: 'Slow',
    fileName: 'test-e4b.litertlm',
    minRamMB: 5120,
    engine: AIEngine.litert,
  ),
];

/// Pick a random LiteRT model from the test set.
ModelInfo _randomLitertModel(Random rng) {
  return _litertModels[rng.nextInt(_litertModels.length)];
}

// ---------------------------------------------------------------------------
// Test body
// ---------------------------------------------------------------------------

void main() {
  group(
      'Property 28: Chat failure is contained and non-destructive '
      '(multi-engine-ai-models)', () {
    // --- Sub-property A: A LiteRT chat failure surfaces as AI_CHAT_FAILURE
    // and does NOT propagate an uncaught exception. ---
    test(
        'LiteRT chat failure surfaces as AIServiceException with AI_CHAT_FAILURE code',
        () async {
      final rng = Random(20240901);

      for (var i = 0; i < _iterations; i++) {
        final gguf = _FakeGgufEngine();
        final litert = _FailableLiteRtService();
        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: _FakeDeviceService(),
        );

        // Load a random LiteRT model successfully.
        final model = _randomLitertModel(rng);
        await router.loadModelInfo(model);

        // Configure chat to fail.
        litert.shouldFailNext = true;

        // The chat call must throw an AIServiceException with the correct code.
        // It must NOT throw an unhandled Exception.
        try {
          await router.chat('prompt-$i').toList();
          fail('Expected AIServiceException to be thrown');
        } on AIServiceException catch (e) {
          expect(e.errorCode, equals('AI_CHAT_FAILURE'),
              reason:
                  'Iteration $i: LiteRT chat error must be wrapped as AI_CHAT_FAILURE');
        } on Exception catch (e) {
          fail(
              'Iteration $i: Expected AIServiceException(AI_CHAT_FAILURE) but got '
              'uncontained exception: ${e.runtimeType}: $e');
        }
      }
    });

    // --- Sub-property B: After a chat failure, the active model remains loaded
    // (isModelLoaded == true, activeModel unchanged). ---
    test('after a chat failure, active model remains loaded and unchanged',
        () async {
      final rng = Random(20240902);

      for (var i = 0; i < _iterations; i++) {
        final gguf = _FakeGgufEngine();
        final litert = _FailableLiteRtService();
        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: _FakeDeviceService(),
        );

        final model = _randomLitertModel(rng);
        await router.loadModelInfo(model);

        // Confirm model is active before failure.
        expect(router.activeModel, equals(model));
        expect(router.isModelLoaded, isTrue);

        // Force a chat failure.
        litert.shouldFailNext = true;
        try {
          await router.chat('will-fail-$i').toList();
        } on AIServiceException {
          // Expected — swallow.
        }

        // After the failure, the active model is still the same.
        expect(router.activeModel, equals(model),
            reason:
                'Iteration $i: activeModel must remain unchanged after chat failure');
        expect(router.isModelLoaded, isTrue,
            reason:
                'Iteration $i: isModelLoaded must remain true after chat failure');
      }
    });

    // --- Sub-property C: After a chat failure, subsequent chat calls still
    // work (the failure is non-destructive). ---
    test('after a chat failure, subsequent chat calls succeed normally',
        () async {
      final rng = Random(20240903);

      for (var i = 0; i < _iterations; i++) {
        final gguf = _FakeGgufEngine();
        final litert = _FailableLiteRtService();
        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: _FakeDeviceService(),
        );

        final model = _randomLitertModel(rng);
        await router.loadModelInfo(model);

        // Force a failure.
        litert.shouldFailNext = true;
        try {
          await router.chat('fail-$i').toList();
        } on AIServiceException {
          // Expected.
        }

        // Now allow success.
        litert.shouldFailNext = false;

        // The next chat call must succeed and return tokens.
        final tokens = await router.chat('recover-$i').toList();
        expect(tokens, isNotEmpty,
            reason:
                'Iteration $i: chat must succeed after a previous failure');
        expect(tokens.first, equals('litert:recover-$i'),
            reason:
                'Iteration $i: recovered chat must delegate to LiteRT and return tokens');
      }
    });

    // --- Sub-property D: Alternating success/failure over many iterations
    // never corrupts state — failures are always contained and successes always
    // produce tokens. This simulates a flaky engine over a longer sequence. ---
    test(
        'alternating success and failure over many iterations never corrupts state',
        () async {
      final rng = Random(20240904);

      for (var i = 0; i < _iterations; i++) {
        final gguf = _FakeGgufEngine();
        final litert = _FailableLiteRtService();
        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: _FakeDeviceService(),
        );

        final model = _randomLitertModel(rng);
        await router.loadModelInfo(model);

        // Run a random sequence of 5-15 chat calls, each randomly succeeding
        // or failing.
        final seqLen = 5 + rng.nextInt(11);
        for (var j = 0; j < seqLen; j++) {
          final shouldFail = rng.nextBool();
          litert.shouldFailNext = shouldFail;

          if (shouldFail) {
            // Must throw AIServiceException with AI_CHAT_FAILURE, not an
            // uncontained exception.
            try {
              await router.chat('seq-$i-$j').toList();
              fail('Expected AIServiceException on iteration $i, call $j');
            } on AIServiceException catch (e) {
              expect(e.errorCode, equals('AI_CHAT_FAILURE'));
            }
          } else {
            // Must succeed and yield tokens.
            final tokens = await router.chat('seq-$i-$j').toList();
            expect(tokens, isNotEmpty,
                reason: 'Iteration $i, call $j: successful chat must yield tokens');
            expect(tokens.first, equals('litert:seq-$i-$j'));
          }

          // After each call (success or failure), the model stays active.
          expect(router.activeModel, equals(model),
              reason: 'Iteration $i, call $j: activeModel must stay unchanged');
          expect(router.isModelLoaded, isTrue,
              reason: 'Iteration $i, call $j: isModelLoaded must remain true');
        }
      }
    });
  });
}
