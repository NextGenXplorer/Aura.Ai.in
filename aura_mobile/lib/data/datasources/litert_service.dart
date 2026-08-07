import 'dart:io';
import 'dart:typed_data';

import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/data/datasources/prompt_templates.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

import 'llm_service.dart';

/// The LiteRT inference engine.
///
/// Implements the existing [LLMService] interface by wrapping the
/// `flutter_gemma` package (LiteRT-LM / MediaPipe LLM Inference), serving as
/// the `litert` branch of the dual-engine architecture. It runs Google Gemma
/// models distributed in the `.task` / `.litertlm` formats.
///
/// This class implements the LiteRT engine incrementally. [loadModel] (model
/// installation, session creation, and the 30-second init timeout) and [chat]
/// (Gemma prompt formatting + streaming) are implemented here.
class LiteRtService implements LLMService, CancellableLLMService {
  /// Handle to the `flutter_gemma` plugin singleton. Injectable for testing;
  /// defaults to the platform instance.
  final FlutterGemmaPlugin _gemma;

  /// The currently loaded inference model, or `null` when no model is loaded.
  InferenceModel? _model;

  Future<void>? _loadInFlight;
  String? _loadedModelPath;
  bool _isGenerating = false;
  InferenceModelSession? _activeSession;
  RandomAccessFile? _runtimeLock;

  /// Whether the plugin handle has been prepared via [initialize].
  bool _initialized = false;

  /// The tier of the active LiteRT model.
  ///
  /// Unlike the GGUF engine, LiteRT file names do not reliably encode model
  /// size, so the tier is supplied from catalog metadata by the router via
  /// [modelTier]'s setter rather than derived from the file name.
  ModelTier _tier = ModelTier.medium;

  /// Whether the active LiteRT model should be loaded with vision (image
  /// input) enabled. Set by the router from catalog metadata before
  /// [loadModel], since the model must be created with image support up front.
  bool _supportsVision = false;

  /// Fallback context window for models that are not in the catalog.
  static const int _defaultContextTokens = 4096;

  /// Context window of the active model, taken from catalog metadata.
  int _contextTokens = _defaultContextTokens;

  /// The prompt template for the currently active model.
  PromptTemplate _promptTemplate = PromptTemplate.gemma;

  /// File extensions the LiteRT engine can load (Req 3.3 / 3.8). Both map to
  /// [ModelFileType.task]; MediaPipe applies the chat template internally.
  static const Set<String> _supportedExtensions = {'.task', '.litertlm'};

  /// Maximum time allowed for the inference engine to initialize a model
  /// before the load is abandoned (Req 10.1).
  static const Duration _initTimeout = Duration(seconds: 30);

  /// Whether this instance guards the native runtime with the cross-engine
  /// file lock. Only true for the production service, which drives the real
  /// platform plugin and therefore owns the multi-GB native model. When a
  /// plugin handle is injected the engine is a test double with no native
  /// resources to guard, so the lock (and its `path_provider` dependency) is
  /// skipped.
  final bool _guardsNativeRuntime;

  LiteRtService({FlutterGemmaPlugin? gemma})
    : _gemma = gemma ?? FlutterGemmaPlugin.instance,
      _guardsNativeRuntime = gemma == null;

  @override
  Future<void> initialize() async {
    // Initialize the flutter_gemma ServiceRegistry once. The modern API
    // (installModel / getActiveModel) requires this before any model work.
    // Heavy work (installing the model file and creating the inference
    // session) is deferred to [loadModel].
    if (!_initialized) {
      try {
        await FlutterGemma.initialize();
      } catch (_) {
        // initialize() is effectively idempotent; ignore re-init errors.
      }
      _initialized = true;
    }
  }

  @override
  Future<void> loadModel(String modelPath) async {
    if (_isGenerating) {
      throw StateError('Cannot replace the local model during generation.');
    }
    if (_model != null && _loadedModelPath == modelPath) return;

    final inFlight = _loadInFlight;
    if (inFlight != null) {
      await inFlight;
      if (_model != null && _loadedModelPath == modelPath) return;
      return loadModel(modelPath);
    }

    final operation = _loadModelInternal(modelPath);
    _loadInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_loadInFlight, operation)) _loadInFlight = null;
    }
  }

  Future<void> _loadModelInternal(String modelPath) async {
    final ext = _extensionOf(modelPath);

    // Req 3.8: An unsupported file format must NOT disturb a model that is
    // already loaded. Reject before touching any engine state so the
    // previously loaded model (if any) stays loaded and usable.
    if (!_supportedExtensions.contains(ext)) {
      throw ValidationException.unsupportedFormat(
        ext.isEmpty ? modelPath : ext,
      );
    }

    // AUTO-DETECT model metadata from the catalog by matching the file name.
    // This ensures vision support, tier, and prompt template are ALWAYS set
    // correctly no matter which code path loads the model (auto-load on app
    // start, model selector, onboarding, etc.) — not just loadModelSafe.
    _applyCatalogMetadata(modelPath);

    // Ensure the ServiceRegistry is initialized before installing.
    if (!_initialized) {
      await initialize();
    }

    // Ensure only one Flutter engine in the Aura process owns the multi-GB
    // native model. The UI engine and Brain headless engine share this lock.
    await _acquireRuntimeLock();

    // CRITICAL FIX: Dispose the previous model BEFORE loading a new one.
    // Without this, switching between LiteRT models leaks the previous
    // InferenceModel's native resources (~2-4GB RAM per leaked model).
    // After 2-3 switches the OS will OOM-kill the app.
    final previous = _model;
    if (previous != null) {
      _model = null;
      try {
        await previous.close();
      } catch (e) {
        // Closing may fail if already disposed; log but don't block the new load.
      }
    }

    try {
      // Req 3.2: all engine work is delegated to the `flutter_gemma` package
      // through the injected plugin handle. `setModelPath` registers the
      // already-downloaded file (building a spec from the local path and
      // setting it active), then `createModel` builds the inference model from
      // that active spec. The 30-second timeout bounds engine initialization
      // (Req 10.1); exceeding it fails the load like any other init error.
      // ignore: deprecated_member_use
      await _gemma.modelManager.setModelPath(modelPath).timeout(_initTimeout);

      _model = await _gemma
          .createModel(
            modelType: ModelType.gemmaIt,
            fileType: ModelFileType.task,
            maxTokens: _contextTokens,
            supportImage: _supportsVision,
            maxNumImages: _supportsVision ? 1 : null,
          )
          .timeout(_initTimeout);
      _loadedModelPath = modelPath;
    } catch (e) {
      // Req 3.7 / 3.9 / 10.1: on any initialization or load failure (including
      // the timeout), clear the model so isModelLoaded reports false and
      // surface a load-failure error.
      _model = null;
      _loadedModelPath = null;
      await _releaseRuntimeLock();
      throw AIServiceException.modelLoadFailed(modelPath, e);
    }
  }

  /// Looks up the model in the catalog by matching its file name, then applies
  /// the model's vision support, tier, and prompt template. This runs for EVERY
  /// load path so metadata is never missed.
  void _applyCatalogMetadata(String modelPath) {
    // Extract just the file name from the path
    final normalized = modelPath.replaceAll('\\', '/');
    final fileName = normalized.substring(normalized.lastIndexOf('/') + 1);

    // Find the matching catalog entry by file name
    ModelInfo? match;
    for (final model in modelCatalog) {
      if (model.fileName == fileName) {
        match = model;
        break;
      }
    }

    if (match != null) {
      _supportsVision = match.supportsVision;
      _promptTemplate = match.promptTemplate;
      _tier = _tierForModel(match);
      _contextTokens = match.contextTokens;
    } else {
      // Unknown model — default to safe values (no vision, gemma template)
      _supportsVision = false;
      _promptTemplate = PromptTemplate.gemma;
      _contextTokens = _defaultContextTokens;
    }
  }

  /// Unloads the currently loaded LiteRT model, freeing native resources.
  ///
  /// Idempotent — safe to call when no model is loaded.
  Future<void> unload() async {
    final previous = _model;
    _model = null;
    _loadedModelPath = null;
    if (previous != null) {
      try {
        await previous.close();
      } catch (_) {
        // Closing may fail if already disposed; ignore.
      }
    }
    await _releaseRuntimeLock();
  }

  Future<void> _acquireRuntimeLock() async {
    if (!_guardsNativeRuntime || _runtimeLock != null) return;
    final docsDir = await getApplicationDocumentsDirectory();
    final handle = await File(
      '${docsDir.path}${Platform.pathSeparator}.aura_model_runtime.lock',
    ).open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive).timeout(const Duration(seconds: 2));
      _runtimeLock = handle;
    } catch (_) {
      await handle.close();
      throw StateError('Another Aura runtime currently owns the local model.');
    }
  }

  Future<void> _releaseRuntimeLock() async {
    final handle = _runtimeLock;
    _runtimeLock = null;
    if (handle == null) return;
    try {
      await handle.unlock();
    } catch (_) {}
    await handle.close();
  }

  /// Returns the lower-cased file extension (including the leading dot) of
  /// [path], or an empty string when the file name has no extension. Handles
  /// both `/` and `\` path separators.
  String _extensionOf(String path) {
    final normalized = path.toLowerCase();
    final lastSlash = normalized.lastIndexOf('/') > normalized.lastIndexOf('\\')
        ? normalized.lastIndexOf('/')
        : normalized.lastIndexOf('\\');
    final fileName = lastSlash >= 0
        ? normalized.substring(lastSlash + 1)
        : normalized;
    final dot = fileName.lastIndexOf('.');
    return dot >= 0 ? fileName.substring(dot) : '';
  }

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
    Uint8List? imageBytes,
  }) async* {
    final model = _model;
    if (model == null) {
      throw AIServiceException.modelNotLoaded();
    }
    if (_isGenerating) {
      throw StateError('The local model is already generating.');
    }

    _isGenerating = true;
    try {
      final useImage = imageBytes != null && _supportsVision;
      final session = await model.createSession(
        temperature: temperature,
        enableVisionModality: useImage ? true : null,
      );
      _activeSession = session;
      try {
        final promptText = PromptTemplateFactory.format(
          _promptTemplate,
          prompt,
          systemPrompt: systemPrompt,
        );
        if (useImage) {
          await session.addQueryChunk(
            Message.withImage(
              text: promptText,
              imageBytes: imageBytes,
              isUser: true,
            ),
          );
        } else {
          await session.addQueryChunk(
            Message.text(text: promptText, isUser: true),
          );
        }
        yield* session.getResponseAsync();
      } finally {
        if (identical(_activeSession, session)) _activeSession = null;
        await session.close();
      }
    } finally {
      _isGenerating = false;
    }
  }

  @override
  Future<void> cancelGeneration() async {
    final session = _activeSession;
    if (session == null) return;
    try {
      await session.stopGeneration();
    } catch (_) {
      // The native stream may already have completed between the user action
      // and this call; session cleanup still runs in chat's finally block.
    }
  }

  /// Formats [prompt] (and an optional [systemPrompt]) using the Gemma
  /// `<start_of_turn>` chat template (Req 3.4).
  ///
  /// The result wraps the user content in a single
  /// `<start_of_turn>user … <end_of_turn>` turn and ends with a
  /// `<start_of_turn>model` opener so the engine continues as the model. When a
  /// non-empty [systemPrompt] is supplied it is embedded ahead of the prompt
  /// inside the same user turn (Gemma has no dedicated system role). The output
  /// never contains ChatML markers (`<|im_start|>` / `<|im_end|>`), which belong
  /// to the GGUF engine.
  ///
  /// Exposed as a pure static function so the template can be verified directly
  /// without standing up the native engine.
  static String formatGemmaPrompt(String prompt, {String? systemPrompt}) {
    final buffer = StringBuffer();
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer
        ..write('<start_of_turn>user\n')
        ..write(systemPrompt)
        ..write('\n\n')
        ..write(prompt)
        ..write('<end_of_turn>\n');
    } else {
      buffer
        ..write('<start_of_turn>user\n')
        ..write(prompt)
        ..write('<end_of_turn>\n');
    }
    buffer.write('<start_of_turn>model\n');
    return buffer.toString();
  }

  @override
  bool get isModelLoaded => _model != null;

  /// Canonical path of the currently loaded local model, if any.
  String? get loadedModelPath => _loadedModelPath;

  @override
  bool get isGenerating => _isGenerating;

  /// LiteRtService tracks tool-calling capability via catalog metadata set
  /// before loading. Matching the [LLMService] default keeps this engine on the
  /// rule-based intent path unless explicitly set (Req 2.5, 5.4).
  @override
  bool get supportsToolCalling => false;

  /// The tier of the currently loaded LiteRT model, sourced from catalog
  /// metadata (see the setter).
  @override
  ModelTier get modelTier => _tier;

  /// Sets the tier for the active LiteRT model from catalog metadata.
  set modelTier(ModelTier tier) => _tier = tier;

  /// Whether the active LiteRT model exposes vision (image) input.
  @override
  bool get supportsVision => _supportsVision;

  /// Context window of the active LiteRT build, from catalog metadata.
  @override
  int get contextTokens => _contextTokens;

  /// Sets whether the next loaded model should enable image input. Must be set
  /// by the router before [loadModel] because the model is created with image
  /// support up front.
  set supportsVision(bool value) => _supportsVision = value;

  /// Sets the prompt template for the active model. Must be set
  /// before [loadModel] or during [loadModelSafe].
  set promptTemplate(PromptTemplate template) => _promptTemplate = template;

  /// Whether the plugin handle has been prepared. Exposed for the router and
  /// tests.
  bool get isInitialized => _initialized;

  /// The underlying `flutter_gemma` plugin handle. Used by [loadModel] and
  /// [chat] in later tasks.
  FlutterGemmaPlugin get plugin => _gemma;

  /// Loads a model with pre-flight RAM gate and metadata setup.
  ///
  /// This replaces the EngineRouter's loadModelInfo. Runs the RAM gate,
  /// sets model tier and vision capability, then calls [loadModel] with the
  /// resolved file path.
  Future<void> loadModelSafe(
    ModelInfo model,
    DeviceService deviceService,
  ) async {
    final device = await deviceService.analyzeDevice();

    if (device.totalRamMB <= 0) {
      throw AIServiceException(
        message: 'Cannot verify device memory',
        technicalDetails:
            'Device RAM could not be determined (reported ${device.totalRamMB} MB). '
            'Model "${model.name}" requires ${model.minRamMB} MB.',
        recoverySuggestion: 'Restart the app or check device compatibility.',
        errorCode: 'AI_DEVICE_COMPATIBILITY',
      );
    }

    if (model.minRamMB > device.totalRamMB) {
      throw AIServiceException(
        message: 'Not enough memory to load ${model.name}',
        technicalDetails:
            'Model requires ${model.minRamMB} MB RAM but device has '
            '${device.totalRamMB} MB.',
        recoverySuggestion:
            'Try a smaller model. Your device has ${device.totalRamMB} MB RAM.',
        errorCode: 'AI_MEMORY_INSUFFICIENCY',
      );
    }

    // Set tier and vision before load
    modelTier = _tierForModel(model);
    promptTemplate = model.promptTemplate;
    supportsVision = model.supportsVision;

    final docsDir = await getApplicationDocumentsDirectory();
    final modelPath =
        '${docsDir.path}${Platform.pathSeparator}${model.fileName}';
    await loadModel(modelPath);
  }

  /// Derives the [ModelTier] for a model from its catalog metadata.
  ///
  /// Based on quantized download size (a reliable proxy for capability):
  /// - < 1.8GB  → small  (0.6B/1B/1.5B models — weak; redirect knowledge
  ///                       questions to web search, handle commands directly)
  /// - >= 1.8GB → large  (2B+ models — capable of answering questions)
  static ModelTier _tierForModel(ModelInfo model) {
    // Parameter count is a better capability signal than file size, because
    // quantization makes a 1.5B q8 build larger than a 3B int4 build.
    final id = model.id.toLowerCase();
    final isSubTwoBillion =
        RegExp(r'(135m|360m|0\.6b|1\.5b|1\.7b|(^|[^e])1b)').hasMatch(id) &&
        !id.contains('e2b') &&
        !id.contains('e4b');
    if (isSubTwoBillion) return ModelTier.small;

    // Size-based fallback for entries whose id carries no parameter hint.
    if (model.sizeBytes > 0 && model.sizeBytes < 1800000000) {
      return ModelTier.small;
    }
    return ModelTier.large;
  }
}
