import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/data/datasources/engine_router.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';

// Feature: multi-engine-ai-models, Property 25: RAM gate decides loading
//
// "For any model and any reported Device_RAM, the loading decision is made
//  before any engine load begins, and: when Device_RAM cannot be determined
//  the load is prevented with a device-compatibility error; when the model's
//  minimum RAM in MB exceeds Device_RAM in MB the load is prevented with a
//  memory-insufficiency message identifying both the required and the available
//  megabytes; otherwise the load proceeds."
//
// Validates: Requirements 8.1, 8.2, 8.3, 8.6
//
// Uses a generator-based approach with Random + iterations >= 100.

const int _iterations = 200;

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// A fake [DeviceService] that returns configurable RAM values without needing
/// platform channels or device_info_plus.
class _FakeDeviceService extends DeviceService {
  final int totalRamMB;

  _FakeDeviceService({required this.totalRamMB});

  @override
  Future<DeviceInfo> analyzeDevice() async {
    return DeviceInfo(
      totalRamMB: totalRamMB,
      availableRamMB: totalRamMB > 0 ? (totalRamMB * 0.7).round() : 0,
      totalStorageMB: 64000,
      availableStorageMB: 32000,
      androidVersion: '14',
      isArm64: true,
    );
  }
}

/// A fake GGUF engine that always succeeds loads and reports isModelLoaded.
class _FakeGgufEngine implements LLMService {
  bool _loaded = false;
  int loadCallCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {
    loadCallCount++;
    _loaded = true;
  }

  @override
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) {
    return Stream.value('response');
  }

  @override
  bool get isModelLoaded => _loaded;

  @override
  ModelTier get modelTier => ModelTier.medium;

  @override
  bool get supportsToolCalling => false;
}

/// Minimal fake [FlutterGemmaPlugin] to satisfy LiteRtService constructor.
class _FakeGemmaPlugin extends Fake implements FlutterGemmaPlugin {
  @override
  ModelFileManager get modelManager => _FakeModelManager();

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

class _FakeModelManager extends Fake implements ModelFileManager {
  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {}
}

class _FakeInferenceModel extends Fake implements InferenceModel {}

/// A fake LiteRT engine that always succeeds loads and reports isModelLoaded.
/// Extends the real [LiteRtService] with a fake gemma plugin, overriding
/// behavior for testing the RAM gate in the router.
class _FakeLiteRtService extends LiteRtService {
  bool _fakeLoaded = false;
  int loadCallCount = 0;

  _FakeLiteRtService() : super(gemma: _FakeGemmaPlugin());

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {
    loadCallCount++;
    _fakeLoaded = true;
  }

  @override
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) {
    return Stream.value('response');
  }

  @override
  bool get isModelLoaded => _fakeLoaded;

  @override
  ModelTier get modelTier => ModelTier.medium;

  @override
  set modelTier(ModelTier tier) {}
}

/// Creates a [ModelInfo] with specified engine and minRamMB.
ModelInfo _makeModel({
  required int minRamMB,
  AIEngine engine = AIEngine.gguf,
  String? id,
}) {
  final effectiveId = id ?? 'test-model-$minRamMB';
  final fileName = engine == AIEngine.gguf
      ? '$effectiveId.gguf'
      : '$effectiveId.task';
  return ModelInfo(
    id: effectiveId,
    name: 'Test Model $minRamMB',
    description: 'Test model requiring $minRamMB MB RAM',
    url: 'https://example.com/$fileName',
    sizeBytes: 500000000,
    ramRequirement: '${minRamMB}MB',
    speed: 'Fast',
    fileName: fileName,
    minRamMB: minRamMB,
    engine: engine,
  );
}

void main() {
  group('Property 25: RAM gate decides loading (multi-engine-ai-models)', () {
    test(
        'RAM gate: deviceRamMB <= 0 always throws AI_DEVICE_COMPATIBILITY, '
        'minRamMB > deviceRamMB always throws AI_MEMORY_INSUFFICIENCY, '
        'minRamMB <= deviceRamMB always allows the load to proceed', () async {
      final rng = Random(20240725);

      for (var i = 0; i < _iterations; i++) {
        // Generate random device RAM and model requirements.
        // Device RAM: -10 to 16384 (includes zero and negative to test undeterminable)
        final deviceRamMB = rng.nextInt(16395) - 10; // range: [-10, 16384]
        // Model minRamMB: 1 to 16384 (always positive per catalog invariants)
        final minRamMB = rng.nextInt(16384) + 1; // range: [1, 16384]

        // Alternate between gguf and litert engines.
        final engine = i % 2 == 0 ? AIEngine.gguf : AIEngine.litert;

        final fakeDevice = _FakeDeviceService(totalRamMB: deviceRamMB);
        final fakeGguf = _FakeGgufEngine();
        final fakeLiteRt = _FakeLiteRtService();

        final router = EngineRouter(
          ggufEngine: fakeGguf,
          litertEngine: fakeLiteRt,
          deviceService: fakeDevice,
        );

        final model = _makeModel(minRamMB: minRamMB, engine: engine, id: 'model-$i');

        final loadCountBefore =
            engine == AIEngine.gguf ? fakeGguf.loadCallCount : fakeLiteRt.loadCallCount;

        String ctx() => 'Property 25 counterexample\n'
            '  iteration    = $i\n'
            '  deviceRamMB  = $deviceRamMB\n'
            '  minRamMB     = $minRamMB\n'
            '  engine       = ${engine.name}';

        if (deviceRamMB <= 0) {
          // Case 1: Undeterminable RAM → device-compatibility error
          try {
            await router.loadModelInfo(model);
            fail('Expected AI_DEVICE_COMPATIBILITY error but load succeeded.\n${ctx()}');
          } catch (e) {
            expect(e, isA<AIServiceException>(), reason: ctx());
            final ex = e as AIServiceException;
            expect(ex.errorCode, 'AI_DEVICE_COMPATIBILITY', reason: ctx());
          }

          // Verify the engine was NOT called (decision made before engine load).
          final loadCountAfter =
              engine == AIEngine.gguf ? fakeGguf.loadCallCount : fakeLiteRt.loadCallCount;
          expect(loadCountAfter, equals(loadCountBefore),
              reason: 'Engine should not be called when RAM is undeterminable.\n${ctx()}');
        } else if (minRamMB > deviceRamMB) {
          // Case 2: Insufficient RAM → memory-insufficiency error
          try {
            await router.loadModelInfo(model);
            fail('Expected AI_MEMORY_INSUFFICIENCY error but load succeeded.\n${ctx()}');
          } catch (e) {
            expect(e, isA<AIServiceException>(), reason: ctx());
            final ex = e as AIServiceException;
            expect(ex.errorCode, 'AI_MEMORY_INSUFFICIENCY', reason: ctx());
            // The error message must identify both required and available MB.
            expect(ex.technicalDetails, contains('$minRamMB'),
                reason: 'Error should identify required RAM.\n${ctx()}');
            expect(ex.technicalDetails, contains('$deviceRamMB'),
                reason: 'Error should identify available RAM.\n${ctx()}');
          }

          // Verify the engine was NOT called (decision made before engine load).
          final loadCountAfter =
              engine == AIEngine.gguf ? fakeGguf.loadCallCount : fakeLiteRt.loadCallCount;
          expect(loadCountAfter, equals(loadCountBefore),
              reason: 'Engine should not be called when RAM is insufficient.\n${ctx()}');
        } else {
          // Case 3: RAM sufficient → load proceeds (no RAM gate error).
          await router.loadModelInfo(model);

          // Verify the engine WAS called.
          final loadCountAfter =
              engine == AIEngine.gguf ? fakeGguf.loadCallCount : fakeLiteRt.loadCallCount;
          expect(loadCountAfter, equals(loadCountBefore + 1),
              reason: 'Engine should be called when RAM is sufficient.\n${ctx()}');

          // Verify the model became active.
          expect(router.activeModel, equals(model), reason: ctx());
        }
      }
    });

    // Concrete deterministic examples for documentation.
    test('example: deviceRamMB == 0 → AI_DEVICE_COMPATIBILITY', () async {
      final router = EngineRouter(
        ggufEngine: _FakeGgufEngine(),
        litertEngine: _FakeLiteRtService(),
        deviceService: _FakeDeviceService(totalRamMB: 0),
      );

      final model = _makeModel(minRamMB: 2048);

      expect(
        () => router.loadModelInfo(model),
        throwsA(
          isA<AIServiceException>()
              .having((e) => e.errorCode, 'errorCode', 'AI_DEVICE_COMPATIBILITY'),
        ),
      );
    });

    test('example: deviceRamMB == -5 → AI_DEVICE_COMPATIBILITY', () async {
      final router = EngineRouter(
        ggufEngine: _FakeGgufEngine(),
        litertEngine: _FakeLiteRtService(),
        deviceService: _FakeDeviceService(totalRamMB: -5),
      );

      final model = _makeModel(minRamMB: 1024);

      expect(
        () => router.loadModelInfo(model),
        throwsA(
          isA<AIServiceException>()
              .having((e) => e.errorCode, 'errorCode', 'AI_DEVICE_COMPATIBILITY'),
        ),
      );
    });

    test('example: minRamMB (4096) > deviceRamMB (2048) → AI_MEMORY_INSUFFICIENCY',
        () async {
      final router = EngineRouter(
        ggufEngine: _FakeGgufEngine(),
        litertEngine: _FakeLiteRtService(),
        deviceService: _FakeDeviceService(totalRamMB: 2048),
      );

      final model = _makeModel(minRamMB: 4096);

      expect(
        () => router.loadModelInfo(model),
        throwsA(
          isA<AIServiceException>()
              .having((e) => e.errorCode, 'errorCode', 'AI_MEMORY_INSUFFICIENCY')
              .having((e) => e.technicalDetails, 'details', contains('4096'))
              .having((e) => e.technicalDetails, 'details', contains('2048')),
        ),
      );
    });

    test('example: minRamMB (2048) <= deviceRamMB (4096) → load proceeds',
        () async {
      final fakeGguf = _FakeGgufEngine();
      final router = EngineRouter(
        ggufEngine: fakeGguf,
        litertEngine: _FakeLiteRtService(),
        deviceService: _FakeDeviceService(totalRamMB: 4096),
      );

      final model = _makeModel(minRamMB: 2048);

      await router.loadModelInfo(model);
      expect(fakeGguf.loadCallCount, 1);
      expect(router.activeModel, model);
    });

    test('example: minRamMB == deviceRamMB (exact boundary) → load proceeds',
        () async {
      final fakeGguf = _FakeGgufEngine();
      final router = EngineRouter(
        ggufEngine: fakeGguf,
        litertEngine: _FakeLiteRtService(),
        deviceService: _FakeDeviceService(totalRamMB: 3000),
      );

      final model = _makeModel(minRamMB: 3000);

      await router.loadModelInfo(model);
      expect(fakeGguf.loadCallCount, 1);
      expect(router.activeModel, model);
    });
  });
}
