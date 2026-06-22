import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';

// Feature: multi-engine-ai-models, Property 10: Catalog invariants
//
// "For any entry in the Model_Catalog, the engine field is a valid AIEngine
//  value, the inference speed is a valid {fast, medium, slow} value, the
//  tool-calling and vision fields are booleans, the download size in MB is
//  greater than 0 and at most 99,999, and the minimum RAM in MB is greater
//  than 0 and at most 65,536; and across the whole catalog every entry's id is
//  unique."
//
// Validates: Requirements 4.1, 4.2, 4.8, 4.9, 4.10
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. Each
// property runs >= 100 generated cases.

const int _iterations = 250;

/// Inclusive upper bound on a model's download size in megabytes (Req 4.8).
const double _maxSizeMB = 99999;

/// Inclusive upper bound on a model's minimum RAM in megabytes (Req 4.9).
const int _maxMinRamMB = 65536;

/// Pure predicate capturing every per-entry invariant of Property 10. A
/// `ModelInfo` is well-formed iff all of these hold. The engine and inference
/// speed fields are statically typed enums, so validity is checked by
/// membership in the declared value set (guards against any future widening or
/// reflective construction).
bool _entryIsValid(ModelInfo m) {
  final engineValid = AIEngine.values.contains(m.engine);
  final speedValid = InferenceSpeed.values.contains(m.inferenceSpeed);
  // ignore: unnecessary_type_check
  final flagsAreBool =
      (m.supportsToolCalling is bool) && (m.supportsVision is bool);
  final sizeValid = m.sizeMB > 0 && m.sizeMB <= _maxSizeMB;
  final ramValid = m.minRamMB > 0 && m.minRamMB <= _maxMinRamMB;
  return engineValid && speedValid && flagsAreBool && sizeValid && ramValid;
}

/// Pure predicate for the catalog-wide uniqueness invariant (Req 4.10).
bool _idsAreUnique(List<ModelInfo> catalog) =>
    catalog.map((m) => m.id).toSet().length == catalog.length;

/// Generates a `ModelInfo` whose fields are uniformly drawn from the *valid*
/// input space. `id` is supplied by the caller so callers control uniqueness.
ModelInfo _genValid(Random rng, String id) {
  // Draw sizeMB uniformly from (0, 99999] then derive whole bytes. We generate
  // the MB value directly (rather than bytes via nextInt) because the byte
  // count for 99999 MB exceeds nextInt's 2^32 argument limit. Clamp the low
  // end so the byte count is always >= 1 (sizeMB strictly > 0).
  final sizeMB = max(0.001, rng.nextDouble() * _maxSizeMB);
  final sizeBytes = (sizeMB * 1024 * 1024).round();
  final minRamMB = 1 + rng.nextInt(_maxMinRamMB); // [1, 65536]
  return ModelInfo(
    id: id,
    name: 'Model $id',
    description: 'Generated model $id',
    url: 'https://example.com/$id.bin',
    sizeBytes: sizeBytes,
    ramRequirement: '${(minRamMB / 1024).ceil()}GB',
    speed: 'Fast',
    fileName: '$id.bin',
    minRamMB: minRamMB,
    engine: AIEngine.values[rng.nextInt(AIEngine.values.length)],
    supportsToolCalling: rng.nextBool(),
    supportsVision: rng.nextBool(),
    inferenceSpeed:
        InferenceSpeed.values[rng.nextInt(InferenceSpeed.values.length)],
  );
}

void main() {
  group('Property 10: Catalog invariants (multi-engine-ai-models)', () {
    // --- The real, shipped catalog must satisfy every invariant. ---
    test('every shipped catalog entry satisfies the per-entry invariants', () {
      expect(modelCatalog, isNotEmpty);
      for (final model in modelCatalog) {
        expect(_entryIsValid(model), isTrue,
            reason: 'catalog entry "${model.id}" violates an invariant: '
                'engine=${model.engine}, speed=${model.inferenceSpeed}, '
                'sizeMB=${model.sizeMB}, minRamMB=${model.minRamMB}');
        // Spell out each bound for precise failure messages.
        expect(AIEngine.values.contains(model.engine), isTrue,
            reason: '"${model.id}" engine is not a valid AIEngine value');
        expect(InferenceSpeed.values.contains(model.inferenceSpeed), isTrue,
            reason: '"${model.id}" inferenceSpeed is not a valid value');
        expect(model.sizeMB, greaterThan(0),
            reason: '"${model.id}" sizeMB must be > 0');
        expect(model.sizeMB, lessThanOrEqualTo(_maxSizeMB),
            reason: '"${model.id}" sizeMB must be <= $_maxSizeMB');
        expect(model.minRamMB, greaterThan(0),
            reason: '"${model.id}" minRamMB must be > 0');
        expect(model.minRamMB, lessThanOrEqualTo(_maxMinRamMB),
            reason: '"${model.id}" minRamMB must be <= $_maxMinRamMB');
      }
    });

    test('shipped catalog has globally unique ids', () {
      expect(_idsAreUnique(modelCatalog), isTrue,
          reason: 'duplicate id(s) found in modelCatalog: '
              '${_duplicateIds(modelCatalog)}');
    });

    // --- Generated valid catalogs always pass the invariant checks. ---
    test('any catalog of generated valid entries satisfies all invariants', () {
      final rng = Random(20240510);
      for (var i = 0; i < _iterations; i++) {
        final size = 1 + rng.nextInt(12);
        final catalog = [
          for (var j = 0; j < size; j++) _genValid(rng, 'model-$i-$j'),
        ];
        for (final m in catalog) {
          expect(_entryIsValid(m), isTrue,
              reason: 'generated entry failed invariants: ${m.id}');
        }
        expect(_idsAreUnique(catalog), isTrue,
            reason: 'generated catalog should have unique ids');
      }
    });

    // --- The uniqueness predicate detects an injected duplicate id. ---
    test('uniqueness invariant rejects any catalog with a duplicated id', () {
      final rng = Random(777);
      for (var i = 0; i < _iterations; i++) {
        final size = 2 + rng.nextInt(10);
        final catalog = [
          for (var j = 0; j < size; j++) _genValid(rng, 'm-$i-$j'),
        ];
        // Duplicate a random existing id into a new entry.
        final dupId = catalog[rng.nextInt(catalog.length)].id;
        catalog.add(_genValid(rng, dupId));
        expect(_idsAreUnique(catalog), isFalse,
            reason: 'duplicate id "$dupId" should be detected');
      }
    });

    // --- The per-entry predicate detects out-of-range size / RAM. ---
    test('per-entry invariant rejects size or RAM outside the valid range', () {
      final rng = Random(31337);
      for (var i = 0; i < _iterations; i++) {
        // Zero-size is invalid (sizeMB == 0).
        final zeroSize = ModelInfo(
          id: 'zero-$i',
          name: 'n',
          description: 'd',
          url: 'u',
          sizeBytes: 0,
          ramRequirement: '1GB',
          speed: 'Fast',
          fileName: 'f.bin',
          minRamMB: 1 + rng.nextInt(_maxMinRamMB),
        );
        expect(_entryIsValid(zeroSize), isFalse,
            reason: 'sizeBytes == 0 should be invalid');

        // RAM over the bound is invalid.
        final overRam = ModelInfo(
          id: 'overram-$i',
          name: 'n',
          description: 'd',
          url: 'u',
          sizeBytes: 1 + rng.nextInt(1024 * 1024),
          ramRequirement: '1GB',
          speed: 'Fast',
          fileName: 'f.bin',
          minRamMB: _maxMinRamMB + 1 + rng.nextInt(100000),
        );
        expect(_entryIsValid(overRam), isFalse,
            reason: 'minRamMB > $_maxMinRamMB should be invalid');

        // Zero RAM is invalid.
        final zeroRam = ModelInfo(
          id: 'zeroram-$i',
          name: 'n',
          description: 'd',
          url: 'u',
          sizeBytes: 1 + rng.nextInt(1024 * 1024),
          ramRequirement: '1GB',
          speed: 'Fast',
          fileName: 'f.bin',
          minRamMB: 0,
        );
        expect(_entryIsValid(zeroRam), isFalse,
            reason: 'minRamMB == 0 should be invalid');
      }
    });
  });
}

/// Returns the set of ids that appear more than once in [catalog].
Set<String> _duplicateIds(List<ModelInfo> catalog) {
  final seen = <String>{};
  final dups = <String>{};
  for (final m in catalog) {
    if (!seen.add(m.id)) dups.add(m.id);
  }
  return dups;
}
