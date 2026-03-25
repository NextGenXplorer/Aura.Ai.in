
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/document_service.dart';
import 'package:aura_mobile/domain/services/memory_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final contextBuilderServiceProvider = Provider((ref) => ContextBuilderService(
  ref.read(memoryServiceProvider),
  ref.read(documentServiceProvider),
));

class ContextBuilderService {
  final MemoryService _memoryService;
  final DocumentService _documentService;

  /// Active persona system prompt override. Set by the persona provider.
  String? personaSystemPrompt;

  /// Current model tier — set by the orchestrator so prompts adapt to model size.
  ModelTier modelTier = ModelTier.large;

  ContextBuilderService(this._memoryService, this._documentService);

  Future<String> buildPrompt({
    required String userMessage,
    required List<String> chatHistory,
    bool includeMemories = true,
    bool includeDocuments = true,
  }) async {
    final buffer = StringBuffer();

    // 1. System Instruction — shorter for small models, detailed for large
    if (modelTier.isSmall) {
      final basePrompt = personaSystemPrompt ??
          "You are AURA, a helpful AI assistant.";
      buffer.writeln("$basePrompt If unsure, say you don't know. Only use the context provided below.");
    } else {
      final basePrompt = personaSystemPrompt ??
          "You are AURA, a privacy-first offline AI assistant. Answer concisely and helpfully.";
      buffer.writeln("$basePrompt "
          "IMPORTANT RULES: "
          "1. Only state facts you are confident about. If you are unsure or don't know, say so clearly — never make up information. "
          "2. When context (memories, documents, or search results) is provided below, base your answer strictly on that context. Do not invent details beyond what is given. "
          "3. Distinguish between what you know vs. what you are reasoning about. Use phrases like 'Based on the provided context...' or 'I think...' when appropriate. "
          "4. When writing HTML, always include CSS within <style> tags and JavaScript within <script> tags in a single ```html block. Do NOT create separate blocks for css or javascript.");
    }

    // 2. Memory Context — fewer for small models to save context window
    if (includeMemories) {
      final memories = await _memoryService.retrieveRelevantMemories(userMessage);
      if (memories.isNotEmpty) {
        final limit = modelTier.isSmall ? 2 : 3;
        final topMemories = memories.take(limit).toList();
        buffer.writeln("\nMemories:");
        for (var mem in topMemories) {
          buffer.writeln("- $mem");
        }
      }
    }

    // 3. Document Context — fewer chunks for small models
    if (includeDocuments) {
      final docContext = await _documentService.retrieveRelevantContext(userMessage);
      if (docContext.isNotEmpty) {
        final limit = modelTier.isSmall ? 1 : 2;
        final topDocs = docContext.take(limit).toList();
        buffer.writeln("\nDocument Context:");
        for (var chunk in topDocs) {
          buffer.writeln(chunk);
        }
      }
    }

    // 4. Chat History — less history for small models to save context window
    if (chatHistory.isNotEmpty) {
      final historyLimit = modelTier.isSmall ? 2 : 3;
      buffer.writeln("\n--- PREVIOUS CONVERSATION CONTEXT (Do not repeat previous answers) ---");
      final limitedHistory = chatHistory.length > historyLimit
          ? chatHistory.sublist(chatHistory.length - historyLimit)
          : chatHistory;

      for (var msg in limitedHistory) {
        buffer.writeln(msg);
      }
      buffer.writeln("--- END OF PREVIOUS CONVERSATION ---\n");
    }

    buffer.writeln("CURRENT USER REQUEST: \"$userMessage\"");
    buffer.writeln("ASSISTANT RESPONSE:");

    return buffer.toString();
  }

  String injectMemory(List<String> memories, String message) {
    final buffer = StringBuffer();
    if (modelTier.isSmall) {
      // Short, direct prompt for small models
      buffer.writeln("User asked: \"$message\"");
      buffer.writeln("Answer using ONLY these memories. Say \"I don't have that info\" if not found:");
    } else {
      buffer.writeln("You are AURA. The user asked: \"$message\"");
      buffer.writeln("\nAnswer ONLY based on the following retrieved memories. If the memories don't contain enough information to fully answer, say what you know and clearly state what is missing. Do not invent or assume details:");
    }
    for (var memory in memories) {
      buffer.writeln("- $memory");
    }
    return buffer.toString();
  }

  String injectWeb(List<dynamic> results, String message) {
    final buffer = StringBuffer();
    // For small models: fewer results, shorter prompt
    final resultLimit = modelTier.isSmall ? 3 : results.length;
    final limitedResults = results.take(resultLimit);

    buffer.writeln("Web Search Results for: \"$message\"");
    for (var result in limitedResults) {
      buffer.writeln("\nTITLE: ${result.title}");
      buffer.writeln("CONTENT: ${result.snippet}");
    }

    if (modelTier.isSmall) {
      buffer.writeln("\nAnswer using ONLY the results above. If not found, say so.");
    } else {
      buffer.writeln("\nTASK: Synthesize ONLY the information above to answer: \"$message\"");
      buffer.writeln("RULES: Answer strictly based on the search results provided. If the results don't fully cover the question, clearly state what you found and what is missing. Never fabricate facts, statistics, dates, or details that are not in the results above.");
    }
    buffer.writeln("\nANSWER:");
    return buffer.toString();
  }

  String injectURL(dynamic content, String message) {
    final buffer = StringBuffer();
    buffer.writeln("Webpage Content for: \"$message\"");
    buffer.writeln("PAGE TITLE: ${content.title}");
    buffer.writeln("PAGE EXCERPT:\n${content.snippet}");

    if (modelTier.isSmall) {
      buffer.writeln("\nSummarize using ONLY the content above.");
    } else {
      buffer.writeln("\nTASK: Summarize this page to answer: \"$message\"");
      buffer.writeln("RULE: Only use information from the page content above. Do not add facts or details not present in the excerpt.");
    }
    buffer.writeln("\nANSWER:");
    return buffer.toString();
  }
}
