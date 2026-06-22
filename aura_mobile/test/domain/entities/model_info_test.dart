import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';

ModelInfo _build({
  AIEngine? engine,
  bool? supportsToolCalling,
  bool? supportsVision,
  InferenceSpeed? inferenceSpeed,
  int sizeBytes = 1024 * 1024,
}) {
  return ModelInfo(
    id: 'test-model',
    name: 'Test Model',
    description: 'A model for testing.',
    url: 'https://example.com/model.bin',
    sizeBytes: sizeBytes,
    ramRequirement: '2GB',
    speed: 'Fast',
    fileName: 'model.bin',
    minRamMB: 2048,
    engine: engine ?? AIEngine.gguf,
    supportsToolCalling: supportsToolCalling ?? false,
    supportsVision: supportsVision ?? false,
    inferenceSpeed: inferenceSpeed ?? InferenceSpeed.medium,
  );
}

void main() {
  group('ModelInfo defaults', () {
    test('engine defaults to gguf', () {
      final model = ModelInfo(
        id: 'id',
        name: 'name',
        description: 'desc',
        url: 'url',
        sizeBytes: 100,
        ramRequirement: '1GB',
        speed: 'Fast',
        fileName: 'file.gguf',
        minRamMB: 1024,
      );
      expect(model.engine, AIEngine.gguf);
      expect(model.supportsToolCalling, isFalse);
      expect(model.supportsVision, isFalse);
      expect(model.inferenceSpeed, InferenceSpeed.medium);
    });

    test('existing Qwen catalog entries remain gguf', () {
      expect(modelCatalog, isNotEmpty);
      final qwenModels =
          modelCatalog.where((model) => model.id.startsWith('qwen'));
      expect(qwenModels, isNotEmpty);
      for (final model in qwenModels) {
        expect(model.engine, AIEngine.gguf);
      }
    });
  });

  group('ModelInfo.sizeMB', () {
    test('converts bytes to megabytes', () {
      final model = _build(sizeBytes: 1024 * 1024);
      expect(model.sizeMB, 1.0);
    });

    test('handles fractional megabytes', () {
      final model = _build(sizeBytes: 1024 * 1024 * 3 ~/ 2);
      expect(model.sizeMB, closeTo(1.5, 1e-9));
    });
  });

  group('ModelInfo.qualifiesFastBadge', () {
    test('is true only for fast inference speed', () {
      expect(_build(inferenceSpeed: InferenceSpeed.fast).qualifiesFastBadge,
          isTrue);
      expect(_build(inferenceSpeed: InferenceSpeed.medium).qualifiesFastBadge,
          isFalse);
      expect(_build(inferenceSpeed: InferenceSpeed.slow).qualifiesFastBadge,
          isFalse);
    });
  });

  group('AIEngine.fromId', () {
    test('resolves gguf identifier', () {
      expect(AIEngine.fromId('gguf'), AIEngine.gguf);
    });

    test('resolves litert identifier', () {
      expect(AIEngine.fromId('litert'), AIEngine.litert);
    });

    test('resolves every enum value from its name', () {
      for (final engine in AIEngine.values) {
        expect(AIEngine.fromId(engine.name), engine);
      }
    });

    test('throws ArgumentError on unknown id', () {
      expect(() => AIEngine.fromId('unknown'), throwsArgumentError);
    });

    test('throws ArgumentError on empty id', () {
      expect(() => AIEngine.fromId(''), throwsArgumentError);
    });

    test('is case-sensitive and throws on mismatched casing', () {
      expect(() => AIEngine.fromId('GGUF'), throwsArgumentError);
    });
  });
}
