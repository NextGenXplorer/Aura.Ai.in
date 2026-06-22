import 'dart:math';
import 'dart:typed_data';

import 'package:aura_mobile/ai/run_anywhere_service.dart';

/// Tier of the currently loaded model, used to adapt prompt complexity and behavior.
enum ModelTier {
  /// 0.5B — ultra-light, weak instruction following, high hallucination risk
  small,
  /// 1.5B — decent, moderate instruction following
  medium,
  /// 3B+ — strong reasoning, good instruction following
  large;

  /// Whether this model tier is prone to hallucination and needs simpler prompts.
  bool get isSmall => this == ModelTier.small;
}

abstract class LLMService {
  Future<void> initialize();
  Future<void> loadModel(String modelPath);
  /// [temperature] controls randomness: 0.3 = factual/grounded, 0.7 = creative/conversational.
  ///
  /// [imageBytes], when provided, attaches an image to the turn for multimodal
  /// (vision) models. Text-only engines ignore it. Only models that report
  /// [supportsVision] will actually process the image.
  Stream<String> chat(String prompt,
      {String? systemPrompt, int maxTokens, double temperature, Uint8List? imageBytes});
  bool get isModelLoaded;

  /// The tier of the currently loaded model, based on file name detection.
  ModelTier get modelTier;

  /// Whether the currently active model supports native function/tool calling.
  ///
  /// Defaults to `false` so existing engines (GGUF/Qwen) and any implementation
  /// that predates multi-engine support keep using the orchestrator's
  /// rule-based intent detection. Engines that front tool-calling-capable
  /// models (e.g. the LiteRT Gemma 4 family via the Engine_Router) override
  /// this to return `true` when such a model is active. This keeps the
  /// interface backward compatible (Requirements 2.5, 5.4).
  bool get supportsToolCalling => false;

  /// Whether the currently active model can accept image input (multimodal
  /// vision). Defaults to `false`; vision-capable engines override it when a
  /// vision model is active.
  bool get supportsVision => false;
}

class LLMServiceImpl implements LLMService {
  final RunAnywhere _runAnywhere;

  LLMServiceImpl(this._runAnywhere);

  @override
  Future<void> initialize() async {
    await _runAnywhere.initialize();
  }

  @override
  Future<void> loadModel(String modelPath) async {
    await _runAnywhere.loadModel(modelPath);
  }

  /// Unloads the currently loaded GGUF model, freeing the fllama context.
  ///
  /// Called by the EngineRouter when switching from GGUF to LiteRT so the
  /// fllama context's native memory is released. Idempotent.
  Future<void> unload() async {
    try {
      _runAnywhere.unloadModel();
    } catch (_) {
      // Best-effort; ignore failures.
    }
  }

  @override
  bool get isModelLoaded => _runAnywhere.isModelLoaded;

  @override
  ModelTier get modelTier => modelTierForPath(_runAnywhere.currentModelPath);

  @override
  bool get supportsToolCalling => false;

  @override
  bool get supportsVision => false;

  /// Pure file-name based tier detection.
  ///
  /// Maps a GGUF model file name (or path) to its [ModelTier]: a name encoding
  /// 0.5B -> [ModelTier.small], 1.5B -> [ModelTier.medium], anything else
  /// (3B, 7B, or unknown) -> [ModelTier.large]. Detection is case-insensitive
  /// and accepts both `.` and `_` as the decimal separator in the size marker.
  ///
  /// Exposed as a pure static function so the mapping can be verified directly.
  static ModelTier modelTierForPath(String? modelPath) {
    final path = modelPath?.toLowerCase() ?? '';
    // Small tier: ~0.5–0.6B models (weak instruction following).
    if (path.contains('0.5b') || path.contains('0_5b') ||
        path.contains('0.6b') || path.contains('0-6b')) {
      return ModelTier.small;
    }
    // Medium tier: ~1.5–1.7B models.
    if (path.contains('1.5b') || path.contains('1_5b') ||
        path.contains('1.7b') || path.contains('1-7b')) {
      return ModelTier.medium;
    }
    return ModelTier.large; // 3B, 4B, 7B, or unknown defaults to large
  }

  @override
  Stream<String> chat(String prompt, {String? systemPrompt, int maxTokens = 512, double temperature = 0.7, Uint8List? imageBytes}) {
    // The GGUF engine is text-only; imageBytes is ignored (vision is handled by
    // the LiteRT engine for multimodal Gemma models).
    final raw = _runAnywhere.chat(
      prompt: prompt,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      temperature: temperature,
    );

    // Apply output cleaning to ALL models — even large models can leak
    // stop tokens like <|endoftext|>, Human:, User: etc.
    return cleanModelOutput(raw);
  }

  /// Post-processing for model output — catches hallucinated conversation
  /// continuations and repetition loops that all model sizes can produce.
  ///
  /// Exposed as a pure static function (it depends only on its input stream,
  /// not on instance state) so the cleaning behavior can be verified directly
  /// without standing up the native engine.
  /// Stop/hallucination markers that terminate the stream. The cleaner
  /// truncates output at the first occurrence of any of these.
  ///
  /// Markers fall into two categories:
  /// - [_unconditionalMarkers]: tokens that are NEVER valid in user-facing
  ///   output (chat-template control tokens like `<|im_end|>`).
  /// - [_lineStartMarkers]: words like "Human:" / "User:" that signal a
  ///   hallucinated turn ONLY when they appear at the start of a line. If
  ///   matched anywhere they would falsely truncate legit prose like
  ///   "I told the User: yes, I can help".
  static const List<String> _unconditionalMarkers = [
    '<|endoftext|>',
    '<|im_end|>',
    '<|im_start|>',
    'ASSISTANT RESPONSE',
    'USER REQUEST',
    'CURRENT USER REQUEST',
  ];

  static const List<String> _lineStartMarkers = [
    'Human:',
    'User:',
  ];

  static Stream<String> cleanModelOutput(Stream<String> raw) async* {
    int repeatCount = 0;
    String lastToken = '';
    final recentSentences = <String>[];
    final sentenceBuffer = StringBuffer();

    // Combined marker list for length calculation only — actual matching
    // is split between unconditional and line-start checks below.
    final allMarkers = [..._unconditionalMarkers, ..._lineStartMarkers];
    final maxMarkerLen = allMarkers.map((m) => m.length).reduce(max);

    // `pending` holds accepted clean text that has NOT yet been emitted because
    // its trailing portion could be the start of a marker that completes in a
    // later token (markers can be split across streamed tokens). Anything we
    // emit from `pending` is guaranteed not to be part of a marker.
    final pending = StringBuffer();

    // Tracks how many characters of clean output we've emitted, so we can tell
    // whether a "Human:"/"User:" match is at line-start.
    final emitted = StringBuffer();

    /// Returns the earliest match index of any marker in [combined], using the
    /// rule that line-start markers only count when preceded by `\n` or at
    /// position 0 of the FULL emitted+combined stream.
    int findEarliestMarker(String combined, int emittedLen) {
      int earliest = -1;

      // Unconditional markers — match anywhere.
      for (final m in _unconditionalMarkers) {
        final idx = combined.indexOf(m);
        if (idx >= 0 && (earliest < 0 || idx < earliest)) earliest = idx;
      }

      // Line-start markers — match only when preceded by `\n` or at the very
      // start of the conversation output (emittedLen == 0 && idx == 0).
      for (final m in _lineStartMarkers) {
        int searchFrom = 0;
        while (true) {
          final idx = combined.indexOf(m, searchFrom);
          if (idx < 0) break;
          // Determine the character immediately before this match in the
          // full output (emitted text + this combined buffer).
          final isLineStart = idx == 0
              ? (emittedLen == 0 ? true : emitted.toString().endsWith('\n'))
              : combined[idx - 1] == '\n';
          if (isLineStart) {
            if (earliest < 0 || idx < earliest) earliest = idx;
            break;
          }
          searchFrom = idx + 1;
        }
      }

      return earliest;
    }

    await for (final token in raw) {
      // 1. Token-level repeat detection — the repeating token is dropped.
      if (token == lastToken && token.trim().isNotEmpty) {
        repeatCount++;
        if (repeatCount >= 4) break;
      } else {
        repeatCount = 0;
      }
      lastToken = token;

      // 2. Marker detection across the token boundary. Combine the held-back
      // text with the new token so a marker split across tokens is found.
      final combined = pending.toString() + token;

      final markerIdx = findEarliestMarker(combined, emitted.length);
      if (markerIdx >= 0) {
        // Emit only the clean text before the first marker, then stop.
        final cleanPart = combined.substring(0, markerIdx);
        if (cleanPart.isNotEmpty) {
          yield cleanPart;
          emitted.write(cleanPart);
        }
        return;
      }

      // 3. Sentence-level repeat check (catches paragraph loops). On a repeat
      // the current token is dropped; previously accepted text is flushed
      // after the loop.
      sentenceBuffer.write(token);
      if (token.contains('.') || token.contains('!') || token.contains('?') || token.contains('\n')) {
        final sentence = sentenceBuffer.toString().trim();
        if (sentence.length > 15) {
          int matches = 0;
          for (final s in recentSentences) {
            if (s == sentence) matches++;
          }
          if (matches >= 2) break;

          recentSentences.add(sentence);
          if (recentSentences.length > 6) {
            recentSentences.removeAt(0);
          }
        }
        sentenceBuffer.clear();
      }

      // 4. No complete marker yet. Hold back the longest suffix of `combined`
      // that is a proper prefix of some marker (it may still become a marker);
      // emit everything before it.
      int holdBack = 0;
      final maxCheck = min(combined.length, maxMarkerLen - 1);
      for (var len = maxCheck; len > 0; len--) {
        final suffix = combined.substring(combined.length - len);
        var isMarkerPrefix = false;
        for (final marker in allMarkers) {
          if (marker.length > len && marker.startsWith(suffix)) {
            isMarkerPrefix = true;
            break;
          }
        }
        if (isMarkerPrefix) {
          holdBack = len;
          break;
        }
      }

      final emitLen = combined.length - holdBack;
      if (emitLen > 0) {
        final part = combined.substring(0, emitLen);
        yield part;
        emitted.write(part);
      }
      pending
        ..clear()
        ..write(combined.substring(emitLen));
    }

    // Stream ended (or a loop was broken) with no marker: the held-back text
    // can never become a marker, so emit it.
    final remaining = pending.toString();
    if (remaining.isNotEmpty) yield remaining;
  }
}
