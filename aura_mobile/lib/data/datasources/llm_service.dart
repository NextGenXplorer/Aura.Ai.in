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
  Stream<String> chat(String prompt, {String? systemPrompt, int maxTokens, double temperature});
  bool get isModelLoaded;

  /// The tier of the currently loaded model, based on file name detection.
  ModelTier get modelTier;
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

  @override
  bool get isModelLoaded => _runAnywhere.isModelLoaded;

  @override
  ModelTier get modelTier {
    final path = _runAnywhere.currentModelPath?.toLowerCase() ?? '';
    if (path.contains('0.5b') || path.contains('0_5b')) return ModelTier.small;
    if (path.contains('1.5b') || path.contains('1_5b')) return ModelTier.medium;
    return ModelTier.large; // 3B, 7B, or unknown defaults to large
  }

  @override
  Stream<String> chat(String prompt, {String? systemPrompt, int maxTokens = 512, double temperature = 0.7}) {
    final raw = _runAnywhere.chat(
      prompt: prompt,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      temperature: temperature,
    );

    // Apply output cleaning to ALL models — even large models can leak
    // stop tokens like <|endoftext|>, Human:, User: etc.
    return _cleanModelOutput(raw);
  }

  /// Post-processing for model output — catches hallucinated conversation
  /// continuations and repetition loops that all model sizes can produce.
  Stream<String> _cleanModelOutput(Stream<String> raw) async* {
    int repeatCount = 0;
    String lastToken = '';
    final recentSentences = <String>[];
    final sentenceBuffer = StringBuffer();
    // Buffer to detect multi-token stop sequences like "<|" + "endoftext" + "|>"
    final tokenWindow = StringBuffer();

    await for (final token in raw) {
      // 1. Token-level repeat detection
      if (token == lastToken && token.trim().isNotEmpty) {
        repeatCount++;
        if (repeatCount >= 4) break;
      } else {
        repeatCount = 0;
      }
      lastToken = token;

      // 2. Build a sliding window to catch multi-token stop sequences
      tokenWindow.write(token);
      final window = tokenWindow.toString();

      // Check for leaked markers that signal the model is hallucinating new turns
      if (window.contains('<|endoftext|>') ||
          window.contains('<|im_end|>') ||
          window.contains('<|im_start|>') ||
          window.contains('Human:') ||
          window.contains('User:') ||
          window.contains('ASSISTANT RESPONSE') ||
          window.contains('USER REQUEST') ||
          window.contains('CURRENT USER REQUEST')) {
        // Yield everything BEFORE the marker, then stop
        final cutPoints = ['<|endoftext|>', '<|im_end|>', '<|im_start|>', 'Human:', 'User:', 'ASSISTANT RESPONSE', 'USER REQUEST', 'CURRENT USER REQUEST'];
        for (final cut in cutPoints) {
          final idx = window.indexOf(cut);
          if (idx >= 0) {
            // Only yield the clean part before the marker (from this token)
            final cleanPart = token.substring(0, token.length - (window.length - idx));
            if (cleanPart.isNotEmpty) yield cleanPart;
            return; // Stop generation
          }
        }
        break;
      }

      // Keep window small — only last 50 chars needed for detection
      if (tokenWindow.length > 50) {
        final str = tokenWindow.toString();
        tokenWindow.clear();
        tokenWindow.write(str.substring(str.length - 30));
      }

      // 3. Sentence-level repeat check (catches paragraph loops)
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

      yield token;
    }
  }
}
