/// Identifies the inference engine that owns a given model.
///
/// Exactly two values are supported, matching the catalog `engine` field
/// strings `gguf` (RunAnywhere / fllama / llama.cpp) and `litert`
/// (flutter_gemma / LiteRT-LM / MediaPipe).
enum AIEngine {
  gguf,
  litert;

  /// Resolves an [AIEngine] from its string identifier.
  ///
  /// Throws an [ArgumentError] when [id] does not match a known engine value.
  static AIEngine fromId(String id) => values.firstWhere(
        (e) => e.name == id,
        orElse: () => throw ArgumentError('Unknown engine: $id'),
      );
}

/// Categorizes a model's relative inference speed for catalog display.
enum InferenceSpeed {
  fast,
  medium,
  slow,
}
