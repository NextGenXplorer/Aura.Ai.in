import 'dart:io';
import 'dart:typed_data';

import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/ai_engine.dart';
import '../../domain/entities/model_info.dart';
import 'litert_service.dart';
import 'llm_service.dart';

/// The Engine_Router: a single [LLMService] that sits behind the unchanged
/// interface the `OrchestratorService` and chat flow already consume, and
/// delegates every call to whichever concrete engine owns the currently
/// active model.
///
/// Because the router *is* an [LLMService], downstream code keeps calling
/// `initialize`, `loadModel`, `chat`, `isModelLoaded`, and `modelTier` exactly
/// as before — it never learns a second engine exists (Requirement 1.2).
///
/// The router holds at most one **active model**: the [ModelInfo] set by the
/// most recent *successful* load. Every member other than `loadModel` is
/// delegated to the engine of the active model; while a `gguf` model is active
/// every call goes to the GGUF engine, and while a `litert` model is active
/// every call goes to the LiteRT engine (Requirements 1.6, 1.7).
///
/// This file implements the router. The skeleton wires the two engines, the
/// [DeviceService], the active-model state, [initialize] (GGUF eager, LiteRT
/// lazy), the [_active] engine resolver, [isModelLoaded], [modelTier], and
/// [supportsToolCalling]. The RAM-gated load ([loadModelInfo] / [loadModel])
/// delegates to the correct engine with commit-on-success semantics.
/// [chat] delegates to the active engine, with LiteRT errors contained so
/// they surface a chat-failure without crashing or clearing the active model.
class EngineRouter implements LLMService {
  /// The existing GGUF engine (RunAnywhere / fllama), the `gguf` branch.
  final LLMService _ggufEngine;

  /// The LiteRT engine (flutter_gemma), the `litert` branch.
  final LiteRtService _litertEngine;

  /// Probes total/available device RAM for the pre-flight RAM gate (Req 8).
  final DeviceService _deviceService;

  /// The currently active model — the [ModelInfo] committed by the most recent
  /// successful load, or `null` when no model is active.
  ModelInfo? _activeModel;

  EngineRouter({
    required LLMService ggufEngine,
    required LiteRtService litertEngine,
    required DeviceService deviceService,
  })  : _ggufEngine = ggufEngine,
        _litertEngine = litertEngine,
        _deviceService = deviceService;

  /// Resolves the engine that owns the active model, or `null` when no model is
  /// active. `gguf` models route to the GGUF engine; `litert` models route to
  /// the LiteRT engine (Requirements 1.6, 1.7).
  LLMService? get _active {
    final model = _activeModel;
    if (model == null) return null;
    return model.engine == AIEngine.gguf ? _ggufEngine : _litertEngine;
  }

  /// The active model, or `null` when none is loaded. Exposed for the router's
  /// load/chat logic and for tests.
  ModelInfo? get activeModel => _activeModel;

  @override
  Future<void> initialize() async {
    // GGUF is the existing default engine and is cheap/safe to bring up, so it
    // is initialized eagerly. LiteRT is initialized lazily on the first
    // successful `litert` load so app startup never incurs the LiteRT engine's
    // cost and so a LiteRT initialization failure can never break startup or
    // the GGUF path (Requirements 10.3, 10.6).
    await _ggufEngine.initialize();
  }

  @override
  Future<void> loadModel(String modelPath) async {
    // Resolve the ModelInfo from the catalog by matching the file name in the
    // path. This is the restart-recovery path: the Model_Selector stores only
    // the file path and resolves back to the catalog entry on restart.
    final model = modelCatalog.cast<ModelInfo?>().firstWhere(
      (m) => modelPath.contains(m!.fileName),
      orElse: () => null,
    );
    if (model == null) {
      throw ModelException.loadFailed(
        modelPath,
        'No catalog entry matches the file path',
      );
    }
    // The caller already supplied the absolute path — use it directly so the
    // engine receives a real file location, not a bare file name.
    await _loadResolved(model, modelPath);
  }

  /// Loads [model] through the engine indicated by its `engine` field, gated by
  /// a pre-flight RAM check, committing it as the active model only on success.
  ///
  /// Resolves the model's absolute file path from the application documents
  /// directory (matching `ModelManager.getModelPath`) before delegating, so the
  /// engine always receives a real file location.
  Future<void> loadModelInfo(ModelInfo model) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final modelPath =
        '${docsDir.path}${Platform.pathSeparator}${model.fileName}';
    await _loadResolved(model, modelPath);
  }

  /// Shared load implementation: runs the RAM gate, selects the engine by the
  /// model's `engine` field, delegates the load using the absolute
  /// [modelPath], and commits the active model only on success.
  ///
  /// The RAM gate runs before any engine work:
  /// - If device RAM cannot be determined (totalRamMB == 0), a
  ///   device-compatibility error is thrown (Req 8.6).
  /// - If the model's [minRamMB] exceeds device RAM, a memory-insufficiency
  ///   error stating required vs available is thrown (Req 8.2).
  /// - Otherwise the load proceeds.
  ///
  /// After the RAM gate passes, the engine is selected by [model.engine], the
  /// load is delegated, and the active model is committed only after the engine
  /// reports [isModelLoaded == true] (Req 1.4). On any failure the previous
  /// active model is retained (Req 1.5, 8.5, 10.2, 10.6).
  Future<void> _loadResolved(ModelInfo model, String modelPath) async {
    // --- Pre-flight RAM gate (Req 8.1, 8.2, 8.6) ---
    final device = await _deviceService.analyzeDevice();

    if (device.totalRamMB <= 0) {
      throw AIServiceException(
        message: 'Cannot verify device memory',
        technicalDetails:
            'Device RAM could not be determined (reported ${device.totalRamMB} MB). '
            'Model "${model.name}" requires ${model.minRamMB} MB.',
        recoverySuggestion:
            'Restart the app or check device compatibility.',
        errorCode: 'AI_DEVICE_COMPATIBILITY',
      );
    }

    if (model.minRamMB > device.totalRamMB) {
      throw AIServiceException(
        message:
            'Not enough memory to load ${model.name}',
        technicalDetails:
            'Model requires ${model.minRamMB} MB RAM but device has '
            '${device.totalRamMB} MB.',
        recoverySuggestion:
            'Try a smaller model. Your device has ${device.totalRamMB} MB RAM.',
        errorCode: 'AI_MEMORY_INSUFFICIENCY',
      );
    }

    // --- Select engine and delegate the load (Req 1.4, 8.4) ---
    final LLMService engine;
    if (model.engine == AIEngine.gguf) {
      engine = _ggufEngine;
    } else {
      // Lazily initialize LiteRT on first litert load (Req 10.3, 10.6).
      if (!_litertEngine.isInitialized) {
        await _litertEngine.initialize();
      }
      // Supply the model tier and vision capability from catalog metadata
      // before loading (Req 8.4); the LiteRT model must be created with image
      // support up front, so this is set before the load.
      _litertEngine.modelTier = _modelTierForLiteRT(model);
      _litertEngine.supportsVision = model.supportsVision;
      engine = _litertEngine;
    }

    // CRITICAL FIX: When switching engines (GGUF ↔ LiteRT), unload the OTHER
    // engine first so its native memory is released. Without this, both engines
    // hold their model contexts in RAM after a switch, leading to OOM-kills.
    final previousModel = _activeModel;
    final previousEngine = previousModel?.engine;
    final newEngine = model.engine;
    if (previousModel != null && previousEngine != newEngine) {
      if (previousEngine == AIEngine.gguf) {
        // Switching FROM GGUF → unload the GGUF context.
        if (_ggufEngine is LLMServiceImpl) {
          try {
            await (_ggufEngine).unload();
          } catch (_) {/* best-effort */}
        }
      } else {
        // Switching FROM LiteRT → unload the LiteRT model.
        try {
          await _litertEngine.unload();
        } catch (_) {/* best-effort */}
      }
    }

    try {
      // Pass the ABSOLUTE path so the engine can locate the downloaded file.
      await engine.loadModel(modelPath);
    } catch (e) {
      // Load failed — retain the previous active model (Req 1.5, 10.2).
      // Re-throw with context if it's not already a well-typed exception.
      if (e is AuraException) rethrow;
      throw ModelException.loadFailed(model.name, e);
    }

    // --- Commit only on success (Req 1.4) ---
    if (!engine.isModelLoaded) {
      throw ModelException.loadFailed(
        model.name,
        'Engine reported model not loaded after load completed',
      );
    }

    _activeModel = model;
  }

  /// Derives the [ModelTier] for a LiteRT model from its catalog metadata.
  ///
  /// LiteRT file names do not reliably encode model size, so tier is sourced
  /// from catalog fields (Req 8.4). Mapping:
  /// - 1B models (Gemma3 1B) → small
  /// - E2B models (Gemma3n/4 E2B ~2B) → large (capable model, needs full prompt)
  /// - E4B+ models (Gemma4 E4B ~4B) → large
  /// Note: LiteRT Gemma models are NOT Qwen 1.5B — they need the full prompt
  /// quality even if labeled "medium" by parameter count.
  static ModelTier _modelTierForLiteRT(ModelInfo model) {
    final id = model.id.toLowerCase();
    if (id.contains('1b') && !id.contains('e2b') && !id.contains('e4b')) {
      return ModelTier.small; // Gemma3 1B only
    }
    // E2B (~2B), E4B (~4B), and anything else → large for full prompt quality
    return ModelTier.large;
  }

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
    Uint8List? imageBytes,
  }) {
    // Req 1.9: No model is active — throw immediately without changing state.
    final engine = _active;
    if (engine == null) {
      throw AIServiceException.modelNotLoaded();
    }

    // Req 1.6, 2.2: GGUF models delegate directly — always available (Req 10.3).
    // The GGUF engine is text-only, so imageBytes is passed but ignored there.
    if (_activeModel!.engine == AIEngine.gguf) {
      return engine.chat(
        prompt,
        systemPrompt: systemPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
        imageBytes: imageBytes,
      );
    }

    // Req 1.7, 10.4, 10.5: LiteRT delegation with error containment.
    // Wrap in an async* generator so any exception (sync or async) from the
    // LiteRT engine is caught and surfaced as a chat-failure error without
    // crashing or clearing the active model.
    return _litertChatGuarded(
      prompt,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      temperature: temperature,
      imageBytes: imageBytes,
    );
  }

  /// Wraps the LiteRT engine's [chat] stream so that any error is caught and
  /// re-thrown as a well-typed [AIServiceException] indicating a chat failure.
  /// The active model remains loaded and available for subsequent calls
  /// (Req 10.4, 10.5).
  Stream<String> _litertChatGuarded(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
    Uint8List? imageBytes,
  }) async* {
    try {
      yield* _litertEngine.chat(
        prompt,
        systemPrompt: systemPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
        imageBytes: imageBytes,
      );
    } catch (e) {
      // Re-throw as a handled chat-failure error. The active model stays loaded
      // because we never clear _activeModel here.
      throw AIServiceException(
        message: 'Chat failed',
        technicalDetails: 'LiteRT engine error during chat: $e',
        recoverySuggestion: 'Try sending the message again or switch to a different model.',
        errorCode: 'AI_CHAT_FAILURE',
      );
    }
  }

  @override
  bool get isModelLoaded => _active?.isModelLoaded ?? false;

  @override
  ModelTier get modelTier => _active?.modelTier ?? ModelTier.large;

  /// Reflects the active model's native function/tool-calling capability so the
  /// orchestrator selects the function-calling path only for capable models and
  /// otherwise keeps rule-based intent detection (Requirements 2.5, 5.4). When
  /// no model is active this is `false`.
  @override
  bool get supportsToolCalling => _activeModel?.supportsToolCalling ?? false;

  /// Reflects the active model's vision (image input) capability so the UI can
  /// offer "ask about this image" only when a multimodal model is loaded.
  @override
  bool get supportsVision => _activeModel?.supportsVision ?? false;
}
