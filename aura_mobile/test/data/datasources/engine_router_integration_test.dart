import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/data/datasources/engine_router.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// ---------------------------------------------------------------------------
// Integration test: End-to-end engine switching
//
// Validates Requirements 1.3, 1.4, 1.5:
// - Loading a GGUF model routes chat/modelTier to the GGUF engine.
// - Switching to a LiteRT model routes chat/modelTier to the LiteRT engine.
// - A failed load preserves the prior active model.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Fake GGUF engine
// ---------------------------------------------------------------------------

class _FakeGgufEngine implements LLMService {
  bool _loaded = false;
  ModelTier _tier = ModelTier.large;
  String? lastChatPrompt;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {
    _loaded = true;
    _tier = LLMServiceImpl.modelTierForPath(modelPath);
  }

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    lastChatPrompt = prompt;
    return Stream.value('gguf-response:$prompt');
  }

  @override
  bool get isModelLoaded => _loaded;

  @override
  ModelTier get modelTier => _tier;

  @override
  bool get supportsToolCalling => false;
}

// ---------------------------------------------------------------------------
// Fake LiteRT engine (extends LiteRtService with overridden behavior)
// ---------------------------------------------------------------------------

class _FakeModelManager extends Fake implements ModelFileManager {
  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {}
}

class _FakeInferenceModel extends Fake implements InferenceModel {}

class _FakeGemmaPlugin extends Fake implements FlutterGemmaPlugin {
  final _FakeModelManager _manager = _FakeModelManager();
  bool shouldFailLoad = false;

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
    if (shouldFailLoad) {
      throw Exception('Simulated LiteRT load failure');
    }
    return _FakeInferenceModel();
  }
}

/// A LiteRtService subclass that overrides chat to return a distinguishing
/// marker without needing a real inference session.
class _FakeLiteRtService extends LiteRtService {
  final _FakeGemmaPlugin _fakePlugin;
  String? lastChatPrompt;

  _FakeLiteRtService(_FakeGemmaPlugin plugin)
      : _fakePlugin = plugin,
        super(gemma: plugin);

  /// Make load failures controllable from the test.
  void setLoadShouldFail(bool fail) {
    _fakePlugin.shouldFailLoad = fail;
  }

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    lastChatPrompt = prompt;
    return Stream.value('litert-response:$prompt');
  }
}

// ---------------------------------------------------------------------------
// Fake DeviceService — reports sufficient RAM for all models
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
// Test helpers
// ---------------------------------------------------------------------------

/// A known GGUF model from the catalog for testing.
ModelInfo get _ggufModel =>
    modelCatalog.firstWhere((m) => m.id == 'qwen2.5-1.5b');

/// A known LiteRT model from the catalog for testing.
ModelInfo get _litertModel =>
    modelCatalog.firstWhere((m) => m.id == 'gemma3-1b');

/// A second LiteRT model to test failed switch scenarios.
ModelInfo get _litertModel2 =>
    modelCatalog.firstWhere((m) => m.id == 'gemma3n-e2b');

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Integration: End-to-end engine switching', () {
    late _FakeGgufEngine ggufEngine;
    late _FakeLiteRtService litertEngine;
    late _FakeDeviceService deviceService;
    late EngineRouter router;

    setUp(() async {
      ggufEngine = _FakeGgufEngine();
      final plugin = _FakeGemmaPlugin();
      litertEngine = _FakeLiteRtService(plugin);
      deviceService = _FakeDeviceService();
      router = EngineRouter(
        ggufEngine: ggufEngine,
        litertEngine: litertEngine,
        deviceService: deviceService,
      );
      await router.initialize();
    });

    test('load GGUF model → chat and modelTier route to GGUF engine', () async {
      // Load a GGUF model (Req 1.4: set active only after engine reports loaded).
      await router.loadModelInfo(_ggufModel);

      // Verify active model is the GGUF model.
      expect(router.activeModel, equals(_ggufModel));
      expect(router.isModelLoaded, isTrue);

      // Req 1.3, 1.6: chat delegates to GGUF engine.
      final chatResult = await router.chat('Hello GGUF').toList();
      expect(chatResult, equals(['gguf-response:Hello GGUF']));
      expect(ggufEngine.lastChatPrompt, equals('Hello GGUF'));

      // modelTier delegates to GGUF engine (file-name-based detection).
      final tier = router.modelTier;
      expect(tier, equals(ModelTier.medium),
          reason: 'qwen2.5-1.5b should map to medium tier');
    });

    test('switch from GGUF to LiteRT → chat and modelTier route to LiteRT engine',
        () async {
      // Start with a GGUF model loaded.
      await router.loadModelInfo(_ggufModel);
      expect(router.activeModel?.engine, equals(AIEngine.gguf));

      // Now switch to a LiteRT model (Req 1.4).
      await router.loadModelInfo(_litertModel);

      // Verify active model switched to LiteRT.
      expect(router.activeModel, equals(_litertModel));
      expect(router.activeModel?.engine, equals(AIEngine.litert));
      expect(router.isModelLoaded, isTrue);

      // Req 1.3, 1.7: chat now delegates to LiteRT engine.
      final chatResult = await router.chat('Hello LiteRT').toList();
      expect(chatResult, equals(['litert-response:Hello LiteRT']));
      expect(litertEngine.lastChatPrompt, equals('Hello LiteRT'));

      // modelTier should reflect the LiteRT model's tier (from catalog metadata).
      final tier = router.modelTier;
      // gemma3-1b should be small tier based on _modelTierForLiteRT.
      expect(tier, equals(ModelTier.small));
    });

    test('failed LiteRT load preserves prior GGUF active model (Req 1.5)',
        () async {
      // Start with a GGUF model loaded.
      await router.loadModelInfo(_ggufModel);
      expect(router.activeModel?.id, equals('qwen2.5-1.5b'));

      // Now attempt to load a LiteRT model that will fail.
      litertEngine.setLoadShouldFail(true);

      // The load should throw.
      expect(
        () => router.loadModelInfo(_litertModel2),
        throwsA(isA<AuraException>()),
      );

      // Req 1.5: The previously active GGUF model should be preserved.
      expect(router.activeModel?.id, equals('qwen2.5-1.5b'));
      expect(router.activeModel?.engine, equals(AIEngine.gguf));
      expect(router.isModelLoaded, isTrue);

      // The GGUF model should still be functional.
      final chatResult = await router.chat('Still GGUF').toList();
      expect(chatResult, equals(['gguf-response:Still GGUF']));
    });

    test('full round-trip: GGUF → LiteRT → failed switch back preserves LiteRT',
        () async {
      // Phase 1: Load GGUF.
      await router.loadModelInfo(_ggufModel);
      expect(router.activeModel?.engine, equals(AIEngine.gguf));
      final ggufChat = await router.chat('phase1').toList();
      expect(ggufChat.first, startsWith('gguf-response:'));

      // Phase 2: Switch to LiteRT.
      await router.loadModelInfo(_litertModel);
      expect(router.activeModel?.engine, equals(AIEngine.litert));
      final litertChat = await router.chat('phase2').toList();
      expect(litertChat.first, startsWith('litert-response:'));

      // Phase 3: Attempt to load a second LiteRT model, but it fails.
      litertEngine.setLoadShouldFail(true);
      expect(
        () => router.loadModelInfo(_litertModel2),
        throwsA(isA<AuraException>()),
      );

      // The first LiteRT model should still be active (Req 1.5).
      expect(router.activeModel?.id, equals('gemma3-1b'));
      expect(router.activeModel?.engine, equals(AIEngine.litert));
      expect(router.isModelLoaded, isTrue);

      // Chat still routes to LiteRT engine.
      final stillLitert = await router.chat('phase3').toList();
      expect(stillLitert.first, startsWith('litert-response:'));
    });

    test('supportsToolCalling reflects active model capabilities after switch',
        () async {
      // Load a non-tool-calling GGUF model.
      await router.loadModelInfo(_ggufModel);
      expect(router.supportsToolCalling, isFalse);

      // Switch to a tool-calling LiteRT model (Gemma 4 E2B).
      final toolCallingModel =
          modelCatalog.firstWhere((m) => m.id == 'gemma4-e2b');
      await router.loadModelInfo(toolCallingModel);
      expect(router.supportsToolCalling, isTrue);

      // Switch back to GGUF.
      await router.loadModelInfo(_ggufModel);
      expect(router.supportsToolCalling, isFalse);
    });
  });
}
