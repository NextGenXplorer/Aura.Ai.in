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

    // For small models: apply post-processing to clean up common hallucination artifacts
    if (modelTier.isSmall) {
      return _cleanSmallModelOutput(raw);
    }
    return raw;
  }

  /// Lightweight post-processing for small model output.
  /// Only checks for token-level repetition (O(1) per token) and leaked
  /// prompt markers (checked only on the token itself, not the full buffer).
  Stream<String> _cleanSmallModelOutput(Stream<String> raw) async* {
    int repeatCount = 0;
    String lastToken = '';
    // Track last few sentences cheaply for repetition detection
    final recentSentences = <String>[];
    final sentenceBuffer = StringBuffer();

    await for (final token in raw) {
      // 1. Token-level repeat detection — O(1)
      if (token == lastToken && token.trim().isNotEmpty) {
        repeatCount++;
        if (repeatCount >= 4) break; // Stuck in loop
      } else {
        repeatCount = 0;
      }
      lastToken = token;

      // 2. Check leaked markers on the token itself — O(1), no buffer scan
      if (token.contains('<|im_') ||
          token.contains('ASSISTANT RESPONSE') ||
          token.contains('USER REQUEST')) {
        break;
      }

      // 3. Cheap sentence-level repeat check — only on sentence boundaries
      sentenceBuffer.write(token);
      if (token.contains('.') || token.contains('!') || token.contains('?') || token.contains('\n')) {
        final sentence = sentenceBuffer.toString().trim();
        if (sentence.length > 15) {
          // Count how many recent sentences match
          int matches = 0;
          for (final s in recentSentences) {
            if (s == sentence) matches++;
          }
          if (matches >= 2) break; // Same sentence 3rd time (2 in history + current)

          recentSentences.add(sentence);
          // Only keep last 6 sentences in memory
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
