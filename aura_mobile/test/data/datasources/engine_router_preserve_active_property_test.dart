import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/data/datasources/engine_router.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';

// Feature: multi-engine-ai-models, Property 3
//
// "For any prior router state and any loadModel attempt that does not succeed —
//  whether because the engine reports a load failure, the format is unsupported,
//  the LiteRT engine fails to initialize (including the 30-second timeout), or
//  the RAM gate blocks the load — the router returns an error and the active
//  model after the attempt is identical to the active model before it, and that
//  previous model remains loaded and usable."
//
// Validates: Requirements 1.5, 2.7, 6.8, 8.5, 10.2, 10.6
//
// The test generates random sequences of loads where an initial successful load
// establishes the active model, and subsequent failing loads (RAM gate block,
// engine throw, engine reports not-loaded) must not disturb the active model.
// Each property runs >= 100 generated cases using the generator-based approach
// (Random + iterations), NOT glados.

const int _iterations = 150;

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Tracks the last prompt passed to `chat` so we can verify delegation.
class _FakeGGUFEngine extends Fake implements LLMService {
  bool _loaded = false;
  bool shouldFail = false;
  bool reportNotLoaded = false;
  String? lastChatPrompt;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {
    if (shouldFail) {
      throw AIServiceException.modelLoadFailed(modelPath, 'simulated GGUF failure');
    }
    _loaded = !reportNotLoaded;
  }

  @override
  bool get isModelLoaded => _loaded;

  @override
  ModelTier get modelTier => ModelTier.large;

  @override
  bool get supportsToolCalling => false;

  @override
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) async* {
    lastChatPrompt = prompt;
    yield 'gguf-response';
  }
}

/// Fake LiteRtService whose load behavior is controllable.
class _FakeLiteRtService extends Fake implements LiteRtService {
  bool _loaded = false;
  bool _initialized = false;
  bool shouldFail = false;
  bool reportNotLoaded = false;
  String? lastChatPrompt;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> loadModel(String modelPath) async {
    if (shouldFail) {
      throw AIServiceException.modelLoadFailed(modelPath, 'simulated LiteRT failure');
    }
    _loaded = !reportNotLoaded;
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
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) async* {
    lastChatPrompt = prompt;
    yield 'litert-response';
  }
}

/// Fake DeviceService whose reported RAM is controllable.
class _FakeDeviceService extends DeviceService {
  int totalRamMB;

  _FakeDeviceService({this.totalRamMB = 8192});

  @override
  Future<DeviceInfo> analyzeDevice() async {
    return DeviceInfo(
      totalRamMB: totalRamMB,
      availableRamMB: totalRamMB,
      totalStorageMB: 64000,
      availableStorageMB: 32000,
      androidVersion: '14',
      isArm64: true,
    );
  }
}

// ---------------------------------------------------------------------------
// Test model generators
// ---------------------------------------------------------------------------

/// A set of synthetic models for testing. Realistic enough to cover both
/// engines, varying RAM requirements, and varied IDs.
final List<ModelInfo> _testModels = [
  ModelInfo(
    id: 'test-gguf-small',
    name: 'Test GGUF Small',
    description: 'test',
    url: 'https://example.com/test.gguf',
    sizeBytes: 500000000,
    ramRequirement: '2GB',
    speed: 'Fast',
    fileName: 'test-small.gguf',
    minRamMB: 1536,
    engine: AIEngine.gguf,
  ),
  ModelInfo(
    id: 'test-gguf-large',
    name: 'Test GGUF Large',
    description: 'test',
    url: 'https://example.com/test-large.gguf',
    sizeBytes: 4000000000,
    ramRequirement: '8GB',
    speed: 'Slow',
    fileName: 'test-large.gguf',
    minRamMB: 7500,
    engine: AIEngine.gguf,
  ),
  ModelInfo(
    id: 'test-litert-small',
    name: 'Test LiteRT Small',
    description: 'test',
    url: 'https://example.com/test.task',
    sizeBytes: 600000000,
    ramRequirement: '2GB',
    speed: 'Fast',
    fileName: 'test-small.task',
    minRamMB: 2048,
    engine: AIEngine.litert,
  ),
  ModelInfo(
    id: 'test-litert-large',
    name: 'Test LiteRT Large',
    description: 'test',
    url: 'https://example.com/test-large.litertlm',
    sizeBytes: 4400000000,
    ramRequirement: '6GB',
    speed: 'Slow',
    fileName: 'test-large.litertlm',
    minRamMB: 6144,
    engine: AIEngine.litert,
  ),
];

/// The type of failure to inject on the load attempt.
enum _FailureMode {
  /// DeviceService reports 0 RAM (undeterminable).
  ramUndeterminable,

  /// Device RAM is below model's minRamMB.
  ramInsufficient,

  /// Engine throws an exception during loadModel.
  engineThrows,

  /// Engine's loadModel completes but reports isModelLoaded == false.
  engineReportsNotLoaded,
}

void main() {
  group('Property 3: Failed or blocked load preserves the previous active '
      'model (multi-engine-ai-models)', () {
    // --- Core property: after a successful load of model A, any failing
    // load of model B leaves activeModel == A and chat delegates to A's engine.
    // Runs >= 100 generated cases over random model pairs and failure modes. ---
    test('a failed load after a successful load preserves the active model',
        () async {
      final rng = Random(20240715);

      for (var i = 0; i < _iterations; i++) {
        // Pick a random initial model (A) that will load successfully.
        final modelA = _testModels[rng.nextInt(_testModels.length)];

        // Pick a second model (B) that will fail to load.
        final modelB = _testModels[rng.nextInt(_testModels.length)];

        // Pick a random failure mode for B's load attempt.
        final failureMode =
            _FailureMode.values[rng.nextInt(_FailureMode.values.length)];

        // Set up fakes.
        final gguf = _FakeGGUFEngine();
        final litert = _FakeLiteRtService();
        final deviceService = _FakeDeviceService(totalRamMB: 8192);

        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: deviceService,
        );
        await router.initialize();

        // --- Step 1: successfully load model A. ---
        // Ensure enough RAM and engines succeed.
        deviceService.totalRamMB = 8192;
        gguf.shouldFail = false;
        gguf.reportNotLoaded = false;
        litert.shouldFail = false;
        litert.reportNotLoaded = false;

        await router.loadModelInfo(modelA);
        expect(router.activeModel, equals(modelA),
            reason: 'model A should be active after a successful load');

        // --- Step 2: attempt to load model B, which must fail. ---
        switch (failureMode) {
          case _FailureMode.ramUndeterminable:
            deviceService.totalRamMB = 0;
            break;
          case _FailureMode.ramInsufficient:
            // Set device RAM to less than B's requirement.
            deviceService.totalRamMB = modelB.minRamMB - 1;
            break;
          case _FailureMode.engineThrows:
            if (modelB.engine == AIEngine.gguf) {
              gguf.shouldFail = true;
            } else {
              litert.shouldFail = true;
            }
            break;
          case _FailureMode.engineReportsNotLoaded:
            if (modelB.engine == AIEngine.gguf) {
              gguf.reportNotLoaded = true;
            } else {
              litert.reportNotLoaded = true;
            }
            break;
        }

        // The load must throw.
        await expectLater(
          router.loadModelInfo(modelB),
          throwsA(anything),
          reason:
              'load of model B ("${modelB.id}") with failure mode $failureMode '
              'must throw',
        );

        // --- Step 3: verify invariant. ---
        expect(router.activeModel, equals(modelA),
            reason: 'after failed load of B ("${modelB.id}") with failure mode '
                '$failureMode, active model must still be A ("${modelA.id}")');

        // Verify chat still delegates to A's engine.
        final testPrompt = 'test-prompt-$i';
        // Reset engine fakes for the chat delegation check.
        gguf.shouldFail = false;
        gguf.reportNotLoaded = false;
        litert.shouldFail = false;
        litert.reportNotLoaded = false;
        deviceService.totalRamMB = 8192;

        final tokens = await router.chat(testPrompt).toList();
        expect(tokens, isNotEmpty,
            reason: 'chat must still produce tokens from the active model');

        if (modelA.engine == AIEngine.gguf) {
          expect(gguf.lastChatPrompt, equals(testPrompt),
              reason: 'chat must delegate to the GGUF engine for gguf model A');
        } else {
          expect(litert.lastChatPrompt, equals(testPrompt),
              reason:
                  'chat must delegate to the LiteRT engine for litert model A');
        }
      }
    });

    // --- Variant: a sequence of multiple failing loads never disturbs the
    // initial active model. ---
    test('multiple consecutive failing loads all preserve the same active model',
        () async {
      final rng = Random(98765);

      for (var i = 0; i < 50; i++) {
        final modelA = _testModels[rng.nextInt(_testModels.length)];

        final gguf = _FakeGGUFEngine();
        final litert = _FakeLiteRtService();
        final deviceService = _FakeDeviceService(totalRamMB: 8192);

        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: deviceService,
        );
        await router.initialize();

        // Successfully load model A.
        await router.loadModelInfo(modelA);
        expect(router.activeModel, equals(modelA));

        // Attempt a sequence of 3–6 failing loads.
        final failCount = 3 + rng.nextInt(4);
        for (var j = 0; j < failCount; j++) {
          final badModel = _testModels[rng.nextInt(_testModels.length)];
          final failMode =
              _FailureMode.values[rng.nextInt(_FailureMode.values.length)];

          // Configure failure.
          switch (failMode) {
            case _FailureMode.ramUndeterminable:
              deviceService.totalRamMB = 0;
              break;
            case _FailureMode.ramInsufficient:
              deviceService.totalRamMB = badModel.minRamMB - 1;
              break;
            case _FailureMode.engineThrows:
              deviceService.totalRamMB = 8192;
              gguf.shouldFail = badModel.engine == AIEngine.gguf;
              litert.shouldFail = badModel.engine == AIEngine.litert;
              break;
            case _FailureMode.engineReportsNotLoaded:
              deviceService.totalRamMB = 8192;
              gguf.shouldFail = false;
              litert.shouldFail = false;
              gguf.reportNotLoaded = badModel.engine == AIEngine.gguf;
              litert.reportNotLoaded = badModel.engine == AIEngine.litert;
              break;
          }

          await expectLater(
            router.loadModelInfo(badModel),
            throwsA(anything),
            reason: 'failing load #$j of "${badModel.id}" ($failMode) must throw',
          );

          // Invariant holds after every failed load.
          expect(router.activeModel, equals(modelA),
              reason: 'active model must be A ("${modelA.id}") after '
                  'failing load #$j');

          // Reset fakes between failures to avoid cross-contamination.
          gguf.shouldFail = false;
          gguf.reportNotLoaded = false;
          litert.shouldFail = false;
          litert.reportNotLoaded = false;
        }

        // After the sequence, chat still delegates to A's engine.
        deviceService.totalRamMB = 8192;
        final tokens = await router.chat('verify-$i').toList();
        expect(tokens, isNotEmpty);
        if (modelA.engine == AIEngine.gguf) {
          expect(gguf.lastChatPrompt, equals('verify-$i'));
        } else {
          expect(litert.lastChatPrompt, equals('verify-$i'));
        }
      }
    });

    // --- Edge case: no prior active model. A failed load must leave
    // activeModel as null and chat must error. ---
    test('a failed load with no prior active model leaves activeModel null',
        () async {
      final rng = Random(55555);

      for (var i = 0; i < _iterations; i++) {
        final model = _testModels[rng.nextInt(_testModels.length)];
        final failMode =
            _FailureMode.values[rng.nextInt(_FailureMode.values.length)];

        final gguf = _FakeGGUFEngine();
        final litert = _FakeLiteRtService();
        final deviceService = _FakeDeviceService(totalRamMB: 8192);

        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: deviceService,
        );
        await router.initialize();

        // Configure failure.
        switch (failMode) {
          case _FailureMode.ramUndeterminable:
            deviceService.totalRamMB = 0;
            break;
          case _FailureMode.ramInsufficient:
            deviceService.totalRamMB = model.minRamMB - 1;
            break;
          case _FailureMode.engineThrows:
            if (model.engine == AIEngine.gguf) {
              gguf.shouldFail = true;
            } else {
              litert.shouldFail = true;
            }
            break;
          case _FailureMode.engineReportsNotLoaded:
            if (model.engine == AIEngine.gguf) {
              gguf.reportNotLoaded = true;
            } else {
              litert.reportNotLoaded = true;
            }
            break;
        }

        await expectLater(
          router.loadModelInfo(model),
          throwsA(anything),
          reason: 'load of "${model.id}" with $failMode must fail',
        );

        expect(router.activeModel, isNull,
            reason: 'activeModel must remain null when no prior model existed '
                'and the load failed ($failMode)');

        // Chat must error (no model loaded).
        expect(
          () => router.chat('should-error'),
          throwsA(isA<AIServiceException>()),
          reason: 'chat with no active model must throw',
        );
      }
    });
  });
}
