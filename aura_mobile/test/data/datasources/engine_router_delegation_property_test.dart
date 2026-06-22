import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/data/datasources/engine_router.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// Feature: multi-engine-ai-models, Property 1: Active-engine delegation
//
// "For any sequence of operations that ends with a successful loadModel of a
//  model whose engine field is E, every subsequent non-loadModel call (chat,
//  isModelLoaded, modelTier) is delegated to the engine E; and when no model
//  is active, every such call returns a 'no model loaded' error (for
//  chat/modelTier) or false (for isModelLoaded) and leaves the active model
//  unset."
//
// **Validates: Requirements 1.3, 1.6, 1.7, 1.9, 2.2**
//
// The test uses fake implementations of LLMService, LiteRtService, and
// DeviceService to test the router in isolation. glados is not a project
// dependency; per the design's testing strategy this uses an equivalent
// generator-based approach layered on package:test. Each property runs >= 100
// generated cases.

const int _iterations = 150;

// ---------------------------------------------------------------------------
// Fake GGUF engine
// ---------------------------------------------------------------------------

/// A fake GGUF engine that tracks whether it is the target of delegation.
/// [loadModel] always succeeds (sets [_loaded] to true). [chat] yields a
/// distinguishing marker so we can verify the router delegated to this engine.
class _FakeGgufEngine implements LLMService {
  bool _loaded = false;
  ModelTier _tier = ModelTier.large;
  int chatCallCount = 0;
  int isModelLoadedCallCount = 0;
  int modelTierCallCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {
    _loaded = true;
    // Derive tier from file name like the real engine.
    _tier = LLMServiceImpl.modelTierForPath(modelPath);
  }

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    chatCallCount++;
    return Stream.value('gguf:$prompt');
  }

  @override
  bool get isModelLoaded {
    isModelLoadedCallCount++;
    return _loaded;
  }

  @override
  ModelTier get modelTier {
    modelTierCallCount++;
    return _tier;
  }

  @override
  bool get supportsToolCalling => false;
}

// ---------------------------------------------------------------------------
// Fake LiteRT engine
// ---------------------------------------------------------------------------

/// Minimal fake [InferenceModel] — not exercised beyond [loadModel].
class _FakeInferenceModel extends Fake implements InferenceModel {}

/// Fake [ModelFileManager] accepting the deprecated setModelPath call.
class _FakeModelManager extends Fake implements ModelFileManager {
  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {}
}

/// Fake [FlutterGemmaPlugin] that always succeeds on createModel.
class _FakeGemmaPlugin extends Fake implements FlutterGemmaPlugin {
  final _FakeModelManager _manager = _FakeModelManager();

  @override
  ModelFileManager get modelManager => _manager;

  @override
  Future<InferenceModel> createModel({
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.task,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
    int? maxNumImages,
    bool supportImage = false,
    bool supportAudio = false,
  }) async {
    return _FakeInferenceModel();
  }
}

/// A [LiteRtService] subclass that tracks delegation calls via counters,
/// overriding chat to yield a distinguishing marker without needing a real
/// session.
class _TrackingLiteRtService extends LiteRtService {
  int chatCallCount = 0;
  int isModelLoadedCallCount = 0;
  int modelTierCallCount = 0;

  _TrackingLiteRtService() : super(gemma: _FakeGemmaPlugin());

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    chatCallCount++;
    return Stream.value('litert:$prompt');
  }

  @override
  bool get isModelLoaded {
    isModelLoadedCallCount++;
    return super.isModelLoaded;
  }

  @override
  ModelTier get modelTier {
    modelTierCallCount++;
    return super.modelTier;
  }
}

// ---------------------------------------------------------------------------
// Fake DeviceService — always reports plenty of RAM so loads succeed.
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
// Test model generators
// ---------------------------------------------------------------------------

/// Generate a random GGUF ModelInfo from the catalog.
ModelInfo _randomGgufModel(Random rng) {
  final ggufModels =
      modelCatalog.where((m) => m.engine == AIEngine.gguf).toList();
  return ggufModels[rng.nextInt(ggufModels.length)];
}

/// Generate a random LiteRT ModelInfo from the catalog.
ModelInfo _randomLitertModel(Random rng) {
  final litertModels =
      modelCatalog.where((m) => m.engine == AIEngine.litert).toList();
  return litertModels[rng.nextInt(litertModels.length)];
}

/// Generate a random ModelInfo from either engine.
ModelInfo _randomModel(Random rng) {
  return rng.nextBool() ? _randomGgufModel(rng) : _randomLitertModel(rng);
}

// ---------------------------------------------------------------------------
// Test body
// ---------------------------------------------------------------------------

void main() {
  group(
      'Property 1: Active-engine delegation (multi-engine-ai-models)', () {
    // --- Sub-property A: When no model is active, isModelLoaded == false,
    // chat throws "no model loaded", and activeModel is null. ---
    test('no active model: isModelLoaded is false, chat throws, activeModel is null',
        () {
      final gguf = _FakeGgufEngine();
      final litert = _TrackingLiteRtService();
      final router = EngineRouter(
        ggufEngine: gguf,
        litertEngine: litert,
        deviceService: _FakeDeviceService(),
      );

      expect(router.isModelLoaded, isFalse);
      expect(router.activeModel, isNull);
      expect(
        () => router.chat('hello'),
        throwsA(isA<AIServiceException>()),
      );
    });

    // --- Sub-property B: After a successful GGUF load, chat/isModelLoaded/
    // modelTier delegate to the GGUF engine. Runs >= 100 cases. ---
    test('after GGUF load, all calls delegate to GGUF engine', () async {
      final rng = Random(20240801);
      for (var i = 0; i < _iterations; i++) {
        final gguf = _FakeGgufEngine();
        final litert = _TrackingLiteRtService();
        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: _FakeDeviceService(),
        );

        final model = _randomGgufModel(rng);
        await router.loadModelInfo(model);

        // Reset counters after the load (which also queries isModelLoaded).
        gguf.chatCallCount = 0;
        gguf.isModelLoadedCallCount = 0;
        gguf.modelTierCallCount = 0;
        litert.chatCallCount = 0;
        litert.isModelLoadedCallCount = 0;
        litert.modelTierCallCount = 0;

        // Verify delegation.
        final loaded = router.isModelLoaded;
        expect(loaded, isTrue,
            reason: 'GGUF model ${model.id}: isModelLoaded should be true');
        expect(gguf.isModelLoadedCallCount, greaterThan(0),
            reason: 'isModelLoaded should delegate to GGUF engine');
        expect(litert.isModelLoadedCallCount, equals(0),
            reason: 'isModelLoaded should NOT delegate to LiteRT engine');

        // modelTier
        final _ = router.modelTier;
        expect(gguf.modelTierCallCount, greaterThan(0),
            reason: 'modelTier should delegate to GGUF engine');
        expect(litert.modelTierCallCount, equals(0),
            reason: 'modelTier should NOT delegate to LiteRT engine');

        // chat — yields the GGUF marker.
        final tokens = await router.chat('test-$i').toList();
        expect(tokens.first, startsWith('gguf:'),
            reason: 'chat should delegate to GGUF engine for model ${model.id}');
        expect(gguf.chatCallCount, greaterThan(0));
        expect(litert.chatCallCount, equals(0));
      }
    });

    // --- Sub-property C: After a successful LiteRT load, chat/isModelLoaded/
    // modelTier delegate to the LiteRT engine. Runs >= 100 cases. ---
    test('after LiteRT load, all calls delegate to LiteRT engine', () async {
      final rng = Random(20240802);
      for (var i = 0; i < _iterations; i++) {
        final gguf = _FakeGgufEngine();
        final litert = _TrackingLiteRtService();
        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: _FakeDeviceService(),
        );

        final model = _randomLitertModel(rng);
        await router.loadModelInfo(model);

        // Reset counters.
        gguf.chatCallCount = 0;
        gguf.isModelLoadedCallCount = 0;
        gguf.modelTierCallCount = 0;
        litert.chatCallCount = 0;
        litert.isModelLoadedCallCount = 0;
        litert.modelTierCallCount = 0;

        // isModelLoaded
        final loaded = router.isModelLoaded;
        expect(loaded, isTrue,
            reason: 'LiteRT model ${model.id}: isModelLoaded should be true');
        expect(litert.isModelLoadedCallCount, greaterThan(0),
            reason: 'isModelLoaded should delegate to LiteRT engine');
        expect(gguf.isModelLoadedCallCount, equals(0),
            reason: 'isModelLoaded should NOT delegate to GGUF engine');

        // modelTier
        final _ = router.modelTier;
        expect(litert.modelTierCallCount, greaterThan(0),
            reason: 'modelTier should delegate to LiteRT engine');
        expect(gguf.modelTierCallCount, equals(0),
            reason: 'modelTier should NOT delegate to GGUF engine');

        // chat — yields the LiteRT marker.
        final tokens = await router.chat('test-$i').toList();
        expect(tokens.first, startsWith('litert:'),
            reason:
                'chat should delegate to LiteRT engine for model ${model.id}');
        expect(litert.chatCallCount, greaterThan(0));
        expect(gguf.chatCallCount, equals(0));
      }
    });

    // --- Sub-property D: Switching engines routes correctly. After loading a
    // model of engine A then a model of engine B, all calls delegate to B.
    // Runs >= 100 generated cases with random engine sequences. ---
    test('switching engines delegates to the most recently loaded engine',
        () async {
      final rng = Random(20240803);
      for (var i = 0; i < _iterations; i++) {
        final gguf = _FakeGgufEngine();
        final litert = _TrackingLiteRtService();
        final router = EngineRouter(
          ggufEngine: gguf,
          litertEngine: litert,
          deviceService: _FakeDeviceService(),
        );

        // Load a random sequence of 2-4 models. The last one wins.
        final seqLen = 2 + rng.nextInt(3);
        ModelInfo lastModel = _randomModel(rng);
        await router.loadModelInfo(lastModel);
        for (var j = 1; j < seqLen; j++) {
          lastModel = _randomModel(rng);
          await router.loadModelInfo(lastModel);
        }

        // Reset counters.
        gguf.chatCallCount = 0;
        litert.chatCallCount = 0;

        // The final model's engine determines which engine receives the chat
        // call.
        final tokens = await router.chat('verify-$i').toList();
        if (lastModel.engine == AIEngine.gguf) {
          expect(tokens.first, startsWith('gguf:'),
              reason: 'After loading GGUF model ${lastModel.id} last, '
                  'chat should delegate to GGUF');
          expect(gguf.chatCallCount, greaterThan(0));
          expect(litert.chatCallCount, equals(0));
        } else {
          expect(tokens.first, startsWith('litert:'),
              reason: 'After loading LiteRT model ${lastModel.id} last, '
                  'chat should delegate to LiteRT');
          expect(litert.chatCallCount, greaterThan(0));
          expect(gguf.chatCallCount, equals(0));
        }

        // activeModel matches the last loaded model.
        expect(router.activeModel?.id, equals(lastModel.id));
      }
    });

    // --- Sub-property E: When no model is active (fresh state), repeated
    // calls do not accidentally set an active model. ---
    test('repeated calls with no active model never set an active model', () {
      final rng = Random(20240804);
      for (var i = 0; i < _iterations; i++) {
        final router = EngineRouter(
          ggufEngine: _FakeGgufEngine(),
          litertEngine: _TrackingLiteRtService(),
          deviceService: _FakeDeviceService(),
        );

        // isModelLoaded is stable at false.
        expect(router.isModelLoaded, isFalse);
        expect(router.isModelLoaded, isFalse);

        // chat always throws.
        expect(() => router.chat('attempt-$i'), throwsA(isA<AIServiceException>()));

        // activeModel remains null.
        expect(router.activeModel, isNull,
            reason: 'Calling LLMService members with no active model must '
                'never set an active model');
      }
    });
  });
}
