import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/data/datasources/model_manager.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Model Manager Provider
final modelManagerProvider = Provider((ref) => ModelManager());

/// Maximum number of total download attempts before a download is treated as
/// failed (Req 7.4).
const int kMaxDownloadAttempts = 3;

/// What to do after a download attempt has failed.
enum DownloadFailureDecision {
  /// Another attempt is allowed — retry the download.
  retry,

  /// All attempts have been used — remove the partial file and report failure.
  exhausted,
}

/// Pure decision used by the retry logic.
///
/// Given the number of attempts made so far ([attemptsSoFar], 1-based), decide
/// whether another retry is allowed or the download has exhausted its attempts.
/// A retry is allowed only while fewer than [maxAttempts] attempts have been
/// made (Req 7.4); on the final failure the caller removes the partial file and
/// reports failure to the user (Req 7.5).
DownloadFailureDecision decideDownloadFailure(
  int attemptsSoFar, {
  int maxAttempts = kMaxDownloadAttempts,
}) {
  return attemptsSoFar < maxAttempts
      ? DownloadFailureDecision.retry
      : DownloadFailureDecision.exhausted;
}

// Model Selector State
class ModelSelectorState {
  final List<ModelInfo> availableModels;
  final Set<String> downloadedModelIds;
  final String? activeModelId;
  final Map<String, double> downloadProgress;
  final Map<String, String?> downloadErrors;
  final int totalStorageUsed;

  ModelSelectorState({
    required this.availableModels,
    this.downloadedModelIds = const {},
    this.activeModelId,
    this.downloadProgress = const {},
    this.downloadErrors = const {},
    this.totalStorageUsed = 0,
  });

  bool isDownloaded(String modelId) => downloadedModelIds.contains(modelId);
  bool isActive(String modelId) => activeModelId == modelId;
  bool isDownloading(String modelId) => downloadProgress.containsKey(modelId);
  double getProgress(String modelId) => downloadProgress[modelId] ?? 0.0;
  String? getError(String modelId) => downloadErrors[modelId];

  ModelSelectorState copyWith({
    List<ModelInfo>? availableModels,
    Set<String>? downloadedModelIds,
    String? activeModelId,
    Map<String, double>? downloadProgress,
    Map<String, String?>? downloadErrors,
    int? totalStorageUsed,
  }) {
    return ModelSelectorState(
      availableModels: availableModels ?? this.availableModels,
      downloadedModelIds: downloadedModelIds ?? this.downloadedModelIds,
      activeModelId: activeModelId ?? this.activeModelId,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadErrors: downloadErrors ?? this.downloadErrors,
      totalStorageUsed: totalStorageUsed ?? this.totalStorageUsed,
    );
  }
}

// Model Selector Notifier
class ModelSelectorNotifier extends StateNotifier<ModelSelectorState> {
  final Ref _ref;
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  StreamSubscription? _downloadSubscription;
  final Map<String, String> _taskIdToModelId = {};
  final Map<String, int> _downloadRetryCount = {};

  ModelSelectorNotifier(this._ref)
      : super(ModelSelectorState(availableModels: modelCatalog)) {
    _loadState();
    _listenToDownloads();
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    super.dispose();
  }

  /// Folds a raw download progress reading into the reported progress value.
  ///
  /// [previous] is the last reported progress, already a value in `[0, 1]`.
  /// [rawPercent] is a freshly observed progress reading on a 0–100 percentage
  /// scale (as emitted by the download pipeline as more bytes are received),
  /// supplied as an `int` or `double`.
  ///
  /// The result is always clamped to the closed interval `[0, 1]` and is never
  /// less than [previous], so the reported progress is bounded and monotonic
  /// non-decreasing across readings, even across retries (Req 7.2).
  static double foldDownloadProgress(double previous, num rawPercent) {
    final reported = (rawPercent / 100).clamp(0.0, 1.0);
    return reported < previous ? previous : reported;
  }

  void _listenToDownloads() {
    final runAnywhere = _ref.read(runAnywhereProvider);
    _downloadSubscription = runAnywhere.downloadUpdates.listen((update) {
      String? modelId = _taskIdToModelId[update.id];

      // Recovery logic: If the taskId (URL) isn't in our map, 
      // look it up in the available models. This happens on app restart.
      if (modelId == null) {
        try {
          final model = state.availableModels.firstWhere((m) => m.url == update.id);
          modelId = model.id;
          _taskIdToModelId[update.id] = modelId;
        } catch (_) {
          return; // Not our model
        }
      }

      if (update.status == DownloadTaskStatus.running) {
        // Report progress as a value in [0, 1] that never decreases as more
        // bytes arrive, even across retries (Req 7.2).
        final current = state.downloadProgress[modelId] ?? 0.0;
        final monotonic = foldDownloadProgress(current, update.progress);
        final newProgress = Map<String, double>.from(state.downloadProgress);
        newProgress[modelId] = monotonic;
        state = state.copyWith(downloadProgress: newProgress);
      } else if (update.status == DownloadTaskStatus.complete) {
        final newProgress = Map<String, double>.from(state.downloadProgress);
        newProgress.remove(modelId);

        final newDownloaded = Set<String>.from(state.downloadedModelIds);
        newDownloaded.add(modelId);

        _updateStorageUsed();

        state = state.copyWith(
          downloadProgress: newProgress,
          downloadedModelIds: newDownloaded,
        );

        if (state.activeModelId == null) {
          selectModel(modelId);
        }
        _taskIdToModelId.remove(update.id);
      } else if (update.status == DownloadTaskStatus.failed) {
        _taskIdToModelId.remove(update.id);

        // _downloadRetryCount holds the number of attempts made so far
        // (1-based). Allow up to 3 total attempts (Req 7.4).
        final attempts = _downloadRetryCount[modelId] ?? 1;

        if (decideDownloadFailure(attempts) == DownloadFailureDecision.retry) {
          _errorHandler.logWarning(
            'Download failed for $modelId. Retrying (attempt ${attempts + 1}/3)...',
          );

          final newErrors = Map<String, String?>.from(state.downloadErrors);
          newErrors[modelId] = 'Download failed. Retrying (attempt ${attempts + 1}/3)...';
          state = state.copyWith(downloadErrors: newErrors);

          // Retry after delay (don't await to avoid blocking the stream)
          retryDownload(modelId);
        } else {
          // All 3 attempts exhausted: remove the partial file and report
          // failure to the user (Req 7.5).
          _failDownloadAfterExhaustion(modelId);
        }
      }
    });
  }

  Future<void> _updateStorageUsed() async {
    final modelManager = _ref.read(modelManagerProvider);
    final totalStorage = await modelManager.getTotalStorageUsed();
    state = state.copyWith(totalStorageUsed: totalStorage);
  }

  Future<void> _loadState() async {
    final modelManager = _ref.read(modelManagerProvider);
    final runAnywhere = _ref.read(runAnywhereProvider);
    final prefs = await SharedPreferences.getInstance();

    // Ensure RunAnywhere is initialized so we can check tasks
    await runAnywhere.initialize();

    final downloadedIds = <String>{};
    final downloadProgress = <String, double>{};
    final downloadErrors = <String, String?>{};

    for (final model in modelCatalog) {
      if (await modelManager.isModelDownloaded(model.id)) {
        downloadedIds.add(model.id);
        // A confirmed-downloaded model must not carry a stale error from a
        // prior failed attempt.
        downloadErrors.remove(model.id);
      } else {
        await modelManager.verifyAndCleanupModel(model.id);
      }
    }

    String? activeModelIdCandidate = prefs.getString('active_model_id');
    if (activeModelIdCandidate == null) {
      final path = prefs.getString('selected_model_path');
      if (path != null) {
        try {
          final model = modelCatalog.firstWhere((m) => path.contains(m.fileName) || path.contains(m.id), orElse: () => modelCatalog.first);
          for (final mId in downloadedIds) {
            final mPath = await modelManager.getModelPath(mId);
            if (mPath == path) {
              activeModelIdCandidate = mId;
              break;
            }
          }
          if (activeModelIdCandidate == null && path.contains(model.fileName)) {
            activeModelIdCandidate = model.id;
          }
        } catch (e) {
          _errorHandler.logWarning("Error mapping path to ID: $e");
        }
      }
    }

    if (activeModelIdCandidate != null && !downloadedIds.contains(activeModelIdCandidate)) {
      activeModelIdCandidate = null;
      await prefs.remove('active_model_id');
    }

    final totalStorage = await modelManager.getTotalStorageUsed();

    state = state.copyWith(
      downloadedModelIds: downloadedIds,
      activeModelId: null,
      downloadProgress: downloadProgress,
      downloadErrors: downloadErrors, 
      totalStorageUsed: totalStorage,
    );

    if (activeModelIdCandidate != null) {
      try {
        final modelPath = await modelManager.getModelPath(activeModelIdCandidate);
        final llmService = _ref.read(llmServiceProvider);
        await llmService.loadModel(modelPath);
        state = state.copyWith(activeModelId: activeModelIdCandidate);
      } on ModelException catch (e) {
        _errorHandler.handleError(e);
        final newErrors = Map<String, String?>.from(state.downloadErrors);
        newErrors[activeModelIdCandidate] = e.userMessage;
        state = state.copyWith(downloadErrors: newErrors);
      } catch (e) {
        _errorHandler.logWarning('Failed to load active model: $e');
        final newErrors = Map<String, String?>.from(state.downloadErrors);
        newErrors[activeModelIdCandidate] = "Failed to load model";
        state = state.copyWith(downloadErrors: newErrors);
      }
    }
  }

  Future<void> downloadModel(String modelId) async {
    // Public, user-initiated download. Reset attempt tracking and any prior
    // progress so a fresh download starts from a clean slate. Works for both
    // `gguf` and `litert` models — the pipeline is engine-agnostic.
    _downloadRetryCount[modelId] = 1; // attempt 1 of 3

    final resetProgress = Map<String, double>.from(state.downloadProgress);
    resetProgress.remove(modelId);
    state = state.copyWith(downloadProgress: resetProgress);

    await _attemptDownload(modelId);
  }

  /// Dispatch a single download attempt without altering the attempt counter.
  ///
  /// Stores the file under the catalog file name (Req 7.1) and validates disk
  /// space first so an insufficient-storage error blocks the download before
  /// it starts (Req 7.8).
  Future<void> _attemptDownload(String modelId) async {
    final model = modelCatalog.firstWhere((m) => m.id == modelId);
    final modelManager = _ref.read(modelManagerProvider);
    final runAnywhere = _ref.read(runAnywhereProvider);

    // Clear previous errors
    final newErrors = Map<String, String?>.from(state.downloadErrors);
    newErrors.remove(modelId);
    state = state.copyWith(downloadErrors: newErrors);

    try {
      // 1. Validate disk space before starting download (Req 7.8)
      await modelManager.validateDiskSpace(modelId);

      // 2. Start download — destination path is derived from the catalog file
      //    name via getModelPath (Req 7.1).
      final modelPath = await modelManager.getModelPath(modelId);
      final taskId = await runAnywhere.downloadModel(model.url, modelPath);

      if (taskId != null) {
        _taskIdToModelId[taskId] = modelId;

        // Seed progress without dropping any already-reported value so the
        // reported progress stays monotonic across retries (Req 7.2).
        final newProgress = Map<String, double>.from(state.downloadProgress);
        newProgress[modelId] = newProgress[modelId] ?? 0.0;
        state = state.copyWith(downloadProgress: newProgress);

        _errorHandler.logInfo(
          'Started download for ${model.name} '
          '(attempt ${_downloadRetryCount[modelId] ?? 1}/3)',
        );
      }
    } on ModelException catch (e) {
      // Handle specific model exceptions with user-friendly messages
      // (e.g. insufficient storage). These are terminal — no retry.
      _handleDownloadError(modelId, e.userMessage);
      _errorHandler.handleError(e);
    } catch (e) {
      // Handle generic errors
      _handleDownloadError(modelId, 'Download failed: ${e.toString()}');
      _errorHandler.logWarning('Download error for $modelId: $e');
    }
  }

  void _handleDownloadError(String modelId, String errorMessage) {
    final newProgress = Map<String, double>.from(state.downloadProgress);
    newProgress.remove(modelId);

    final newErrors = Map<String, String?>.from(state.downloadErrors);
    newErrors[modelId] = errorMessage;

    state = state.copyWith(
      downloadProgress: newProgress,
      downloadErrors: newErrors,
    );
  }

  /// Remove the partial file and surface a download-failure error after all
  /// 3 attempts have been exhausted (Req 7.5).
  Future<void> _failDownloadAfterExhaustion(String modelId) async {
    final modelManager = _ref.read(modelManagerProvider);

    // Remove any partially downloaded file.
    await modelManager.removePartialDownload(modelId);

    final newProgress = Map<String, double>.from(state.downloadProgress);
    newProgress.remove(modelId);

    final newErrors = Map<String, String?>.from(state.downloadErrors);
    newErrors[modelId] =
        'Download failed after 3 attempts. Please check your connection.';

    state = state.copyWith(
      downloadProgress: newProgress,
      downloadErrors: newErrors,
    );

    _downloadRetryCount.remove(modelId);

    // Reduce reported storage in case a partial file was removed.
    await _updateStorageUsed();
  }

  /// Retry a failed download. Increments the attempt counter and re-dispatches,
  /// up to 3 total attempts (Req 7.4); cleans up after the third (Req 7.5).
  Future<void> retryDownload(String modelId) async {
    final attempts = _downloadRetryCount[modelId] ?? 1;

    if (decideDownloadFailure(attempts) == DownloadFailureDecision.exhausted) {
      await _failDownloadAfterExhaustion(modelId);
      return;
    }

    _downloadRetryCount[modelId] = attempts + 1;
    _errorHandler.logInfo(
      'Retrying download for $modelId (attempt ${attempts + 1}/3)',
    );

    // Wait before retrying (exponential backoff)
    await Future.delayed(_errorHandler.getRetryDelay(attempts - 1));

    await _attemptDownload(modelId);
  }

  Future<void> deleteModel(String modelId) async {
    final modelManager = _ref.read(modelManagerProvider);
    try {
      await modelManager.deleteModel(modelId);
      final newDownloaded = Set<String>.from(state.downloadedModelIds);
      newDownloaded.remove(modelId);
      final totalStorage = await modelManager.getTotalStorageUsed();
      String? newActiveModelId = state.activeModelId;
      if (state.activeModelId == modelId) {
        newActiveModelId = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_model_id');
      }
      state = state.copyWith(
        downloadedModelIds: newDownloaded,
        activeModelId: newActiveModelId,
        totalStorageUsed: totalStorage,
      );
    } on ModelException catch (e) {
      _errorHandler.handleError(e);
    } catch (e) {
      _errorHandler.logWarning('Error deleting model: $e');
    }
  }

  Future<void> selectModel(String modelId) async {
    if (!state.isDownloaded(modelId)) return;

    // Clear any stale error for this model and clear the active model to
    // trigger the "Loading..." state in the UI. A fresh select attempt should
    // never show an error left over from a previous attempt.
    final clearedErrors = Map<String, String?>.from(state.downloadErrors);
    clearedErrors.remove(modelId);
    state = state.copyWith(activeModelId: null, downloadErrors: clearedErrors);

    SharedPreferences? prefs;
    try {
      final modelManager = _ref.read(modelManagerProvider);
      final llmService = _ref.read(llmServiceProvider);

      // Reconcile: make sure the file is actually present and valid before
      // attempting a load. If it isn't, fix the downloaded state instead of
      // surfacing a confusing "loaded but not found" situation.
      final stillDownloaded = await modelManager.isModelDownloaded(modelId);
      if (!stillDownloaded) {
        final newDownloaded = Set<String>.from(state.downloadedModelIds)
          ..remove(modelId);
        final newErrors = Map<String, String?>.from(state.downloadErrors);
        newErrors[modelId] = 'Model file is missing. Please download again.';
        state = state.copyWith(
          downloadedModelIds: newDownloaded,
          downloadErrors: newErrors,
        );
        await _updateStorageUsed();
        return;
      }

      final modelPath = await modelManager.getModelPath(modelId);
      
      // Set sentinel before loading
      prefs = await SharedPreferences.getInstance();
      await prefs.setBool('model_load_crashed_sentinel', true);

      await llmService.loadModel(modelPath);

      // Clear sentinel on success
      await prefs.setBool('model_load_crashed_sentinel', false);

      await prefs.setString('active_model_id', modelId);
      await prefs.setString('selected_model_path', modelPath);
      state = state.copyWith(activeModelId: modelId);

      _errorHandler.logInfo('Successfully loaded model: ${modelManager.getModelById(modelId)?.name}');
    } on ModelException catch (e) {
      if (prefs != null) {
        await prefs.setBool('model_load_crashed_sentinel', false);
      }
      _errorHandler.handleError(e);
      // Show error in UI
      final newErrors = Map<String, String?>.from(state.downloadErrors);
      newErrors[modelId] = e.userMessage;
      state = state.copyWith(downloadErrors: newErrors);
    } catch (e) {
      if (prefs != null) {
        await prefs.setBool('model_load_crashed_sentinel', false);
      }
      _errorHandler.logWarning('Error selecting model: $e');
      final newErrors = Map<String, String?>.from(state.downloadErrors);
      newErrors[modelId] = 'Failed to load model';
      state = state.copyWith(downloadErrors: newErrors);
    }
  }

  Future<void> refreshModels() async {
    await _loadState();
  }
}


// Provider
final modelSelectorProvider =
    StateNotifierProvider<ModelSelectorNotifier, ModelSelectorState>((ref) {
  return ModelSelectorNotifier(ref);
});
