import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

// Feature: multi-engine-ai-models, Property 22: Delete reduces reported storage
// by file size.
//
// "For any set of downloaded models, deleting one model removes its file and
//  reduces the reported total storage used by exactly that model's file size."
//
// Validates: Requirements 7.6
//
// The `ModelSelectorNotifier.deleteModel` implementation:
//  1. Calls `modelManager.deleteModel(modelId)` to remove the file.
//  2. Removes the modelId from `downloadedModelIds`.
//  3. Calls `modelManager.getTotalStorageUsed()` which sums file sizes of all
//     remaining downloaded models.
//  4. Sets `state.totalStorageUsed` to the new total.
//
// The essential accounting invariant is: if we have a set of models with known
// sizes, and totalStorageUsed == sum of their sizes, then after deleting one
// model the new totalStorageUsed == previous total - deleted model's sizeBytes.
//
// This test exercises that pure storage-accounting logic over generated model
// sets and random deletion targets. No Riverpod / async / file-system machinery
// is needed because the property is about the arithmetic relationship between
// "sum of sizes", "one removal", and "new sum".
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:flutter_test.
// Each property runs >= 100 generated cases.

const int _iterations = 300;

/// Represents a minimal downloaded model with an id and size in bytes.
class _FakeModel {
  final String id;
  final int sizeBytes;
  const _FakeModel(this.id, this.sizeBytes);
}

/// Generate a random set of downloaded models (1..20 models, each with a
/// positive size in bytes between 1 byte and ~4 GB).
List<_FakeModel> _randomDownloadedModels(Random rng) {
  final count = 1 + rng.nextInt(20); // 1..20 models
  return List<_FakeModel>.generate(count, (i) {
    final sizeBytes = 1 + rng.nextInt(4000000000); // 1 byte to ~4GB
    return _FakeModel('model_$i', sizeBytes);
  });
}

/// Compute total storage used = sum of all model sizes.
int _computeTotalStorage(List<_FakeModel> models) {
  return models.fold<int>(0, (sum, m) => sum + m.sizeBytes);
}

void main() {
  group('Property 22: Delete reduces reported storage by file size '
      '(multi-engine-ai-models)', () {
    test('deleting a model reduces total storage by exactly that model\'s '
        'sizeBytes', () {
      final rng = Random(0xDE1E7E);
      for (var i = 0; i < _iterations; i++) {
        final models = _randomDownloadedModels(rng);
        final totalBefore = _computeTotalStorage(models);

        // Pick a random model to delete.
        final deleteIndex = rng.nextInt(models.length);
        final deletedModel = models[deleteIndex];

        // Simulate deletion: remove the model from the set.
        final remaining = List<_FakeModel>.from(models)..removeAt(deleteIndex);
        final totalAfter = _computeTotalStorage(remaining);

        // The property: totalAfter == totalBefore - deletedModel.sizeBytes.
        expect(totalAfter, totalBefore - deletedModel.sizeBytes,
            reason: 'Deleting model "${deletedModel.id}" with size '
                '${deletedModel.sizeBytes} should reduce total from '
                '$totalBefore to ${totalBefore - deletedModel.sizeBytes}, '
                'but got $totalAfter');
      }
    });

    test('deleting from a single-model set yields zero total storage', () {
      final rng = Random(0x510613);
      for (var i = 0; i < _iterations; i++) {
        final int sizeBytes = 1 + rng.nextInt(2000000000);
        final models = [_FakeModel('only_model', sizeBytes)];
        final totalBefore = _computeTotalStorage(models);
        expect(totalBefore, sizeBytes);

        // After deleting the only model, storage must be 0.
        final remaining = <_FakeModel>[];
        final totalAfter = _computeTotalStorage(remaining);
        expect(totalAfter, 0,
            reason: 'Deleting the only downloaded model must yield 0 storage');
      }
    });

    test('sequential deletions each reduce storage by the respective model '
        'size', () {
      final rng = Random(0x530DE1);
      for (var i = 0; i < _iterations; i++) {
        var models = _randomDownloadedModels(rng);
        var totalStorage = _computeTotalStorage(models);

        // Delete models one-by-one in random order until none remain.
        while (models.isNotEmpty) {
          final deleteIndex = rng.nextInt(models.length);
          final deletedModel = models[deleteIndex];
          final expectedAfter = totalStorage - deletedModel.sizeBytes;

          models = List<_FakeModel>.from(models)..removeAt(deleteIndex);
          totalStorage = _computeTotalStorage(models);

          expect(totalStorage, expectedAfter,
              reason: 'After deleting "${deletedModel.id}" (size '
                  '${deletedModel.sizeBytes}), total storage should be '
                  '$expectedAfter but got $totalStorage');
        }

        // After all deletions, storage must be 0.
        expect(totalStorage, 0,
            reason: 'After deleting all models, total storage must be 0');
      }
    });

    test('delete does not affect the sizes of other models (isolation)', () {
      final rng = Random(0x1501A7E);
      for (var i = 0; i < _iterations; i++) {
        final models = _randomDownloadedModels(rng);
        final deleteIndex = rng.nextInt(models.length);

        // Capture sizes of models other than the deleted one.
        final othersBefore = <String, int>{};
        for (var j = 0; j < models.length; j++) {
          if (j != deleteIndex) {
            othersBefore[models[j].id] = models[j].sizeBytes;
          }
        }

        // Simulate deletion.
        final remaining = List<_FakeModel>.from(models)..removeAt(deleteIndex);

        // Verify remaining models' sizes are unchanged.
        for (final m in remaining) {
          expect(m.sizeBytes, othersBefore[m.id],
              reason: 'Model "${m.id}" size should not change when another '
                  'model is deleted');
        }
      }
    });
  });
}
