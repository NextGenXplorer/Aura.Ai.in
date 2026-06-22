import 'dart:math';

import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/presentation/providers/model_catalog_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

// Feature: multi-engine-ai-models, Property 16: Engine grouping partitions
// the catalog.
//
// "groupCatalogByEngine(catalog) returns List<EngineGroup> such that the
//  groups are disjoint, their union equals the original catalog (preserving
//  each model's order within its group), and the set of group engines equals
//  exactly the set of distinct engine values present among the input models."
//
// **Validates: Requirements 6.1**
//
// This test generates random catalogs of varying sizes with mixed engine values
// and verifies the partition properties. No glados dependency is used; instead
// a generator-based approach with Random + iterations >= 100 is employed.

const int _iterations = 300;

/// Generate a random ModelInfo with the given engine.
ModelInfo _randomModel(Random rng, AIEngine engine, int index) {
  final id = 'model_${engine.name}_$index';
  final sizeBytes = 100000000 + rng.nextInt(4000000000);
  final minRamMB = 1024 + rng.nextInt(7000);
  final speeds = InferenceSpeed.values;
  final speed = speeds[rng.nextInt(speeds.length)];

  return ModelInfo(
    id: id,
    name: 'Test Model $index',
    description: 'A test model for property testing',
    url: 'https://example.com/$id',
    sizeBytes: sizeBytes,
    ramRequirement: '${minRamMB}MB',
    speed: speed.name,
    fileName: '$id.${engine == AIEngine.gguf ? "gguf" : "task"}',
    minRamMB: minRamMB,
    engine: engine,
    supportsToolCalling: rng.nextBool(),
    supportsVision: rng.nextBool(),
    inferenceSpeed: speed,
  );
}

/// Generate a random catalog of 0..30 models with mixed engines.
List<ModelInfo> _randomCatalog(Random rng) {
  final count = rng.nextInt(31); // 0..30 models
  final engines = AIEngine.values;
  return List<ModelInfo>.generate(count, (i) {
    final engine = engines[rng.nextInt(engines.length)];
    return _randomModel(rng, engine, i);
  });
}

void main() {
  group('Property 16: Engine grouping partitions the catalog '
      '(multi-engine-ai-models)', () {
    test('groups are disjoint: no model appears in more than one group', () {
      final rng = Random(0xA016);
      for (var i = 0; i < _iterations; i++) {
        final catalog = _randomCatalog(rng);
        final groups = groupCatalogByEngine(catalog);

        // Collect all model ids across groups and check for duplicates.
        final allIds = <String>[];
        for (final group in groups) {
          for (final model in group.models) {
            allIds.add(model.id);
          }
        }

        final uniqueIds = allIds.toSet();
        expect(allIds.length, uniqueIds.length,
            reason: 'Iteration $i: A model appears in more than one group');
      }
    });

    test('union of groups equals the original catalog (same models, same '
        'total count)', () {
      final rng = Random(0xA110);
      for (var i = 0; i < _iterations; i++) {
        final catalog = _randomCatalog(rng);
        final groups = groupCatalogByEngine(catalog);

        // The total number of models across all groups should equal catalog
        // size.
        final totalModelsInGroups =
            groups.fold<int>(0, (sum, g) => sum + g.models.length);
        expect(totalModelsInGroups, catalog.length,
            reason: 'Iteration $i: Union of groups must have same count as '
                'catalog');

        // Every model in the catalog appears in exactly one group.
        final groupedIds = <String>{};
        for (final group in groups) {
          for (final model in group.models) {
            groupedIds.add(model.id);
          }
        }
        for (final model in catalog) {
          expect(groupedIds.contains(model.id), isTrue,
              reason: 'Iteration $i: Model "${model.id}" from catalog is '
                  'missing from the groups');
        }
      }
    });

    test('each model in a group has the engine matching the group\'s engine',
        () {
      final rng = Random(0xE6C1A);
      for (var i = 0; i < _iterations; i++) {
        final catalog = _randomCatalog(rng);
        final groups = groupCatalogByEngine(catalog);

        for (final group in groups) {
          for (final model in group.models) {
            expect(model.engine, group.engine,
                reason: 'Iteration $i: Model "${model.id}" has engine '
                    '${model.engine} but is in group ${group.engine}');
          }
        }
      }
    });

    test('the set of group engines equals the set of distinct engines in the '
        'catalog', () {
      final rng = Random(0xD157A);
      for (var i = 0; i < _iterations; i++) {
        final catalog = _randomCatalog(rng);
        final groups = groupCatalogByEngine(catalog);

        final distinctEnginesInCatalog =
            catalog.map((m) => m.engine).toSet();
        final groupEngines = groups.map((g) => g.engine).toSet();

        expect(groupEngines, distinctEnginesInCatalog,
            reason: 'Iteration $i: Group engines must exactly match the '
                'distinct engines present in the catalog');
      }
    });

    test('order within each group preserves the original catalog order', () {
      final rng = Random(0x00D3E);
      for (var i = 0; i < _iterations; i++) {
        final catalog = _randomCatalog(rng);
        final groups = groupCatalogByEngine(catalog);

        for (final group in groups) {
          // Get the indices of this group's models in the original catalog.
          final indices = group.models.map((m) {
            return catalog.indexWhere((c) => c.id == m.id);
          }).toList();

          // Indices must be strictly increasing (preserves original order).
          for (var j = 1; j < indices.length; j++) {
            expect(indices[j] > indices[j - 1], isTrue,
                reason: 'Iteration $i: Models in group ${group.engine} are '
                    'not in original catalog order. Index ${indices[j]} should '
                    'be > ${indices[j - 1]}');
          }
        }
      }
    });

    test('an empty catalog yields no groups', () {
      final groups = groupCatalogByEngine([]);
      expect(groups, isEmpty,
          reason: 'An empty catalog must produce zero groups');
    });

    test('a single-engine catalog yields exactly one group containing all '
        'models', () {
      final rng = Random(0x5106);
      for (var i = 0; i < _iterations; i++) {
        // Generate a catalog where all models share a single engine.
        final engine = AIEngine.values[rng.nextInt(AIEngine.values.length)];
        final count = 1 + rng.nextInt(20); // 1..20 models
        final catalog = List<ModelInfo>.generate(
            count, (idx) => _randomModel(rng, engine, idx));

        final groups = groupCatalogByEngine(catalog);

        expect(groups.length, 1,
            reason: 'Iteration $i: A single-engine catalog should produce '
                'exactly one group');
        expect(groups.first.engine, engine);
        expect(groups.first.models.length, catalog.length);
      }
    });
  });
}
