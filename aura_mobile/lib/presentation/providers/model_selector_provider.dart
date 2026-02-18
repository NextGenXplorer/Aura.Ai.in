import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/data/datasources/model_manager.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Model Manager Provider
final modelManagerProvider = Provider((ref) => ModelManager());

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

  StreamSubscription? _downloadSubscription;
  final Map<String, String> _taskIdToModelId = {};

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
        final progress = update.progress / 100;
        final newProgress = Map<String, double>.from(state.downloadProgress);
        newProgress[modelId] = progress;
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
        final newProgress = Map<String, double>.from(state.downloadProgress);
        newProgress.remove(modelId);

        final newErrors = Map<String, String?>.from(state.downloadErrors);
        newErrors[modelId] = "Download failed";

        state = state.copyWith(
          downloadProgress: newProgress,
          downloadErrors: newErrors,
        );
        _taskIdToModelId.remove(update.id);
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
          print("Error mapping path to ID: $e");
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
      } catch (e) {
        print('Initialization Error: Failed to load active model: $e');
        final newErrors = Map<String, String?>.from(state.downloadErrors);
        newErrors[activeModelIdCandidate] = "Failed to load: $e";
        state = state.copyWith(downloadErrors: newErrors);
      }
    }
  }

  Future<void> downloadModel(String modelId) async {
    final model = modelCatalog.firstWhere((m) => m.id == modelId);
    final modelManager = _ref.read(modelManagerProvider);
    final runAnywhere = _ref.read(runAnywhereProvider);

    final newErrors = Map<String, String?>.from(state.downloadErrors);
    newErrors.remove(modelId);
    state = state.copyWith(downloadErrors: newErrors);

    try {
      final modelPath = await modelManager.getModelPath(modelId);
      final taskId = await runAnywhere.downloadModel(model.url, modelPath);
      if (taskId != null) {
        _taskIdToModelId[taskId] = modelId;
        final newProgress = Map<String, double>.from(state.downloadProgress);
        newProgress[modelId] = 0.0;
        state = state.copyWith(downloadProgress: newProgress);
      }
    } catch (e) {
      final newProgress = Map<String, double>.from(state.downloadProgress);
      newProgress.remove(modelId);
      final newErrors = Map<String, String?>.from(state.downloadErrors);
      newErrors[modelId] = e.toString();
      state = state.copyWith(downloadProgress: newProgress, downloadErrors: newErrors);
    }
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
      state = state.copyWith(downloadedModelIds: newDownloaded, activeModelId: newActiveModelId, totalStorageUsed: totalStorage);
    } catch (e) {
      print('Error deleting model: $e');
    }
  }

  Future<void> selectModel(String modelId) async {
    if (!state.isDownloaded(modelId)) return;
    
    // Clear active model to trigger "Loading..." state in UI
    state = state.copyWith(activeModelId: null);

    try {
      final modelManager = _ref.read(modelManagerProvider);
      final llmService = _ref.read(llmServiceProvider);
      final modelPath = await modelManager.getModelPath(modelId);
      await llmService.loadModel(modelPath);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_model_id', modelId);
      await prefs.setString('selected_model_path', modelPath);
      state = state.copyWith(activeModelId: modelId);
    } catch (e) {
      print('Error selecting model: $e');
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
