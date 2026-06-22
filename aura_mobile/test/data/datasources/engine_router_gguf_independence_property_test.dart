import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/data/datasources/engine_router.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';

// Feature: multi-engine-ai-models, Property 27: GGUF availability is
// independent of LiteRT
//
// "For any catalog, while the LiteRT engine is unavailable, every gguf model
//  remains selectable and loadable (its load succeeds and selection is enabled)."
//
// **Validates: Requirements 10.3**
//
// The test mocks LiteRtService to throw on initialize/loadModel (simulating
// LiteRT being unavailable), then verifies that GGUF models can still be
// loaded, queried, and chatted through the EngineRouter. Uses the
// generator-based approach (Random + iterations >= 100), NOT glados.

const int _iterations = 150;

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fake GGUF engine that always loads successfully and returns distinguishing
/// markers so we can verify correct delegation.
class _FakeGgufEngine extends Fake implements LLMService {
  bool _loaded = false;
  String? lastLoadedPath;
  String? lastChatPrompt;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {
    lastLoadedPath = modelPath;
    _loaded = true;
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
    yield 'gguf-response:$prompt';
  }
}

/// Fake LiteRtService that simulates LiteRT being completely unavailable:
/// - [initialize] always throws (engine initialization failure).
/// - [loadModel] always throws (engine load failure).
/// This represents the scenario where the LiteRT engine cannot start at all
/// (Requirement 10.3, 10.6).
class _FailingLiteRtService extends Fake implements LiteRtService {
  bool initializeCalled = false;
  bool loadModelCalled = false;
  bool _initialized = false;

  /// Controls how initialize fails. When true, throws on initialize.
  final bool failOnInitialize;

  /// Controls how loadModel fails. When true, throws on loadModel.
  final bool failOnLoad;

  _FailingLiteRtService({
    this.failOnInitialize = true,
    this.failOnLoad = true,
  });

  @override
  Future<void> initialize() async {
    initializeCalled = true;
    if (failOnInitialize) {
      throw AIServiceException(
        message: 'LiteRT engine initialization failed',
        technicalDetails: 'Simulated LiteRT init failure',
        recoverySuggestion: 'Try again later',
        errorCode: 'AI_LITERT_INIT_FAILURE',
      );
    }
    _initialized = true;
  }

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> loadModel(String modelPath) async {
    loadModelCalled = true;
    if (failOnLoad) {
      throw AIServiceException.modelLoadFailed(modelPath, 'LiteRT unavailable');
    }
  }

  @override
  bool get isModelLoaded => false;

  @override
  ModelTier get modelTier => ModelTier.medium;

  @override
  set modelTier(ModelTier tier) {}

  @override
  bool get supportsToolCalling => false;

  @override
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) {
    throw AIServiceException.modelNotLoaded();
  }
}

/// Fake DeviceService that always reports enough RAM for any GGUF model.
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
// Helpers
// ---------------------------------------------------------------------------

/// Returns all GGUF models from the catalog.
List<ModelInfo> _allGgufModels() =>
    modelCatalog.where((m) => m.engine == AIEngine.gguf).toList();

/// Returns a random GGUF model from the catalog.
ModelInfo _randomGgufModel(Random rng) {
  final models = _allGgufModels();
  return models[rng.nextInt(models.length)];
}

/// Returns a random LiteRT model from the catalog.
ModelInfo _randomLitertModel(Random rng) {
  final models = modelCatalog.where((m) => m.engine == AIEngine.litert).toList();
  return models[rng.nextInt(models.length)];
}

// ---------------------------------------------------------------------------
// Test body
// ---------------------------------------------------------------------------

void main() {
  group(
      'Property 27: GGUF availability is independent of LiteRT '
      '(multi-engine-ai-models)', () {
    // --- Sub-property A: When LiteRT initialization fails, GGUF models can
    // still be loaded successfully. Runs >= 100 generated cases. ---
    test(
        'GGUF models load successfully when LiteRT initialization fails',
        () async {
      final rng = Random(20240901);

      for (var i = 0; i < _iterations; i++) {
        final gguf = _FakeGgufEngine();
        final litert = _FailingLiteRtService(
          failOnInitialize: true,
          failOnLoad: true,
        );
        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: _FakeDeviceService(),
        );

        // Initialize the router (GGUF eager, LiteRT lazy).
        await router.initialize();

        // Pick a random GGUF model.
        final model = _randomGgufModel(rng);

        // Load should succeed — GGUF path is independent of LiteRT.
        await router.loadModelInfo(model);

        expect(router.activeModel, equals(model),
            reason: 'GGUF model "${model.id}" should be active despite '
                'LiteRT being unavailable (iteration $i)');
        expect(router.isModelLoaded, isTrue,
            reason: 'isModelLoaded should be true after GGUF load');
        expect(gguf.lastLoadedPath, equals(model.fileName),
            reason: 'GGUF engine should receive the load call');
      }
    });

    // --- Sub-property B: After a LiteRT model load fails (because LiteRT is
    // unavailable), GGUF models can still be loaded and used. This verifies
    // that a failed LiteRT load does not poison the GGUF path. ---
    test(
        'GGUF models remain loadable after a LiteRT model load fails',
        () async {
      final rng = Random(20240902);

      for (var i = 0; i < _iterations; i++) {
        final gguf = _FakeGgufEngine();
        final litert = _FailingLiteRtService(
          failOnInitialize: true,
          failOnLoad: true,
        );
        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: _FakeDeviceService(),
        );
        await router.initialize();

        // Attempt to load a LiteRT model — must fail because LiteRT is broken.
        final litertModel = _randomLitertModel(rng);
        await expectLater(
          router.loadModelInfo(litertModel),
          throwsA(anything),
          reason: 'LiteRT load of "${litertModel.id}" must fail '
              'when LiteRT is unavailable',
        );

        // Now load a GGUF model — must succeed.
        final ggufModel = _randomGgufModel(rng);
        await router.loadModelInfo(ggufModel);

        expect(router.activeModel, equals(ggufModel),
            reason: 'GGUF model "${ggufModel.id}" should be active after '
                'a failed LiteRT load (iteration $i)');
        expect(router.isModelLoaded, isTrue);
      }
    });

    // --- Sub-property C: When LiteRT is unavailable, chat still works for
    // GGUF models. The router correctly delegates chat to the GGUF engine. ---
    test(
        'chat works for GGUF models when LiteRT is unavailable',
        () async {
      final rng = Random(20240903);

      for (var i = 0; i < _iterations; i++) {
        final gguf = _FakeGgufEngine();
        final litert = _FailingLiteRtService(
          failOnInitialize: true,
          failOnLoad: true,
        );
        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: _FakeDeviceService(),
        );
        await router.initialize();

        // Load a random GGUF model.
        final model = _randomGgufModel(rng);
        await router.loadModelInfo(model);

        // Chat with a random prompt.
        final prompt = 'test-prompt-$i-${rng.nextInt(10000)}';
        final tokens = await router.chat(prompt).toList();

        expect(tokens, isNotEmpty,
            reason: 'Chat should produce tokens for GGUF model "${model.id}"');
        expect(tokens.first, contains('gguf-response:'),
            reason: 'Chat response should come from the GGUF engine');
        expect(gguf.lastChatPrompt, equals(prompt),
            reason: 'GGUF engine should receive the chat prompt');
      }
    });

    // --- Sub-property D: Multiple consecutive GGUF loads all succeed while
    // LiteRT is down, and switching between different GGUF models works. ---
    test(
        'switching between GGUF models works when LiteRT is unavailable',
        () async {
      final rng = Random(20240904);

      for (var i = 0; i < _iterations; i++) {
        final gguf = _FakeGgufEngine();
        final litert = _FailingLiteRtService(
          failOnInitialize: true,
          failOnLoad: true,
        );
        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: _FakeDeviceService(),
        );
        await router.initialize();

        // Load a sequence of 2–4 random GGUF models. Each should succeed.
        final seqLen = 2 + rng.nextInt(3);
        ModelInfo lastModel = _randomGgufModel(rng);

        for (var j = 0; j < seqLen; j++) {
          lastModel = _randomGgufModel(rng);
          await router.loadModelInfo(lastModel);
          expect(router.activeModel, equals(lastModel),
              reason: 'GGUF model "${lastModel.id}" should be active '
                  '(sequence step $j, iteration $i)');
        }

        // Chat delegates to GGUF for the last loaded model.
        final prompt = 'final-$i';
        final tokens = await router.chat(prompt).toList();
        expect(tokens.first, contains('gguf-response:'),
            reason: 'Chat should delegate to GGUF after model switching');
      }
    });

    // --- Sub-property E: Interleaved LiteRT failures and GGUF loads — every
    // GGUF load succeeds regardless of how many LiteRT loads have failed. ---
    test(
        'interleaved LiteRT failures do not affect GGUF availability',
        () async {
      final rng = Random(20240905);

      for (var i = 0; i < _iterations; i++) {
        final gguf = _FakeGgufEngine();
        final litert = _FailingLiteRtService(
          failOnInitialize: true,
          failOnLoad: true,
        );
        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: _FakeDeviceService(),
        );
        await router.initialize();

        // Interleave: attempt LiteRT (fail), load GGUF (succeed), repeat.
        final steps = 2 + rng.nextInt(4);
        for (var j = 0; j < steps; j++) {
          // Attempt a LiteRT load that will fail.
          final litertModel = _randomLitertModel(rng);
          await expectLater(
            router.loadModelInfo(litertModel),
            throwsA(anything),
            reason: 'LiteRT load must fail (step $j, iteration $i)',
          );

          // Load a GGUF model — must succeed.
          final ggufModel = _randomGgufModel(rng);
          await router.loadModelInfo(ggufModel);
          expect(router.activeModel, equals(ggufModel),
              reason: 'GGUF model "${ggufModel.id}" should be active after '
                  'LiteRT failure (step $j, iteration $i)');

          // Chat must work.
          final tokens = await router.chat('step-$j-$i').toList();
          expect(tokens, isNotEmpty,
              reason: 'Chat must produce tokens (step $j, iteration $i)');
        }
      }
    });
  });
}
