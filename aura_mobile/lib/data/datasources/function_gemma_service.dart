import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// Maps FunctionGemma output function names to IntentType enum name strings.
const Map<String, String> functionToIntentMap = {
  'toggleTorch': 'torchControl',
  'openCamera': 'openCamera',
  'openSettings': 'openSettings',
  'dialContact': 'dialContact',
  'sendSMS': 'sendSMS',
  'composeEmail': 'emailDraft',
  'webSearch': 'webSearch',
  'setAlarm': 'reminderSet',
  'createCalendarEvent': 'createEvent',
  'getNextEvent': 'getNextEvent',
  'startNavigation': 'navigation',
  'openApp': 'openApp',
  'detectFaces': 'scanImage',
  'detectObjects': 'scanImage',
  'removeBackground': 'scanImage',
  'detectPose': 'scanImage',
};

/// Service that uses the FunctionGemma 270M model to classify natural language
/// into structured JSON function calls for device actions.
///
/// Progressive Enhancement: When this service has a loaded model, the
/// IntentDetectionService calls it BEFORE the regex engine. If the model
/// returns a valid function call, that's used; otherwise regex takes over.
class FunctionGemmaService {
  InferenceModel? _model;
  bool _isLoaded = false;

  /// Maximum time allowed for a single FunctionGemma inference call.
  /// If exceeded, the result is discarded and regex fallback is used.
  static const Duration _inferenceTimeout = Duration(milliseconds: 500);

  /// Load the FunctionGemma model from the given path.
  /// Should be called on app start if the model file exists.
  Future<void> loadModel(String modelPath) async {
    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      ).fromFile(modelPath).install().timeout(const Duration(seconds: 30));

      _model = await FlutterGemma.getActiveModel(
        maxTokens: 256,
      ).timeout(const Duration(seconds: 30));

      _isLoaded = true;
      debugPrint('FunctionGemmaService: Model loaded successfully');
    } catch (e) {
      _isLoaded = false;
      _model = null;
      debugPrint('FunctionGemmaService: Load failed: $e');
    }
  }

  /// Classify a user message into a structured function call.
  ///
  /// Returns a Map with 'name' (String) and 'arguments' (Map) keys if the
  /// model produces a valid function call. Returns null on:
  /// - Timeout (>500ms)
  /// - Parse error (output is not valid JSON)
  /// - Invalid structure (missing 'name' or 'arguments' key)
  /// - Model not loaded
  /// - Any runtime exception
  ///
  /// Callers (IntentDetectionService) treat null as "fall through to regex".
  Future<Map<String, dynamic>?> classifyIntent(String message) async {
    if (!_isLoaded || _model == null) return null;

    try {
      final output = await _runInference(message).timeout(_inferenceTimeout);
      return _parseResult(output);
    } catch (e) {
      // Timeout or runtime error → return null for fallback
      debugPrint('FunctionGemmaService: classifyIntent failed: $e');
      return null;
    }
  }

  /// Run inference on the loaded FunctionGemma model.
  Future<String> _runInference(String message) async {
    final session = await _model!.createSession(temperature: 0.0);
    try {
      final prompt = _buildPrompt(message);
      await session.addQueryChunk(
        Message.text(text: prompt, isUser: true),
      );
      final buffer = StringBuffer();
      await for (final token in session.getResponseAsync()) {
        buffer.write(token);
        // Early exit if we have enough for a JSON response
        if (buffer.length > 500) break;
      }
      return buffer.toString();
    } finally {
      await session.close();
    }
  }

  /// Build the prompt for FunctionGemma.
  /// Uses Gemma turn markers since FunctionGemma is based on Gemma 3.
  String _buildPrompt(String message) {
    return '<start_of_turn>user\n'
        '$message'
        '<end_of_turn>\n'
        '<start_of_turn>model\n';
  }

  /// Parse FunctionGemma output into {name, arguments} map.
  /// Returns null if output is not valid JSON with the expected structure.
  Map<String, dynamic>? _parseResult(String output) {
    try {
      final trimmed = output.trim();
      if (trimmed.isEmpty) return null;

      // FunctionGemma may wrap output in markdown code fences
      String jsonStr = trimmed;
      if (jsonStr.startsWith('```')) {
        final firstNewline = jsonStr.indexOf('\n');
        if (firstNewline > 0) jsonStr = jsonStr.substring(firstNewline + 1);
        final lastFence = jsonStr.lastIndexOf('```');
        if (lastFence > 0) jsonStr = jsonStr.substring(0, lastFence);
        jsonStr = jsonStr.trim();
      }

      // Try to extract JSON object
      final startBrace = jsonStr.indexOf('{');
      final endBrace = jsonStr.lastIndexOf('}');
      if (startBrace < 0 || endBrace <= startBrace) return null;
      jsonStr = jsonStr.substring(startBrace, endBrace + 1);

      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) return null;

      // Validate required keys
      final name = decoded['name'];
      if (name is! String || name.isEmpty) return null;

      // arguments is optional but must be a map if present
      final args = decoded['arguments'];
      if (args != null && args is! Map) return null;

      return {
        'name': name,
        'arguments': args is Map ? Map<String, dynamic>.from(args) : <String, dynamic>{},
      };
    } catch (e) {
      return null;
    }
  }

  /// Whether the FunctionGemma model is currently loaded and ready.
  bool get isLoaded => _isLoaded;

  /// Unload the model and free resources.
  Future<void> dispose() async {
    if (_model != null) {
      try {
        await _model!.close();
      } catch (_) {}
      _model = null;
    }
    _isLoaded = false;
  }
}
