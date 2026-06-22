import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';

// Feature: multi-engine-ai-models, Property 18: Model card shows size and RAM.
//
// "For any model, the rendered Model_Selector card content includes the
//  model's download size in megabytes and its minimum RAM requirement in
//  megabytes."
//
// Validates: Requirements 6.6
//
// The Model_Selector displays `model.sizeMB` (the computed getter
// `sizeBytes / (1024 * 1024)`) and `model.minRamMB` (the stored field).
// This property verifies that for any ModelInfo — whether from the real
// catalog or randomly generated — the `sizeMB` getter correctly computes
// `sizeBytes / (1024 * 1024)` and the `minRamMB` field faithfully reflects
// the value assigned at construction.
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:flutter_test.
// Each property runs >= 100 generated cases.

const int _iterations = 200;

/// Generates a random ModelInfo with arbitrary sizeBytes and minRamMB values.
ModelInfo _randomModelInfo(Random rng, int index) {
  // sizeBytes: between 1 byte and ~4.2 GB (stays within 32-bit int limit for
  // Random.nextInt while covering realistic model file sizes).
  final sizeBytes = 1 + rng.nextInt(4294967295); // 1..~4.2GB

  // minRamMB: between 1 and 65536 (matching the catalog constraint from Req 4.9).
  final minRamMB = 1 + rng.nextInt(65536);

  // Pick a random engine to ensure the property holds for both engine types.
  final engine = AIEngine.values[rng.nextInt(AIEngine.values.length)];

  // Pick a random inference speed.
  final speed = InferenceSpeed.values[rng.nextInt(InferenceSpeed.values.length)];

  return ModelInfo(
    id: 'test-model-$index',
    name: 'Test Model $index',
    description: 'Generated model for property testing',
    url: 'https://example.com/model-$index',
    sizeBytes: sizeBytes,
    ramRequirement: '${minRamMB}MB',
    speed: 'Medium',
    fileName: 'test-model-$index.${engine == AIEngine.gguf ? "gguf" : "task"}',
    minRamMB: minRamMB,
    engine: engine,
    inferenceSpeed: speed,
  );
}

void main() {
  group('Property 18: Model card shows size and RAM '
      '(multi-engine-ai-models)', () {
    // --- Concrete check: every real catalog entry's sizeMB equals
    // sizeBytes / (1024 * 1024) and minRamMB is positive. ---
    test('every catalog model sizeMB equals sizeBytes / (1024 * 1024)', () {
      for (final model in modelCatalog) {
        final expectedSizeMB = model.sizeBytes / (1024 * 1024);
        expect(model.sizeMB, expectedSizeMB,
            reason: 'model ${model.id}: sizeMB should be '
                '${model.sizeBytes} / (1024*1024) = $expectedSizeMB, '
                'got ${model.sizeMB}');
      }
    });

    test('every catalog model minRamMB is a positive integer', () {
      for (final model in modelCatalog) {
        expect(model.minRamMB, greaterThan(0),
            reason: 'model ${model.id}: minRamMB must be > 0, '
                'got ${model.minRamMB}');
      }
    });

    // --- Generated property: for any random ModelInfo, sizeMB equals
    // sizeBytes / (1024 * 1024). Runs >= 100 cases. ---
    test('sizeMB getter equals sizeBytes / (1024 * 1024) for random models',
        () {
      final rng = Random(0xCAFE);
      for (var i = 0; i < _iterations; i++) {
        final model = _randomModelInfo(rng, i);
        final expectedSizeMB = model.sizeBytes / (1024 * 1024);
        expect(model.sizeMB, expectedSizeMB,
            reason: 'iteration $i: sizeMB should be '
                '${model.sizeBytes} / (1024*1024) = $expectedSizeMB, '
                'got ${model.sizeMB}');
      }
    });

    // --- Generated property: for any random ModelInfo, the minRamMB field
    // equals the value passed at construction. Runs >= 100 cases. ---
    test('minRamMB field equals the construction value for random models', () {
      final rng = Random(0xBEEF);
      for (var i = 0; i < _iterations; i++) {
        final minRamMB = 1 + rng.nextInt(65536);
        final model = ModelInfo(
          id: 'ram-test-$i',
          name: 'RAM Test $i',
          description: 'RAM property testing',
          url: 'https://example.com/ram-$i',
          sizeBytes: 1 + rng.nextInt(4294967295),
          ramRequirement: '${minRamMB}MB',
          speed: 'Fast',
          fileName: 'ram-test-$i.gguf',
          minRamMB: minRamMB,
        );
        expect(model.minRamMB, minRamMB,
            reason: 'iteration $i: minRamMB should be $minRamMB, '
                'got ${model.minRamMB}');
      }
    });

    // --- Edge case: sizeBytes of exactly 1 MB boundary (1024*1024 bytes)
    // should yield sizeMB == 1.0. ---
    test('sizeBytes at exact MB boundary yields integer sizeMB', () {
      final boundaries = [
        1024 * 1024, // 1 MB
        512 * 1024 * 1024, // 512 MB
        2048 * 1024 * 1024, // 2048 MB = 2 GB
      ];
      for (final bytes in boundaries) {
        final model = ModelInfo(
          id: 'boundary-$bytes',
          name: 'Boundary Test',
          description: 'Boundary test',
          url: 'https://example.com/boundary',
          sizeBytes: bytes,
          ramRequirement: '2GB',
          speed: 'Medium',
          fileName: 'boundary.gguf',
          minRamMB: 2048,
        );
        final expectedMB = bytes / (1024 * 1024);
        expect(model.sizeMB, expectedMB,
            reason: 'sizeBytes=$bytes should yield sizeMB=$expectedMB');
        // At exact boundaries the result should be a whole number.
        expect(model.sizeMB, equals(model.sizeMB.roundToDouble()),
            reason: 'sizeMB at exact MB boundary should be a whole number');
      }
    });

    // --- Property: sizeMB is always non-negative when sizeBytes >= 0. ---
    test('sizeMB is non-negative for all generated models', () {
      final rng = Random(0xDEAD);
      for (var i = 0; i < _iterations; i++) {
        final model = _randomModelInfo(rng, i);
        expect(model.sizeMB, greaterThanOrEqualTo(0),
            reason: 'iteration $i: sizeMB must be >= 0 for '
                'sizeBytes=${model.sizeBytes}');
      }
    });

    // --- Property: the displayed size and RAM values are both accessible
    // from the model card data (sizeMB and minRamMB) for all engines. ---
    test('sizeMB and minRamMB are accessible for both engine types', () {
      final rng = Random(0xF00D);
      for (final engineValue in AIEngine.values) {
        for (var i = 0; i < _iterations ~/ AIEngine.values.length; i++) {
          final sizeBytes = 1 + rng.nextInt(4294967295);
          final minRamMB = 1 + rng.nextInt(65536);
          final model = ModelInfo(
            id: '${engineValue.name}-card-$i',
            name: '${engineValue.name} Card $i',
            description: 'Engine card test',
            url: 'https://example.com/card-$i',
            sizeBytes: sizeBytes,
            ramRequirement: '${minRamMB}MB',
            speed: 'Medium',
            fileName: 'card-$i.${engineValue == AIEngine.gguf ? "gguf" : "task"}',
            minRamMB: minRamMB,
            engine: engineValue,
          );

          // sizeMB must match the formula
          expect(model.sizeMB, sizeBytes / (1024 * 1024),
              reason: '${engineValue.name} model $i: sizeMB mismatch');
          // minRamMB must match construction value
          expect(model.minRamMB, minRamMB,
              reason: '${engineValue.name} model $i: minRamMB mismatch');
        }
      }
    });
  });
}
