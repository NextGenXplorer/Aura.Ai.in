import 'dart:typed_data';

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

abstract interface class CancellableLLMService {
  Future<void> cancelGeneration();
}

class GenerationCancelledException implements Exception {
  const GenerationCancelledException();

  @override
  String toString() => 'Generation cancelled';
}

abstract class LLMService {
  Future<void> initialize();
  Future<void> loadModel(String modelPath);

  /// [temperature] controls randomness: 0.3 = factual/grounded, 0.7 = creative/conversational.
  ///
  /// [imageBytes], when provided, attaches an image to the turn for multimodal
  /// (vision) models. Text-only engines ignore it. Only models that report
  /// [supportsVision] will actually process the image.
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens,
    double temperature,
    Uint8List? imageBytes,
  });
  bool get isModelLoaded;

  /// Whether this runtime currently owns an active generation session.
  bool get isGenerating;

  /// The tier of the currently loaded model.
  ModelTier get modelTier;

  /// Whether the currently active model supports native function/tool calling.
  bool get supportsToolCalling => false;

  /// Whether the currently active model can accept image input (multimodal
  /// vision). Defaults to `false`; vision-capable engines override it when a
  /// vision model is active.
  bool get supportsVision => false;

  /// Usable context window of the active model, in tokens. Engines override it
  /// with real metadata (LiteRT KV-cache size, provider-reported context) so
  /// the UI does not assume one fixed size for every model.
  int get contextTokens => 4096;
}
