import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';

/// Tests for ModelSelectorState without the complexity of Riverpod and async initialization
void main() {
  group('ModelSelectorState - State management', () {
    test('should track download progress', () {
      final state = ModelSelectorState(
        availableModels: modelCatalog,
        downloadProgress: {'qwen2.5-0.5b': 0.5},
      );

      expect(state.isDownloading('qwen2.5-0.5b'), true);
      expect(state.getProgress('qwen2.5-0.5b'), 0.5);
      expect(state.isDownloading('qwen2.5-1.5b'), false);
    });

    test('should track downloaded models', () {
      final state = ModelSelectorState(
        availableModels: modelCatalog,
        downloadedModelIds: {'qwen2.5-0.5b', 'qwen2.5-1.5b'},
      );

      expect(state.isDownloaded('qwen2.5-0.5b'), true);
      expect(state.isDownloaded('qwen2.5-1.5b'), true);
      expect(state.isDownloaded('qwen2.5-3b'), false);
    });

    test('should track active model', () {
      final state = ModelSelectorState(
        availableModels: modelCatalog,
        activeModelId: 'qwen2.5-0.5b',
      );

      expect(state.isActive('qwen2.5-0.5b'), true);
      expect(state.isActive('qwen2.5-1.5b'), false);
    });

    test('should track download errors', () {
      final state = ModelSelectorState(
        availableModels: modelCatalog,
        downloadErrors: {
          'qwen2.5-0.5b': 'Download failed',
          'qwen2.5-1.5b': 'Insufficient space',
        },
      );

      expect(state.getError('qwen2.5-0.5b'), 'Download failed');
      expect(state.getError('qwen2.5-1.5b'), 'Insufficient space');
      expect(state.getError('qwen2.5-3b'), isNull);
    });

    test('should track total storage used', () {
      final state = ModelSelectorState(
        availableModels: modelCatalog,
        totalStorageUsed: 1500000000, // 1.5GB
      );

      expect(state.totalStorageUsed, 1500000000);
    });
  });

  group('ModelSelectorState - copyWith functionality', () {
    test('should update download progress while preserving other fields', () {
      final original = ModelSelectorState(
        availableModels: modelCatalog,
        downloadedModelIds: {'qwen2.5-0.5b'},
        activeModelId: 'qwen2.5-0.5b',
        downloadProgress: {'qwen2.5-1.5b': 0.3},
        totalStorageUsed: 1000000,
      );

      final modified = original.copyWith(
        downloadProgress: {'qwen2.5-1.5b': 0.6},
      );

      expect(modified.downloadedModelIds, original.downloadedModelIds);
      expect(modified.activeModelId, original.activeModelId);
      expect(modified.totalStorageUsed, original.totalStorageUsed);
      expect(modified.getProgress('qwen2.5-1.5b'), 0.6);
    });

    test('should add downloaded model', () {
      final original = ModelSelectorState(
        availableModels: modelCatalog,
        downloadedModelIds: {'qwen2.5-0.5b'},
      );

      final modified = original.copyWith(
        downloadedModelIds: {'qwen2.5-0.5b', 'qwen2.5-1.5b'},
      );

      expect(modified.isDownloaded('qwen2.5-0.5b'), true);
      expect(modified.isDownloaded('qwen2.5-1.5b'), true);
    });

    test('should update active model', () {
      final original = ModelSelectorState(
        availableModels: modelCatalog,
        activeModelId: 'qwen2.5-0.5b',
      );

      final modified = original.copyWith(
        activeModelId: 'qwen2.5-1.5b',
      );

      expect(modified.isActive('qwen2.5-0.5b'), false);
      expect(modified.isActive('qwen2.5-1.5b'), true);
    });

    test('should add and remove errors', () {
      final original = ModelSelectorState(
        availableModels: modelCatalog,
        downloadErrors: {'qwen2.5-0.5b': 'Error 1'},
      );

      final modified = original.copyWith(
        downloadErrors: {
          'qwen2.5-1.5b': 'Error 2',
        },
      );

      expect(modified.getError('qwen2.5-0.5b'), isNull);
      expect(modified.getError('qwen2.5-1.5b'), 'Error 2');
    });

    test('should update storage used', () {
      final original = ModelSelectorState(
        availableModels: modelCatalog,
        totalStorageUsed: 1000000,
      );

      final modified = original.copyWith(
        totalStorageUsed: 2000000,
      );

      expect(modified.totalStorageUsed, 2000000);
    });
  });

  group('ModelSelectorState - Multiple models workflow', () {
    test('should handle multiple simultaneous downloads', () {
      final state = ModelSelectorState(
        availableModels: modelCatalog,
        downloadProgress: {
          'qwen2.5-0.5b': 0.3,
          'qwen2.5-1.5b': 0.6,
          'qwen2.5-3b': 0.9,
        },
      );

      expect(state.isDownloading('qwen2.5-0.5b'), true);
      expect(state.isDownloading('qwen2.5-1.5b'), true);
      expect(state.isDownloading('qwen2.5-3b'), true);
      expect(state.getProgress('qwen2.5-0.5b'), 0.3);
      expect(state.getProgress('qwen2.5-1.5b'), 0.6);
      expect(state.getProgress('qwen2.5-3b'), 0.9);
    });

    test('should handle complete download workflow', () {
      // Initial state: nothing downloaded
      var state = ModelSelectorState(
        availableModels: modelCatalog,
      );
      expect(state.isDownloaded('qwen2.5-0.5b'), false);
      expect(state.isDownloading('qwen2.5-0.5b'), false);

      // Start download
      state = state.copyWith(
        downloadProgress: {'qwen2.5-0.5b': 0.0},
      );
      expect(state.isDownloading('qwen2.5-0.5b'), true);

      // Progress update
      state = state.copyWith(
        downloadProgress: {'qwen2.5-0.5b': 0.5},
      );
      expect(state.getProgress('qwen2.5-0.5b'), 0.5);

      // Download complete
      state = state.copyWith(
        downloadProgress: {},
        downloadedModelIds: {'qwen2.5-0.5b'},
      );
      expect(state.isDownloading('qwen2.5-0.5b'), false);
      expect(state.isDownloaded('qwen2.5-0.5b'), true);

      // Select as active
      state = state.copyWith(
        activeModelId: 'qwen2.5-0.5b',
      );
      expect(state.isActive('qwen2.5-0.5b'), true);
    });

    test('should handle download failure and retry', () {
      var state = ModelSelectorState(
        availableModels: modelCatalog,
      );

      // Start download
      state = state.copyWith(
        downloadProgress: {'qwen2.5-0.5b': 0.3},
      );
      expect(state.isDownloading('qwen2.5-0.5b'), true);

      // Download fails
      state = state.copyWith(
        downloadProgress: {},
        downloadErrors: {'qwen2.5-0.5b': 'Network error'},
      );
      expect(state.isDownloading('qwen2.5-0.5b'), false);
      expect(state.getError('qwen2.5-0.5b'), 'Network error');

      // Retry
      state = state.copyWith(
        downloadProgress: {'qwen2.5-0.5b': 0.0},
        downloadErrors: {},
      );
      expect(state.isDownloading('qwen2.5-0.5b'), true);
      expect(state.getError('qwen2.5-0.5b'), isNull);
    });
  });

  group('ModelSelectorState - Edge cases', () {
    test('should handle empty state', () {
      final state = ModelSelectorState(
        availableModels: modelCatalog,
      );

      expect(state.downloadedModelIds, isEmpty);
      expect(state.downloadProgress, isEmpty);
      expect(state.downloadErrors, isEmpty);
      expect(state.activeModelId, isNull);
      expect(state.totalStorageUsed, 0);
    });

    test('should handle model deletion', () {
      var state = ModelSelectorState(
        availableModels: modelCatalog,
        downloadedModelIds: {'qwen2.5-0.5b', 'qwen2.5-1.5b'},
        activeModelId: 'qwen2.5-0.5b',
        totalStorageUsed: 1500000000,
      );

      // Delete active model (create new state without active model)
      state = ModelSelectorState(
        availableModels: modelCatalog,
        downloadedModelIds: {'qwen2.5-1.5b'},
        totalStorageUsed: 900000000,
      );

      expect(state.isDownloaded('qwen2.5-0.5b'), false);
      expect(state.isDownloaded('qwen2.5-1.5b'), true);
      expect(state.activeModelId, isNull);
      expect(state.totalStorageUsed, 900000000);
    });

    test('should handle switching active models', () {
      var state = ModelSelectorState(
        availableModels: modelCatalog,
        downloadedModelIds: {'qwen2.5-0.5b', 'qwen2.5-1.5b'},
        activeModelId: 'qwen2.5-0.5b',
      );

      expect(state.isActive('qwen2.5-0.5b'), true);

      // Switch to different model
      state = state.copyWith(
        activeModelId: 'qwen2.5-1.5b',
      );

      expect(state.isActive('qwen2.5-0.5b'), false);
      expect(state.isActive('qwen2.5-1.5b'), true);
    });
  });
}
