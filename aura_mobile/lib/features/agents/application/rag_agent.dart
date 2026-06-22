import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/document_service.dart';
import 'package:aura_mobile/features/agents/domain/agent.dart';

class RAGAgent implements Agent {
  final DocumentService _documentService;
  final LLMService _llmService;

  RAGAgent(this._documentService, this._llmService);

  @override
  String get name => 'RAGAgent';

  @override
  Future<bool> canHandle(String intent) async {
    return intent == 'document_query';
  }

  @override
  Stream<String> process(String input, {Map<String, dynamic>? context}) async* {
    // 1. Check if a model is loaded
    if (!_llmService.isModelLoaded) {
      yield 'Please load an AI model first to query your documents.';
      return;
    }

    // 2. Retrieve relevant document chunks
    List<String> chunks;
    try {
      chunks = await _documentService.retrieveRelevantContext(input, limit: 10);
    } catch (e) {
      yield 'An error occurred while searching your documents. Please try again.';
      return;
    }

    if (chunks.isEmpty) {
      yield "I couldn't find relevant information in your uploaded documents for that query.";
      return;
    }

    // 3. Build RAG prompt and stream LLM response
    final ragPrompt = buildRagPrompt(input, chunks);

    try {
      await for (final token in _llmService.chat(
        ragPrompt,
        systemPrompt: null,
        maxTokens: 1024,
        temperature: 0.3,
      )) {
        yield token;
      }
    } catch (e) {
      yield '\n\n⚠️ An error occurred while generating the response. Please try again.';
      return;
    }

    // 4. Append citations
    yield formatCitations();
  }

  /// Builds a grounded RAG prompt from the user query and retrieved document chunks.
  String buildRagPrompt(String query, List<String> chunks) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Answer the following question based ONLY on the provided document excerpts. '
      "If the excerpts don't contain enough information, say so.",
    );
    buffer.writeln();
    buffer.writeln('Document Excerpts:');

    for (final chunk in chunks) {
      buffer.writeln('---');
      buffer.writeln(chunk);
    }

    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('Question: $query');
    buffer.writeln();
    buffer.write('Answer:');
    return buffer.toString();
  }

  /// Formats a generic citation footer.
  ///
  /// Since the current DocumentService returns only chunk text without document
  /// metadata, we use a generic citation. This can be enhanced later when the
  /// repository exposes document names per chunk.
  String formatCitations() {
    return '\n\n📄 **Sources:** Your uploaded documents';
  }
}
