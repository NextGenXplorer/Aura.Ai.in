import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/data/datasources/engine_router.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';

// Feature: multi-engine-ai-models, Property 26: LiteRT model tier from metadata
//
// "For any litert model that becomes active, modelTier returns exactly one of
//  small, medium, or large, equal to the tier mapped from that model's catalog
//  metadata."
//
// The mapping (from EngineRouter._modelTierForLiteRT):
//   - id contains '1b' (but not 'e2b' or 'e4b') → ModelTier.small
//   - id contains 'e4b' → ModelTier.large
//   - otherwise → ModelTier.medium
//
// Validates: Requirements 8.4
//
// Uses a generator-based approach with Random + iterations >= 100.

const int _iterations = 150;

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// A fake [DeviceService] that always reports ample RAM so loading is never
/// blocked by the RAM gate.
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

/// A fake GGUF engine (unused here but required by EngineRouter constructor).
class _FakeGgufEngine implements LLMService {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {}

  @override
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) {
    return Stream.value('response');
  }

  @override
  bool get isModelLoaded => false;

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

/// A fake LiteRT engine that always succeeds loads and tracks the tier
/// assigned by the router. The real [LiteRtService]'s `modelTier` setter is
/// used by the router to push the derived tier before loading.
class _FakeLiteRtService extends LiteRtService {
  bool _fakeLoaded = false;

  _FakeLiteRtService() : super(gemma: _FakeGemmaPlugin());

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) async {
    _fakeLoaded = true;
  }

  @override
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) {
    return Stream.value('response');
  }

  @override
  bool get isModelLoaded => _fakeLoaded;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Computes the expected tier for a given model id, mirroring the logic in
/// EngineRouter._modelTierForLiteRT.
ModelTier _expectedTierForId(String id) {
  final lower = id.toLowerCase();
  if (lower.contains('1b') && !lower.contains('e2b') && !lower.contains('e4b')) {
    return ModelTier.small;
  }
  if (lower.contains('e4b')) {
    return ModelTier.large;
  }
  return ModelTier.medium;
}

/// Creates a LiteRT [ModelInfo] with the given [id].
ModelInfo _makeLiteRtModel(String id) {
  return ModelInfo(
    id: id,
    name: 'Test LiteRT $id',
    description: 'Generated LiteRT model for property testing',
    url: 'https://example.com/$id.task',
    sizeBytes: 500000000,
    ramRequirement: '2GB',
    speed: 'Fast',
    fileName: '$id.task',
    minRamMB: 1024,
    engine: AIEngine.litert,
  );
}

/// Character pool for generating random model ID segments.
const _idChars = 'abcdefghijklmnopqrstuvwxyz0123456789-';

/// Generates a random model id segment of [length] characters from [_idChars].
String _randomSegment(Random rng, int length) {
  return String.fromCharCodes(
    Iterable.generate(length, (_) => _idChars.codeUnitAt(rng.nextInt(_idChars.length))),
  );
}

void main() {
  group('Property 26: LiteRT model tier from metadata (multi-engine-ai-models)', () {
    test(
        'For any litert model that becomes active, modelTier returns the '
        'tier mapped from catalog metadata via the id-based rule', () async {
      final rng = Random(20240826);

      for (var i = 0; i < _iterations; i++) {
        final fakeLiteRt = _FakeLiteRtService();
        final router = EngineRouter(
          ggufEngine: _FakeGgufEngine(),
          litertEngine: fakeLiteRt,
          deviceService: _FakeDeviceService(),
        );

        // Generate model IDs that exercise the three branches:
        //   - small: contains '1b' without 'e2b'/'e4b'
        //   - large: contains 'e4b'
        //   - medium: everything else (including 'e2b')
        String modelId;
        final branch = i % 5;
        switch (branch) {
          case 0:
            // Force small: embed '1b' without 'e2b' or 'e4b'
            final prefix = _randomSegment(rng, rng.nextInt(4) + 1);
            modelId = '${prefix}1b${_randomSegment(rng, rng.nextInt(4))}';
            // Ensure no accidental 'e2b' or 'e4b' — replace if collision
            if (modelId.contains('e2b') || modelId.contains('e4b')) {
              modelId = modelId.replaceAll('e2b', 'x2x').replaceAll('e4b', 'x4x');
            }
            break;
          case 1:
            // Force large: embed 'e4b'
            final prefix = _randomSegment(rng, rng.nextInt(5) + 1);
            modelId = '${prefix}e4b${_randomSegment(rng, rng.nextInt(4))}';
            break;
          case 2:
            // Force medium via 'e2b' prefix (contains 'e2b', which blocks '1b' rule)
            final prefix = _randomSegment(rng, rng.nextInt(4) + 1);
            modelId = '${prefix}e2b${_randomSegment(rng, rng.nextInt(4))}';
            break;
          case 3:
            // Force medium: random id without '1b' or 'e4b'
            modelId = _randomSegment(rng, rng.nextInt(8) + 3);
            modelId = modelId.replaceAll('1b', 'xx').replaceAll('e4b', 'xxx');
            break;
          default:
            // Fully random: may hit any branch
            modelId = _randomSegment(rng, rng.nextInt(10) + 3);
            break;
        }

        final model = _makeLiteRtModel(modelId);
        final expectedTier = _expectedTierForId(modelId);

        await router.loadModelInfo(model);

        String ctx() => 'Property 26 counterexample\n'
            '  iteration  = $i\n'
            '  modelId    = "$modelId"\n'
            '  expected   = ${expectedTier.name}\n'
            '  actual     = ${router.modelTier.name}';

        // The tier must be exactly one of the three enum values.
        expect(
          [ModelTier.small, ModelTier.medium, ModelTier.large],
          contains(router.modelTier),
          reason: 'modelTier must be one of small, medium, large.\n${ctx()}',
        );

        // The tier must match the expected mapping.
        expect(router.modelTier, equals(expectedTier), reason: ctx());
      }
    });

    test('All LiteRT catalog entries produce the correct tier', () async {
      final literCatalogEntries =
          modelCatalog.where((m) => m.engine == AIEngine.litert).toList();

      // Ensure there are actually LiteRT entries in the catalog.
      expect(literCatalogEntries, isNotEmpty,
          reason: 'Expected at least one LiteRT entry in modelCatalog');

      for (final model in literCatalogEntries) {
        final fakeLiteRt = _FakeLiteRtService();
        final router = EngineRouter(
          ggufEngine: _FakeGgufEngine(),
          litertEngine: fakeLiteRt,
          deviceService: _FakeDeviceService(),
        );

        await router.loadModelInfo(model);

        final expectedTier = _expectedTierForId(model.id);

        expect(router.modelTier, equals(expectedTier),
            reason: 'Catalog model "${model.id}" (${model.name}) should map '
                'to tier ${expectedTier.name} but got ${router.modelTier.name}');
      }
    });

    // Deterministic examples for documentation.
    test('example: gemma3-1b → small', () async {
      final fakeLiteRt = _FakeLiteRtService();
      final router = EngineRouter(
        ggufEngine: _FakeGgufEngine(),
        litertEngine: fakeLiteRt,
        deviceService: _FakeDeviceService(),
      );

      final model = _makeLiteRtModel('gemma3-1b');
      await router.loadModelInfo(model);
      expect(router.modelTier, ModelTier.small);
    });

    test('example: gemma3n-e2b → medium (e2b blocks 1b rule)', () async {
      final fakeLiteRt = _FakeLiteRtService();
      final router = EngineRouter(
        ggufEngine: _FakeGgufEngine(),
        litertEngine: fakeLiteRt,
        deviceService: _FakeDeviceService(),
      );

      final model = _makeLiteRtModel('gemma3n-e2b');
      await router.loadModelInfo(model);
      expect(router.modelTier, ModelTier.medium);
    });

    test('example: gemma4-e4b → large', () async {
      final fakeLiteRt = _FakeLiteRtService();
      final router = EngineRouter(
        ggufEngine: _FakeGgufEngine(),
        litertEngine: fakeLiteRt,
        deviceService: _FakeDeviceService(),
      );

      final model = _makeLiteRtModel('gemma4-e4b');
      await router.loadModelInfo(model);
      expect(router.modelTier, ModelTier.large);
    });

    test('example: gemma4-e2b → medium', () async {
      final fakeLiteRt = _FakeLiteRtService();
      final router = EngineRouter(
        ggufEngine: _FakeGgufEngine(),
        litertEngine: fakeLiteRt,
        deviceService: _FakeDeviceService(),
      );

      final model = _makeLiteRtModel('gemma4-e2b');
      await router.loadModelInfo(model);
      expect(router.modelTier, ModelTier.medium);
    });

    test('example: model-xyz (no size marker) → medium', () async {
      final fakeLiteRt = _FakeLiteRtService();
      final router = EngineRouter(
        ggufEngine: _FakeGgufEngine(),
        litertEngine: fakeLiteRt,
        deviceService: _FakeDeviceService(),
      );

      final model = _makeLiteRtModel('model-xyz');
      await router.loadModelInfo(model);
      expect(router.modelTier, ModelTier.medium);
    });
  });
}
