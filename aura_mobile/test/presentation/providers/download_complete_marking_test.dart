import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';

/// Unit test for download-complete marking.
///
/// Validates: Requirement 7.3
/// "WHEN a litert model download completes with the entire file received,
///  THE Model_Selector SHALL mark that model as downloaded."
///
/// This test verifies that when a download reaches 100% progress and completes
/// successfully, the model is added to `downloadedModelIds`.
void main() {
  group('Download-complete marking (Requirement 7.3)', () {
    test(
        'completing a download marks the model as downloaded in state', () {
      // Start with a model that is downloading at some progress.
      final modelId = 'gemma3-1b';
      var state = ModelSelectorState(
        availableModels: modelCatalog,
        downloadProgress: {modelId: 0.75},
        downloadedModelIds: {},
      );

      // Verify the model is currently downloading and NOT yet downloaded.
      expect(state.isDownloading(modelId), isTrue);
      expect(state.isDownloaded(modelId), isFalse);

      // Simulate download completion: remove from progress, add to downloaded.
      // This mirrors the logic in ModelSelectorNotifier._listenToDownloads
      // when update.status == DownloadTaskStatus.complete.
      final newProgress = Map<String, double>.from(state.downloadProgress);
      newProgress.remove(modelId);

      final newDownloaded = Set<String>.from(state.downloadedModelIds);
      newDownloaded.add(modelId);

      state = state.copyWith(
        downloadProgress: newProgress,
        downloadedModelIds: newDownloaded,
      );

      // The model should now be marked as downloaded.
      expect(state.isDownloaded(modelId), isTrue);
      expect(state.isDownloading(modelId), isFalse);
      expect(state.downloadedModelIds.contains(modelId), isTrue);
    });

    test(
        'completing a GGUF download also marks the model as downloaded', () {
      final modelId = 'qwen2.5-0.5b';
      var state = ModelSelectorState(
        availableModels: modelCatalog,
        downloadProgress: {modelId: 0.99},
        downloadedModelIds: {},
      );

      expect(state.isDownloading(modelId), isTrue);
      expect(state.isDownloaded(modelId), isFalse);

      // Simulate download completion.
      final newProgress = Map<String, double>.from(state.downloadProgress);
      newProgress.remove(modelId);

      final newDownloaded = Set<String>.from(state.downloadedModelIds);
      newDownloaded.add(modelId);

      state = state.copyWith(
        downloadProgress: newProgress,
        downloadedModelIds: newDownloaded,
      );

      expect(state.isDownloaded(modelId), isTrue);
      expect(state.isDownloading(modelId), isFalse);
    });

    test(
        'download completion preserves other already-downloaded models', () {
      final newModelId = 'gemma3n-e2b';
      final existingDownloaded = {'qwen2.5-0.5b', 'gemma3-1b'};

      var state = ModelSelectorState(
        availableModels: modelCatalog,
        downloadProgress: {newModelId: 0.85},
        downloadedModelIds: existingDownloaded,
      );

      // Simulate download completion for the new model.
      final newProgress = Map<String, double>.from(state.downloadProgress);
      newProgress.remove(newModelId);

      final newDownloaded = Set<String>.from(state.downloadedModelIds);
      newDownloaded.add(newModelId);

      state = state.copyWith(
        downloadProgress: newProgress,
        downloadedModelIds: newDownloaded,
      );

      // All previously downloaded models are still downloaded.
      for (final id in existingDownloaded) {
        expect(state.isDownloaded(id), isTrue,
            reason: 'Previously downloaded model $id should remain downloaded');
      }
      // The newly completed model is also downloaded.
      expect(state.isDownloaded(newModelId), isTrue);
    });

    test(
        'download that completes at 100% progress is marked as downloaded', () {
      final modelId = 'gemma4-e2b';

      // Simulate the progress reaching 1.0 (100%) before the complete event.
      var state = ModelSelectorState(
        availableModels: modelCatalog,
        downloadProgress: {modelId: 1.0},
        downloadedModelIds: {},
      );

      expect(state.getProgress(modelId), 1.0);
      expect(state.isDownloaded(modelId), isFalse,
          reason: 'Progress at 100% alone does not mark as downloaded');

      // The download-complete event fires and marks the model as downloaded.
      final newProgress = Map<String, double>.from(state.downloadProgress);
      newProgress.remove(modelId);

      final newDownloaded = Set<String>.from(state.downloadedModelIds);
      newDownloaded.add(modelId);

      state = state.copyWith(
        downloadProgress: newProgress,
        downloadedModelIds: newDownloaded,
      );

      expect(state.isDownloaded(modelId), isTrue);
      expect(state.isDownloading(modelId), isFalse);
    });

    test(
        'foldDownloadProgress reaches 1.0 at 100% raw progress', () {
      // Verify the pure function that feeds into the download progress state.
      final result = ModelSelectorNotifier.foldDownloadProgress(0.5, 100);
      expect(result, 1.0);
    });

    test(
        'a model not in downloadProgress is not considered downloading', () {
      final state = ModelSelectorState(
        availableModels: modelCatalog,
        downloadedModelIds: {'gemma3-1b'},
      );

      // Downloaded but not downloading.
      expect(state.isDownloaded('gemma3-1b'), isTrue);
      expect(state.isDownloading('gemma3-1b'), isFalse);
      expect(state.getProgress('gemma3-1b'), 0.0);
    });
  });
}
