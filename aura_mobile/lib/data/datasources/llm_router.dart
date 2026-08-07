import 'dart:async';
import 'dart:typed_data';

import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/core/services/llm_selection_store.dart';
import 'package:aura_mobile/core/services/provider_api_key_store.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/domain/entities/online_model.dart';

import 'litert_service.dart';
import 'llm_service.dart';
import 'openai_compatible_llm_service.dart';

enum LLMBackend { offline, online }

/// Routes Aura's existing LLM workflow to either LiteRT or an explicitly
/// selected online provider. Online fallback is never automatic.
class LLMRouter implements LLMService, CancellableLLMService {
  final LiteRtService offlineService;
  final OpenAICompatibleLLMService onlineService;
  final ProviderApiKeyStore keyStore;
  final LLMSelectionStore selectionStore;

  LLMBackend _activeBackend = LLMBackend.offline;
  String? _activeModelId;
  String? _activeModelName;
  Future<void>? _restoreInFlight;

  LLMRouter({
    required this.offlineService,
    required this.onlineService,
    required this.keyStore,
    required this.selectionStore,
  });

  LLMBackend get activeBackend => _activeBackend;
  bool get isOnline => _activeBackend == LLMBackend.online;
  String? get activeModelId => _activeModelId;
  String? get activeModelName => _activeModelName;
  OnlineProvider? get activeOnlineProvider => onlineService.activeProvider;
  OnlineModel? get activeOnlineModel => onlineService.activeModel;

  @override
  Future<void> initialize() => offlineService.initialize();

  Future<void> restoreActiveSelection() {
    return _restoreInFlight ??= _restoreActiveSelection().whenComplete(() {
      _restoreInFlight = null;
    });
  }

  Future<void> _restoreActiveSelection() async {
    final snapshot = await selectionStore.read();
    if (snapshot.activeBackend == LLMBackend.online.name) {
      final savedOnline = snapshot.online;
      if (savedOnline != null) {
        final apiKey = await keyStore.read(savedOnline.provider);
        if (apiKey != null) {
          final model = savedOnline.toModel();
          onlineService.configure(
            provider: savedOnline.provider,
            model: model,
            apiKey: apiKey,
          );
          _activeBackend = LLMBackend.online;
          _activeModelId = model.selectionId;
          _activeModelName = model.name;
          return;
        }
      }

      await _restoreLocalOrClear(snapshot.copyWith(clearOnline: true));
      return;
    }

    if (snapshot.activeBackend == LLMBackend.offline.name &&
        snapshot.local != null) {
      try {
        await _activateSavedLocal(snapshot.local!);
      } catch (_) {
        await selectionStore.write(snapshot.copyWith(clearActiveBackend: true));
        _clearRuntimeSelection();
        rethrow;
      }
      return;
    }

    _clearRuntimeSelection();
  }

  Future<void> _restoreLocalOrClear(LLMSelectionSnapshot snapshot) async {
    onlineService.clearConfiguration();
    final local = snapshot.local;
    if (local == null) {
      await selectionStore.write(
        snapshot.copyWith(clearActiveBackend: true, clearOnline: true),
      );
      _clearRuntimeSelection();
      return;
    }
    try {
      await _activateSavedLocal(local);
      await selectionStore.write(
        snapshot.copyWith(
          activeBackend: LLMBackend.offline.name,
          clearOnline: true,
        ),
      );
    } catch (_) {
      await selectionStore.write(
        snapshot.copyWith(clearActiveBackend: true, clearOnline: true),
      );
      _clearRuntimeSelection();
    }
  }

  Future<void> _activateSavedLocal(LocalModelSelection local) async {
    await offlineService.loadModel(local.path);
    onlineService.clearConfiguration();
    _activeBackend = LLMBackend.offline;
    _activeModelId = local.id;
    _activeModelName = local.name;
  }

  void _clearRuntimeSelection() {
    onlineService.clearConfiguration();
    _activeBackend = LLMBackend.offline;
    _activeModelId = null;
    _activeModelName = null;
  }

  bool get _anyGenerationActive =>
      offlineService.isGenerating || onlineService.isGenerating;

  Future<void> _applySnapshotRuntime(LLMSelectionSnapshot snapshot) async {
    if (snapshot.activeBackend == LLMBackend.online.name &&
        snapshot.online != null) {
      final key = await keyStore.read(snapshot.online!.provider);
      if (key != null) {
        final online = snapshot.online!.toModel();
        onlineService.configure(
          provider: online.provider,
          model: online,
          apiKey: key,
        );
        _activeBackend = LLMBackend.online;
        _activeModelId = online.selectionId;
        _activeModelName = online.name;
        return;
      }
    }
    if (snapshot.activeBackend == LLMBackend.offline.name &&
        snapshot.local != null) {
      await _activateSavedLocal(snapshot.local!);
      return;
    }
    await offlineService.unload();
    _clearRuntimeSelection();
  }

  Future<void> _rollbackSelection(LLMSelectionSnapshot previous) async {
    try {
      await selectionStore.write(previous);
    } catch (_) {
      // The original persistence failure remains the actionable error.
    }
    try {
      await _applySnapshotRuntime(previous);
    } catch (_) {
      _clearRuntimeSelection();
    }
  }

  Future<List<OnlineModel>> listModels(OnlineProvider provider) async {
    final apiKey = await keyStore.read(provider);
    if (apiKey == null) {
      throw StateError('Add a ${provider.displayName} API key first.');
    }
    return onlineService.listModels(provider: provider, apiKey: apiKey);
  }

  Future<List<OnlineModel>> validateAndSaveApiKey(
    OnlineProvider provider,
    String candidateKey,
  ) async {
    final key = candidateKey.trim();
    if (key.isEmpty) {
      throw StateError('Enter a ${provider.displayName} API key.');
    }
    final models = await onlineService.listModels(
      provider: provider,
      apiKey: key,
    );
    if (isOnline &&
        activeOnlineProvider == provider &&
        onlineService.isGenerating) {
      throw StateError('Wait for the current response to finish.');
    }
    await keyStore.write(provider, key);
    if (isOnline && activeOnlineProvider == provider) {
      final activeModel = onlineService.activeModel;
      if (activeModel != null) {
        onlineService.configure(
          provider: provider,
          model: activeModel,
          apiKey: key,
        );
      }
    }
    return models;
  }

  Future<bool> hasApiKey(OnlineProvider provider) => keyStore.hasKey(provider);

  Future<void> deleteApiKey(OnlineProvider provider) async {
    if (_anyGenerationActive) {
      throw StateError('Wait for the current response to finish.');
    }
    await keyStore.delete(provider);
    final snapshot = await selectionStore.read();
    final deletingActiveProvider =
        snapshot.activeBackend == LLMBackend.online.name &&
        snapshot.online?.provider == provider;
    final updated = snapshot.copyWith(
      clearOnline: snapshot.online?.provider == provider,
      activeBackend: deletingActiveProvider && snapshot.local != null
          ? LLMBackend.offline.name
          : null,
      clearActiveBackend: deletingActiveProvider && snapshot.local == null,
    );
    if (deletingActiveProvider) {
      await _restoreLocalOrClear(updated);
    } else {
      await selectionStore.write(updated);
    }
  }

  Future<void> selectOnlineModel(OnlineModel requestedModel) async {
    if (_anyGenerationActive) {
      throw StateError('Wait for the current response to finish.');
    }
    final apiKey = await keyStore.read(requestedModel.provider);
    if (apiKey == null) {
      throw StateError(
        'Add a ${requestedModel.provider.displayName} API key first.',
      );
    }
    final model = await onlineService.validateConfiguration(
      provider: requestedModel.provider,
      model: requestedModel,
      apiKey: apiKey,
    );
    final previous = await selectionStore.read();
    onlineService.configure(
      provider: model.provider,
      model: model,
      apiKey: apiKey,
    );
    try {
      await selectionStore.write(
        previous.copyWith(
          activeBackend: LLMBackend.online.name,
          online: OnlineModelSelection.fromModel(model),
        ),
      );
    } catch (_) {
      await _rollbackSelection(previous);
      rethrow;
    }
    _activeBackend = LLMBackend.online;
    _activeModelId = model.selectionId;
    _activeModelName = model.name;
  }

  Future<void> selectLocalModel({
    required ModelInfo model,
    required String path,
    required DeviceService deviceService,
  }) async {
    if (_anyGenerationActive) {
      throw StateError('Wait for the current response to finish.');
    }
    final previous = await selectionStore.read();
    final local = LocalModelSelection(
      id: model.id,
      name: model.name,
      path: path,
    );
    try {
      await offlineService.loadModelSafe(model, deviceService);
      await selectionStore.write(
        previous.copyWith(activeBackend: LLMBackend.offline.name, local: local),
      );
    } catch (_) {
      await _rollbackSelection(previous);
      rethrow;
    }
    onlineService.clearConfiguration();
    _activeBackend = LLMBackend.offline;
    _activeModelId = model.id;
    _activeModelName = model.name;
  }

  Future<LLMSelectionSnapshot?> removeLocalSelection([String? modelId]) async {
    if (offlineService.isGenerating) {
      throw StateError('Wait for the local response to finish.');
    }
    final snapshot = await selectionStore.read();
    if (snapshot.local == null ||
        (modelId != null && snapshot.local!.id != modelId)) {
      return null;
    }
    final wasActive = snapshot.activeBackend == LLMBackend.offline.name;
    try {
      if (offlineService.isModelLoaded) await offlineService.unload();
      await selectionStore.write(
        snapshot.copyWith(clearLocal: true, clearActiveBackend: wasActive),
      );
    } catch (_) {
      await _rollbackSelection(snapshot);
      rethrow;
    }
    if (wasActive) _clearRuntimeSelection();
    return snapshot;
  }

  /// Waits until the active engine is free so a queued request (for example a
  /// voice question arriving while chat is streaming) does not fail outright.
  Future<bool> waitUntilIdle({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_anyGenerationActive) {
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return true;
  }

  /// Last online model the user selected, if any. Reading it requires no
  /// network call so the UI can offer a fast switch back to online.
  Future<OnlineModelSelection?> savedOnlineSelection() async =>
      (await selectionStore.read()).online;

  /// Last local model the user selected, if any.
  Future<LocalModelSelection?> savedLocalSelection() async =>
      (await selectionStore.read()).local;

  /// Re-activates the stored online selection without re-validating the
  /// catalog. Used for quick offline/online switching in chat.
  Future<void> activateSavedOnlineSelection() async {
    final snapshot = await selectionStore.read();
    final online = snapshot.online;
    if (online == null) {
      throw StateError('Choose an online model in Online AI Providers first.');
    }
    if (await keyStore.read(online.provider) == null) {
      throw StateError('Add a ${online.provider.displayName} API key first.');
    }
    await restoreSelectionSnapshot(
      snapshot.copyWith(activeBackend: LLMBackend.online.name),
    );
  }

  Future<void> restoreSelectionSnapshot(LLMSelectionSnapshot snapshot) async {
    if (_anyGenerationActive) {
      throw StateError('Wait for the current response to finish.');
    }
    await selectionStore.write(snapshot);
    await _applySnapshotRuntime(snapshot);
  }

  @override
  Future<void> loadModel(String modelPath) async {
    if (_anyGenerationActive) {
      throw StateError('Wait for the current response to finish.');
    }
    final snapshot = await selectionStore.read();
    final local = snapshot.local;
    if (local == null || local.path != modelPath) {
      throw StateError(
        'Local model identity is missing. Select the model in Model Manager.',
      );
    }
    try {
      await _activateSavedLocal(local);
      await selectionStore.write(
        snapshot.copyWith(activeBackend: LLMBackend.offline.name),
      );
    } catch (_) {
      await _rollbackSelection(snapshot);
      rethrow;
    }
  }

  LLMService get _activeService => isOnline ? onlineService : offlineService;

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
    Uint8List? imageBytes,
  }) {
    return _activeService.chat(
      prompt,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      temperature: temperature,
      imageBytes: imageBytes,
    );
  }

  @override
  Future<void> cancelGeneration() async {
    if (isOnline) {
      await onlineService.cancelGeneration();
    } else {
      await offlineService.cancelGeneration();
    }
  }

  @override
  bool get isModelLoaded => _activeService.isModelLoaded;

  @override
  bool get isGenerating => _activeService.isGenerating;

  @override
  ModelTier get modelTier => _activeService.modelTier;

  @override
  bool get supportsToolCalling => _activeService.supportsToolCalling;

  @override
  bool get supportsVision => _activeService.supportsVision;

  @override
  int get contextTokens => _activeService.contextTokens;
}
