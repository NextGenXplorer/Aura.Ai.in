import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/data/datasources/engine_router.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';

// Feature: multi-engine-ai-models, Property 2: Engine selection commits only on success
//
// "For any model, a loadModelInfo call selects the engine by the model's engine
//  field (gguf → GGUF_Engine, litert → LiteRT_Engine) and sets that model as
//  the active model only after the selected engine reports isModelLoaded == true."
//
// **Validates: Requirements 1.4**
//
// The property exercises the commit-on-success invariant: when a load through
// the delegate engine succeeds (isModelLoaded == true), activeModel must be
// updated to the loaded model; when the delegate engine fails or reports
// isModelLoaded == false, activeModel must remain unchanged (null or whatever
// was set prior).
//
// We mock both engines and the DeviceService so the test controls success vs
// failure outcomes. Random model choices (both GGUF and LiteRT) and random
// success/failure outcomes verify the invariant over many cases.
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. The
// random property runs >= 100 generated cases.

const int _iterations = 150;

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// A fake [LLMService] (GGUF engine) whose load outcome is controllable.
class _FakeGgufEngine implements LLMService {
  bool _loaded = false;
  bool shouldFail = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {
    if (shouldFail) {
      _loaded = false;
      throw AIServiceException.modelLoadFailed(modelPath, 'simulated failure');
    }
    _loaded = true;
  }

  @override
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) {
    return const Stream.empty();
  }

  @override
  bool get isModelLoaded => _loaded;

  @override
  ModelTier get modelTier => ModelTier.medium;

  @override
  bool get supportsToolCalling => false;
}

/// A fake [LiteRtService] whose load outcome is controllable.
class _FakeLiteRtEngine implements LiteRtService {
  bool _loaded = false;
  bool _initialized = false;
  bool shouldFail = false;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> loadModel(String modelPath) async {
    if (shouldFail) {
      _loaded = false;
      throw AIServiceException.modelLoadFailed(modelPath, 'simulated failure');
    }
    _loaded = true;
  }

  @override
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) {
    return const Stream.empty();
  }

  @override
  bool get isModelLoaded => _loaded;

  @override
  ModelTier get modelTier => _tier;

  ModelTier _tier = ModelTier.medium;

  @override
  set modelTier(ModelTier tier) => _tier = tier;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get supportsToolCalling => false;

  // LiteRtService-specific members not exercised by the router.
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fake [DeviceService] that always reports ample RAM so the RAM gate never
/// blocks. The property under test is commit-on-success semantics, not the RAM
/// gate (that's Property 25).
class _FakeDeviceService extends DeviceService {
  @override
  Future<DeviceInfo> analyzeDevice() async {
    return DeviceInfo(
      totalRamMB: 16384,
      availableRamMB: 12000,
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

/// A subset of catalog models covering both engines for generation.
final _ggufModels = modelCatalog.where((m) => m.engine == AIEngine.gguf).toList();
final _litertModels =
    modelCatalog.where((m) => m.engine == AIEngine.litert).toList();

/// Picks a random model from the full catalog.
ModelInfo _randomModel(Random rng) {
  return modelCatalog[rng.nextInt(modelCatalog.length)];
}

/// Picks a random GGUF model.
ModelInfo _randomGgufModel(Random rng) {
  return _ggufModels[rng.nextInt(_ggufModels.length)];
}

/// Picks a random LiteRT model.
ModelInfo _randomLitertModel(Random rng) {
  return _litertModels[rng.nextInt(_litertModels.length)];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Property 2: Engine selection commits only on success '
      '(multi-engine-ai-models)', () {
    late _FakeGgufEngine gguf;
    late _FakeLiteRtEngine litert;
    late _FakeDeviceService device;
    late EngineRouter router;

    setUp(() {
      gguf = _FakeGgufEngine();
      litert = _FakeLiteRtEngine();
      device = _FakeDeviceService();
      router = EngineRouter(
        ggufEngine: gguf,
        litertEngine: litert,
        deviceService: device,
      );
    });

    // --- Core invariant: when the engine reports success (isModelLoaded ==
    // true), activeModel is committed to the loaded model. ---
    test('successful load commits activeModel for random models', () async {
      final rng = Random(20240802);
      for (var i = 0; i < _iterations; i++) {
        // Fresh router per iteration to test from a clean state.
        gguf = _FakeGgufEngine();
        litert = _FakeLiteRtEngine();
        router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: device,
        );

        final model = _randomModel(rng);
        // Ensure the delegate engine will succeed.
        gguf.shouldFail = false;
        litert.shouldFail = false;

        await router.loadModelInfo(model);

        expect(router.activeModel, equals(model),
            reason: 'after a successful load of "${model.id}" '
                '(${model.engine.name}), activeModel must be that model');
      }
    });

    // --- When the engine throws during load, activeModel stays null
    // (from a clean state). ---
    test('failed load from clean state leaves activeModel null', () async {
      final rng = Random(20240803);
      for (var i = 0; i < _iterations; i++) {
        gguf = _FakeGgufEngine();
        litert = _FakeLiteRtEngine();
        router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: device,
        );

        final model = _randomModel(rng);
        // Force the delegate engine to fail.
        if (model.engine == AIEngine.gguf) {
          gguf.shouldFail = true;
        } else {
          litert.shouldFail = true;
        }

        await expectLater(
          router.loadModelInfo(model),
          throwsA(anything),
          reason: 'a failing load of "${model.id}" must throw',
        );

        expect(router.activeModel, isNull,
            reason: 'after a failed load of "${model.id}" from a clean state, '
                'activeModel must remain null');
      }
    });

    // --- When a load fails after a prior success, activeModel retains the
    // previously committed model. ---
    test('failed load after a prior success retains previous activeModel',
        () async {
      final rng = Random(20240804);
      for (var i = 0; i < _iterations; i++) {
        gguf = _FakeGgufEngine();
        litert = _FakeLiteRtEngine();
        router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: device,
        );

        // First: succeed a load so activeModel is non-null.
        final firstModel = _randomModel(rng);
        gguf.shouldFail = false;
        litert.shouldFail = false;
        await router.loadModelInfo(firstModel);
        expect(router.activeModel, equals(firstModel));

        // Second: attempt a load that fails — could be same or different engine.
        final secondModel = _randomModel(rng);
        if (secondModel.engine == AIEngine.gguf) {
          gguf.shouldFail = true;
        } else {
          litert.shouldFail = true;
        }

        await expectLater(
          router.loadModelInfo(secondModel),
          throwsA(anything),
        );

        // The active model must be the first successful one, unchanged.
        expect(router.activeModel, equals(firstModel),
            reason: 'after a failed load of "${secondModel.id}", '
                'activeModel must remain "${firstModel.id}"');
      }
    });

    // --- Engine selection correctness: gguf models go through the GGUF engine,
    // litert models go through the LiteRT engine. Verified by checking that
    // only the correct engine is flagged as loaded after success. ---
    test('engine selection routes to the correct delegate', () async {
      final rng = Random(20240805);
      for (var i = 0; i < _iterations; i++) {
        gguf = _FakeGgufEngine();
        litert = _FakeLiteRtEngine();
        router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: device,
        );

        gguf.shouldFail = false;
        litert.shouldFail = false;

        final model = _randomModel(rng);
        await router.loadModelInfo(model);

        if (model.engine == AIEngine.gguf) {
          expect(gguf.isModelLoaded, isTrue,
              reason: 'gguf model "${model.id}" must load through GGUF engine');
          // LiteRT engine should not have been loaded.
          expect(litert.isModelLoaded, isFalse,
              reason: 'litert engine must not be loaded for a gguf model');
        } else {
          expect(litert.isModelLoaded, isTrue,
              reason:
                  'litert model "${model.id}" must load through LiteRT engine');
          // GGUF engine should not have been loaded.
          expect(gguf.isModelLoaded, isFalse,
              reason: 'gguf engine must not be loaded for a litert model');
        }
      }
    });

    // --- The commit happens ONLY after isModelLoaded == true. Verify
    // by having an engine that does not throw but sets isModelLoaded = false
    // (simulating a load that completes without error but the model isn't
    // actually loaded). ---
    test('engine reporting not-loaded after non-throwing load does not commit',
        () async {
      // Custom engine that completes without throwing but stays not-loaded.
      final sneakyGguf = _SneakyNotLoadedGgufEngine();
      final sneakyLitert = _SneakyNotLoadedLiteRtEngine();
      final rng = Random(20240806);

      for (var i = 0; i < _iterations; i++) {
        final testRouter = EngineRouter(
          ggufEngine: sneakyGguf,
          litertEngine: sneakyLitert,
          deviceService: device,
        );

        final model = _randomModel(rng);

        // The load completes without throwing, but isModelLoaded remains false.
        // The router must NOT commit the model; it should throw because the
        // engine did not report loaded.
        await expectLater(
          testRouter.loadModelInfo(model),
          throwsA(anything),
          reason:
              'when engine reports not-loaded for "${model.id}", must throw',
        );

        expect(testRouter.activeModel, isNull,
            reason: 'when the engine reports not-loaded for "${model.id}", '
                'activeModel must not be committed');
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Additional test helpers
// ---------------------------------------------------------------------------

/// An LLMService that never throws during loadModel but always reports
/// isModelLoaded == false afterward. This tests the isModelLoaded check
/// in the router's commit logic.
class _SneakyNotLoadedGgufEngine implements LLMService {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {
    // Does not throw — but remains not-loaded.
  }

  @override
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) {
    return const Stream.empty();
  }

  @override
  bool get isModelLoaded => false;

  @override
  ModelTier get modelTier => ModelTier.medium;

  @override
  bool get supportsToolCalling => false;
}

/// A LiteRtService that never throws during loadModel but always reports
/// isModelLoaded == false afterward.
class _SneakyNotLoadedLiteRtEngine implements LiteRtService {
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> loadModel(String modelPath) async {
    // Does not throw — but remains not-loaded.
  }

  @override
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) {
    return const Stream.empty();
  }

  @override
  bool get isModelLoaded => false;

  @override
  ModelTier get modelTier => _tier;

  ModelTier _tier = ModelTier.medium;

  @override
  set modelTier(ModelTier tier) => _tier = tier;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get supportsToolCalling => false;

  // LiteRtService-specific members not exercised by the router.
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
