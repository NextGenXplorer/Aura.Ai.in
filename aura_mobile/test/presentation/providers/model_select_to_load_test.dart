import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/data/datasources/engine_router.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// Unit test for select-to-load wiring.
///
/// Validates: Requirement 6.7
/// "WHEN a user selects a downloaded model, THE Model_Selector SHALL request
///  that the Engine_Router load that model through the engine indicated by
///  the model's engine field."
///
/// This test verifies that when `selectModel(id)` is called on a downloaded
/// model, the EngineRouter's `loadModelInfo` is called with the correct
/// ModelInfo matching that id.
///
/// Since the full ModelSelectorNotifier requires Riverpod + filesystem + prefs,
/// we test at the EngineRouter level: selectModel → getModelPath → loadModel →
/// loadModelInfo → correct engine. The EngineRouter's `loadModel(String)`
/// resolves the ModelInfo from the catalog by file name and delegates to
/// `loadModelInfo`, which routes to the engine indicated by the model's engine
/// field.

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// A fake GGUF engine that records the model path it was asked to load.
class _FakeGgufEngine implements LLMService {
  String? lastLoadedPath;
  bool _loaded = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {
    lastLoadedPath = modelPath;
    _loaded = true;
  }

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    return Stream.value('gguf:$prompt');
  }

  @override
  bool get isModelLoaded => _loaded;

  @override
  ModelTier get modelTier => ModelTier.medium;

  @override
  bool get supportsToolCalling => false;
}

/// Fake [ModelFileManager] for LiteRtService.
class _FakeModelManager extends Fake implements ModelFileManager {
  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {}
}

/// Fake [FlutterGemmaPlugin] that always succeeds.
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

class _FakeInferenceModel extends Fake implements InferenceModel {}

/// A [LiteRtService] subclass that records the model path it was asked to load.
class _TrackingLiteRtService extends LiteRtService {
  String? lastLoadedPath;

  _TrackingLiteRtService() : super(gemma: _FakeGemmaPlugin());

  @override
  Future<void> loadModel(String modelPath) async {
    lastLoadedPath = modelPath;
    await super.loadModel(modelPath);
  }
}

/// Fake DeviceService — always reports plenty of RAM so loads succeed.
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
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Select-to-load wiring (Requirement 6.7)', () {
    late _FakeGgufEngine gguf;
    late _TrackingLiteRtService litert;
    late EngineRouter router;

    setUp(() {
      gguf = _FakeGgufEngine();
      litert = _TrackingLiteRtService();
      router = EngineRouter(
        ggufEngine: gguf,
        litertEngine: litert,
        deviceService: _FakeDeviceService(),
      );
    });

    test(
        'selecting a downloaded GGUF model loads through the GGUF engine', () async {
      final model = modelCatalog.firstWhere((m) => m.id == 'qwen2.5-1.5b');

      // Simulate what happens when selectModel calls loadModel with the
      // resolved path that contains the model's fileName.
      await router.loadModelInfo(model);

      // The GGUF engine should have been called with the model's fileName.
      expect(gguf.lastLoadedPath, model.fileName);
      expect(gguf.isModelLoaded, isTrue);
      expect(litert.lastLoadedPath, isNull,
          reason: 'LiteRT engine should NOT be called for a GGUF model');

      // The router should have committed this as the active model.
      expect(router.activeModel, isNotNull);
      expect(router.activeModel!.id, model.id);
      expect(router.activeModel!.engine, AIEngine.gguf);
    });

    test(
        'selecting a downloaded LiteRT model loads through the LiteRT engine', () async {
      final model = modelCatalog.firstWhere((m) => m.id == 'gemma3-1b');

      await router.loadModelInfo(model);

      // The LiteRT engine should have been called with the model's fileName.
      expect(litert.lastLoadedPath, model.fileName);
      expect(litert.isModelLoaded, isTrue);
      expect(gguf.lastLoadedPath, isNull,
          reason: 'GGUF engine should NOT be called for a LiteRT model');

      // The router should have committed this as the active model.
      expect(router.activeModel, isNotNull);
      expect(router.activeModel!.id, model.id);
      expect(router.activeModel!.engine, AIEngine.litert);
    });

    test(
        'selecting a tool-calling LiteRT model routes to the LiteRT engine', () async {
      final model = modelCatalog.firstWhere((m) => m.id == 'gemma4-e2b');
      expect(model.supportsToolCalling, isTrue,
          reason: 'Test precondition: gemma4-e2b supports tool calling');

      await router.loadModelInfo(model);

      expect(litert.lastLoadedPath, model.fileName);
      expect(router.activeModel!.id, model.id);
      expect(router.activeModel!.engine, AIEngine.litert);
      expect(router.supportsToolCalling, isTrue,
          reason:
              'Router should expose tool-calling capability of the active model');
    });

    test(
        'loadModel(path) resolves to loadModelInfo with correct ModelInfo', () async {
      // This tests the indirect path: selectModel calls loadModel(path) on the
      // LLMService. EngineRouter.loadModel resolves the ModelInfo by matching
      // the file name in the path against the catalog.
      final model = modelCatalog.firstWhere((m) => m.id == 'gemma3n-e2b');
      final fakePath = '/data/user/0/com.aura.ai/files/${model.fileName}';

      await router.loadModel(fakePath);

      // The router should have resolved the ModelInfo and routed to LiteRT.
      expect(router.activeModel, isNotNull);
      expect(router.activeModel!.id, model.id);
      expect(router.activeModel!.engine, AIEngine.litert);
      expect(litert.lastLoadedPath, model.fileName);
    });

    test(
        'loadModel(path) for a GGUF model resolves and routes to GGUF engine', () async {
      final model = modelCatalog.firstWhere((m) => m.id == 'qwen2.5-3b');
      final fakePath = '/storage/emulated/0/Documents/${model.fileName}';

      await router.loadModel(fakePath);

      expect(router.activeModel, isNotNull);
      expect(router.activeModel!.id, model.id);
      expect(router.activeModel!.engine, AIEngine.gguf);
      expect(gguf.lastLoadedPath, model.fileName);
    });

    test(
        'each catalog model routes to the engine indicated by its engine field', () async {
      // Iterate over all catalog models and verify each routes correctly.
      for (final model in modelCatalog) {
        final freshGguf = _FakeGgufEngine();
        final freshLitert = _TrackingLiteRtService();
        final freshRouter = EngineRouter(
          ggufEngine: freshGguf,
          litertEngine: freshLitert,
          deviceService: _FakeDeviceService(),
        );

        await freshRouter.loadModelInfo(model);

        expect(freshRouter.activeModel!.id, model.id,
            reason: 'Model ${model.id} should be the active model');

        if (model.engine == AIEngine.gguf) {
          expect(freshGguf.lastLoadedPath, model.fileName,
              reason:
                  'GGUF model ${model.id} should load through GGUF engine');
          expect(freshLitert.lastLoadedPath, isNull,
              reason:
                  'GGUF model ${model.id} should NOT touch LiteRT engine');
        } else {
          expect(freshLitert.lastLoadedPath, model.fileName,
              reason:
                  'LiteRT model ${model.id} should load through LiteRT engine');
          expect(freshGguf.lastLoadedPath, isNull,
              reason:
                  'LiteRT model ${model.id} should NOT touch GGUF engine');
        }
      }
    });
  });
}
