import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/data/datasources/engine_router.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// Unit tests for the EngineRouter.chat signature boundaries.
//
// Verifies that `chat` accepts `maxTokens >= 1` and `temperature` in [0.0, 2.0]
// and that these parameters are correctly passed through to the delegate engine.
//
// _Requirements: 1.8_

// ---------------------------------------------------------------------------
// Capturing GGUF engine — records the parameters passed to chat
// ---------------------------------------------------------------------------

class _CapturingGgufEngine implements LLMService {
  bool _loaded = false;

  // Captured parameters from the last chat call.
  String? lastPrompt;
  String? lastSystemPrompt;
  int? lastMaxTokens;
  double? lastTemperature;
  int chatCallCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {
    _loaded = true;
  }

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    chatCallCount++;
    lastPrompt = prompt;
    lastSystemPrompt = systemPrompt;
    lastMaxTokens = maxTokens;
    lastTemperature = temperature;
    return Stream.value('response');
  }

  @override
  bool get isModelLoaded => _loaded;

  @override
  ModelTier get modelTier => ModelTier.medium;

  @override
  bool get supportsToolCalling => false;
}

// ---------------------------------------------------------------------------
// Capturing LiteRT engine — records the parameters passed to chat
// ---------------------------------------------------------------------------

class _FakeModelManager extends Fake implements ModelFileManager {
  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {}
}

class _FakeInferenceModel extends Fake implements InferenceModel {}

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

class _CapturingLiteRtService extends LiteRtService {
  String? lastPrompt;
  String? lastSystemPrompt;
  int? lastMaxTokens;
  double? lastTemperature;
  int chatCallCount = 0;

  _CapturingLiteRtService() : super(gemma: _FakeGemmaPlugin());

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    chatCallCount++;
    lastPrompt = prompt;
    lastSystemPrompt = systemPrompt;
    lastMaxTokens = maxTokens;
    lastTemperature = temperature;
    return Stream.value('litert-response');
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
// Helper: get a GGUF model from the catalog
// ---------------------------------------------------------------------------

ModelInfo _aGgufModel() =>
    modelCatalog.firstWhere((m) => m.engine == AIEngine.gguf);

ModelInfo _aLitertModel() =>
    modelCatalog.firstWhere((m) => m.engine == AIEngine.litert);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EngineRouter.chat signature boundaries (Requirement 1.8)', () {
    late _CapturingGgufEngine gguf;
    late _CapturingLiteRtService litert;
    late EngineRouter router;

    setUp(() {
      gguf = _CapturingGgufEngine();
      litert = _CapturingLiteRtService();
      router = EngineRouter(
        ggufEngine: gguf,
        litertEngine: litert,
        deviceService: _FakeDeviceService(),
      );
    });

    group('maxTokens boundary (minimum = 1)', () {
      test('maxTokens = 1 is accepted and passed through (GGUF)', () async {
        await router.loadModelInfo(_aGgufModel());

        final tokens = await router
            .chat('hello', maxTokens: 1, temperature: 0.7)
            .toList();

        expect(tokens, isNotEmpty);
        expect(gguf.lastMaxTokens, equals(1));
      });

      test('maxTokens = 1 is accepted and passed through (LiteRT)', () async {
        await router.loadModelInfo(_aLitertModel());

        final tokens = await router
            .chat('hello', maxTokens: 1, temperature: 0.7)
            .toList();

        expect(tokens, isNotEmpty);
        expect(litert.lastMaxTokens, equals(1));
      });

      test('maxTokens = 512 (default) is passed through', () async {
        await router.loadModelInfo(_aGgufModel());

        await router.chat('hello').toList();

        expect(gguf.lastMaxTokens, equals(512));
      });

      test('maxTokens = 100 is accepted and passed through', () async {
        await router.loadModelInfo(_aGgufModel());

        await router.chat('hello', maxTokens: 100).toList();

        expect(gguf.lastMaxTokens, equals(100));
      });

      test('maxTokens = 4096 (large value) is accepted and passed through',
          () async {
        await router.loadModelInfo(_aGgufModel());

        await router.chat('hello', maxTokens: 4096).toList();

        expect(gguf.lastMaxTokens, equals(4096));
      });
    });

    group('temperature boundaries [0.0, 2.0]', () {
      test('temperature = 0.0 (lower bound) is accepted and passed through',
          () async {
        await router.loadModelInfo(_aGgufModel());

        await router
            .chat('hello', temperature: 0.0, maxTokens: 512)
            .toList();

        expect(gguf.lastTemperature, equals(0.0));
      });

      test(
          'temperature = 0.0 (lower bound) is accepted and passed through (LiteRT)',
          () async {
        await router.loadModelInfo(_aLitertModel());

        await router
            .chat('hello', temperature: 0.0, maxTokens: 512)
            .toList();

        expect(litert.lastTemperature, equals(0.0));
      });

      test('temperature = 2.0 (upper bound) is accepted and passed through',
          () async {
        await router.loadModelInfo(_aGgufModel());

        await router
            .chat('hello', temperature: 2.0, maxTokens: 512)
            .toList();

        expect(gguf.lastTemperature, equals(2.0));
      });

      test(
          'temperature = 2.0 (upper bound) is accepted and passed through (LiteRT)',
          () async {
        await router.loadModelInfo(_aLitertModel());

        await router
            .chat('hello', temperature: 2.0, maxTokens: 512)
            .toList();

        expect(litert.lastTemperature, equals(2.0));
      });

      test('temperature = 0.7 (default) is passed through', () async {
        await router.loadModelInfo(_aGgufModel());

        await router.chat('hello').toList();

        expect(gguf.lastTemperature, equals(0.7));
      });

      test('temperature = 1.0 (mid-range) is accepted and passed through',
          () async {
        await router.loadModelInfo(_aGgufModel());

        await router.chat('hello', temperature: 1.0).toList();

        expect(gguf.lastTemperature, equals(1.0));
      });
    });

    group('valid parameter combinations', () {
      test('maxTokens=1, temperature=0.0 — both lower bounds', () async {
        await router.loadModelInfo(_aGgufModel());

        await router
            .chat('edge case', maxTokens: 1, temperature: 0.0)
            .toList();

        expect(gguf.lastMaxTokens, equals(1));
        expect(gguf.lastTemperature, equals(0.0));
        expect(gguf.lastPrompt, equals('edge case'));
      });

      test('maxTokens=4096, temperature=2.0 — both upper bounds', () async {
        await router.loadModelInfo(_aGgufModel());

        await router
            .chat('creative mode', maxTokens: 4096, temperature: 2.0)
            .toList();

        expect(gguf.lastMaxTokens, equals(4096));
        expect(gguf.lastTemperature, equals(2.0));
        expect(gguf.lastPrompt, equals('creative mode'));
      });

      test('with systemPrompt, maxTokens=256, temperature=1.5', () async {
        await router.loadModelInfo(_aGgufModel());

        await router
            .chat(
              'user prompt',
              systemPrompt: 'You are helpful',
              maxTokens: 256,
              temperature: 1.5,
            )
            .toList();

        expect(gguf.lastPrompt, equals('user prompt'));
        expect(gguf.lastSystemPrompt, equals('You are helpful'));
        expect(gguf.lastMaxTokens, equals(256));
        expect(gguf.lastTemperature, equals(1.5));
      });

      test('LiteRT: with systemPrompt, maxTokens=2048, temperature=0.3',
          () async {
        await router.loadModelInfo(_aLitertModel());

        await router
            .chat(
              'summarize this',
              systemPrompt: 'Be concise',
              maxTokens: 2048,
              temperature: 0.3,
            )
            .toList();

        expect(litert.lastPrompt, equals('summarize this'));
        expect(litert.lastSystemPrompt, equals('Be concise'));
        expect(litert.lastMaxTokens, equals(2048));
        expect(litert.lastTemperature, equals(0.3));
      });

      test('multiple sequential chats pass different params correctly',
          () async {
        await router.loadModelInfo(_aGgufModel());

        // First call with specific params.
        await router.chat('first', maxTokens: 10, temperature: 0.1).toList();
        expect(gguf.lastMaxTokens, equals(10));
        expect(gguf.lastTemperature, equals(0.1));

        // Second call with different params.
        await router.chat('second', maxTokens: 999, temperature: 1.9).toList();
        expect(gguf.lastMaxTokens, equals(999));
        expect(gguf.lastTemperature, equals(1.9));
        expect(gguf.lastPrompt, equals('second'));
        expect(gguf.chatCallCount, equals(2));
      });
    });
  });
}
