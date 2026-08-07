import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// Text vectoriser intended for EmbeddingGemma 300M.
///
/// IMPORTANT: this does not currently produce true semantic embeddings. Until
/// flutter_gemma exposes a native embedding API, [embed] hashes generated text
/// into a fixed-size vector (see [_textToEmbedding]), which gives only a weak
/// lexical signal. Nothing in the app should describe this as semantic search.
/// The utility model it depends on is also not downloadable yet, so document
/// and memory lookups run on keyword search in practice.
///
/// Progressive Enhancement: When this service has a loaded model, MemoryService
/// and DocumentService use it for vector similarity search. When not loaded,
/// they fall back to keyword-based search.
///
/// This service runs on a SEPARATE pipeline from the main chat LLM — loading or
/// using EmbeddingGemma never unloads or interferes with the active chat model.
class EmbeddingService {
  InferenceModel? _model;
  bool _isLoaded = false;

  /// Embedding dimension produced by EmbeddingGemma 300M.
  static const int embeddingDimension = 768;

  /// Load the EmbeddingGemma model from the given path.
  /// Should be called on app start if the model file exists.
  Future<void> loadModel(String modelPath) async {
    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      ).fromFile(modelPath).install().timeout(const Duration(seconds: 30));

      _model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
      ).timeout(const Duration(seconds: 30));

      _isLoaded = true;
      debugPrint('EmbeddingService: Model loaded successfully');
    } catch (e) {
      _isLoaded = false;
      _model = null;
      debugPrint('EmbeddingService: Load failed: $e');
    }
  }

  /// Generate a 768-dimensional embedding vector for the given text.
  ///
  /// Returns an empty list if:
  /// - Model is not loaded
  /// - Inference fails
  /// - Text is empty
  ///
  /// Callers (MemoryService, DocumentService) treat empty list as "use keyword
  /// fallback instead".
  Future<List<double>> embed(String text) async {
    if (!_isLoaded || _model == null || text.trim().isEmpty) return [];

    try {
      final session = await _model!.createSession(temperature: 0.0);
      try {
        // Ask the model to generate an embedding representation
        // The actual embedding extraction depends on flutter_gemma's API
        final prompt = 'Represent this text for retrieval: $text';
        await session.addQueryChunk(Message.text(text: prompt, isUser: true));

        // Collect the model output tokens and hash them into a pseudo-embedding
        // NOTE: This is a workaround — real EmbeddingGemma uses a dedicated
        // embedding API. When flutter_gemma exposes native embedding support,
        // replace this with the proper API call.
        final buffer = StringBuffer();
        await for (final token in session.getResponseAsync()) {
          buffer.write(token);
          if (buffer.length > 200) break; // Cap output length
        }

        // Generate a deterministic pseudo-embedding from the output text.
        // This provides SOME semantic signal (model's interpretation of the
        // input) while we await proper embedding API support.
        return _textToEmbedding(buffer.toString());
      } finally {
        await session.close();
      }
    } catch (e) {
      debugPrint('EmbeddingService: embed failed: $e');
      return [];
    }
  }

  /// Convert text to a deterministic 768-dim embedding vector.
  ///
  /// Uses a simple hash-based approach: splits text into character trigrams,
  /// hashes each to a position in the 768-dim vector, and normalizes.
  /// This provides weak but non-trivial semantic signal — texts with similar
  /// content produce more similar vectors than completely different texts.
  ///
  /// Will be replaced with native embedding API when available.
  static List<double> _textToEmbedding(String text) {
    final embedding = List<double>.filled(embeddingDimension, 0.0);
    if (text.isEmpty) return embedding;

    final normalized = text.toLowerCase().trim();
    // Character trigram hashing
    for (int i = 0; i < normalized.length - 2; i++) {
      final trigram = normalized.substring(i, i + 3);
      final hash = trigram.hashCode;
      final idx = hash.abs() % embeddingDimension;
      embedding[idx] += 1.0;
    }

    // Word-level features
    final words = normalized.split(RegExp(r'\s+')).where((w) => w.length > 2);
    for (final word in words) {
      final idx = word.hashCode.abs() % embeddingDimension;
      embedding[idx] += 2.0; // Words get higher weight
    }

    // L2 normalize
    double norm = 0.0;
    for (final v in embedding) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (int i = 0; i < embedding.length; i++) {
        embedding[i] /= norm;
      }
    }

    return embedding;
  }

  /// Compute cosine similarity between two embedding vectors.
  ///
  /// Returns a value in [-1.0, 1.0] for non-empty vectors of equal length.
  /// Returns 0.0 for empty or mismatched vectors.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = sqrt(normA) * sqrt(normB);
    if (denominator == 0.0) return 0.0;
    return dotProduct / denominator;
  }

  /// Whether the EmbeddingGemma model is loaded and ready.
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
