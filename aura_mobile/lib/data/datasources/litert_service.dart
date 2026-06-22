import 'dart:typed_data';

import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

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
class LiteRtService implements LLMService {
  /// Handle to the `flutter_gemma` plugin singleton. Injectable for testing;
  /// defaults to the platform instance.
  final FlutterGemmaPlugin _gemma;

  /// The currently loaded inference model, or `null` when no model is loaded.
  InferenceModel? _model;

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

  /// File extensions the LiteRT engine can load. Both map to
  /// [ModelFileType.task]; MediaPipe applies the chat template internally.
  static const Set<String> _supportedExtensions = {'.task', '.litertlm'};

  /// Maximum time allowed for the inference engine to initialize a model
  /// before the load is abandoned (Req 10.1).
  static const Duration _initTimeout = Duration(seconds: 30);

  LiteRtService({FlutterGemmaPlugin? gemma})
      : _gemma = gemma ?? FlutterGemmaPlugin.instance;

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
    final ext = _extensionOf(modelPath);

    // Req 3.8: An unsupported file format must NOT disturb a model that is
    // already loaded. Reject before touching any engine state so the
    // previously loaded model (if any) stays loaded and usable.
    if (!_supportedExtensions.contains(ext)) {
      throw ValidationException.unsupportedFormat(ext.isEmpty ? modelPath : ext);
    }

    // Ensure the ServiceRegistry is initialized before installing.
    if (!_initialized) {
      await initialize();
    }

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
      // Modern flutter_gemma flow: install the already-downloaded file from
      // its local path (registers it and sets it active), then create the
      // inference model. The 30-second timeout bounds engine initialization
      // (Req 10.1); exceeding it fails the load like any other init error.
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      ).fromFile(modelPath).install().timeout(_initTimeout);

      _model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        supportImage: _supportsVision,
        maxNumImages: _supportsVision ? 1 : null,
      ).timeout(_initTimeout);
    } catch (e) {
      // Req 3.7 / 3.9 / 10.1: on any initialization or load failure (including
      // the timeout), clear the model so isModelLoaded reports false and
      // surface a load-failure error.
      _model = null;
      throw AIServiceException.modelLoadFailed(modelPath, e);
    }
  }

  /// Unloads the currently loaded LiteRT model, freeing native resources.
  ///
  /// Called by the EngineRouter when switching from a LiteRT model to a GGUF
  /// model so the LiteRT model's RAM is released. Idempotent — safe to call
  /// when no model is loaded.
  Future<void> unload() async {
    final previous = _model;
    if (previous == null) return;
    _model = null;
    try {
      await previous.close();
    } catch (_) {
      // Closing may fail if already disposed; ignore.
    }
  }

  /// Returns the lower-cased file extension (including the leading dot) of
  /// [path], or an empty string when the file name has no extension. Handles
  /// both `/` and `\` path separators.
  String _extensionOf(String path) {
    final normalized = path.toLowerCase();
    final lastSlash =
        normalized.lastIndexOf('/') > normalized.lastIndexOf('\\')
            ? normalized.lastIndexOf('/')
            : normalized.lastIndexOf('\\');
    final fileName =
        lastSlash >= 0 ? normalized.substring(lastSlash + 1) : normalized;
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
    // Req 3.10: a chat call with no loaded LiteRT model is an error.
    final model = _model;
    if (model == null) {
      throw AIServiceException.modelNotLoaded();
    }

    // Whether this turn carries an image the loaded model can actually use.
    final useImage = imageBytes != null && _supportsVision;

    // Open a fresh generation session for this turn. Enable the vision
    // modality on the session when an image is attached. The session is always
    // closed once the stream completes (or fails) so native resources are not
    // leaked across turns.
    final session = await model.createSession(
      temperature: temperature,
      enableVisionModality: useImage ? true : null,
    );
    try {
      // Req 3.4: feed the Gemma-formatted prompt to the session. When an image
      // is attached, send it together with the prompt as a multimodal message.
      final promptText =
          formatGemmaPrompt(prompt, systemPrompt: systemPrompt);
      if (useImage) {
        await session.addQueryChunk(
          Message.withImage(text: promptText, imageBytes: imageBytes, isUser: true),
        );
      } else {
        await session.addQueryChunk(Message.text(text: promptText, isUser: true));
      }

      // Req 3.5: relay the token stream in order; the underlying stream closes
      // when generation completes, which closes this stream too.
      yield* session.getResponseAsync();
    } finally {
      await session.close();
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

  /// LiteRtService alone does not track per-model tool-calling capability;
  /// that capability is sourced from catalog metadata and surfaced by the
  /// Engine_Router. Matching the [LLMService] default keeps this engine on the
  /// rule-based intent path unless the router decides otherwise (Req 2.5, 5.4).
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

  /// Sets whether the next loaded model should enable image input. Must be set
  /// by the router before [loadModel] because the model is created with image
  /// support up front.
  set supportsVision(bool value) => _supportsVision = value;

  /// Whether the plugin handle has been prepared. Exposed for the router and
  /// tests.
  bool get isInitialized => _initialized;

  /// The underlying `flutter_gemma` plugin handle. Used by [loadModel] and
  /// [chat] in later tasks.
  FlutterGemmaPlugin get plugin => _gemma;
}
