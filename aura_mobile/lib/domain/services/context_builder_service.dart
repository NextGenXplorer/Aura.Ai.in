
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

  // ── Memory cache to avoid redundant DB+embedding queries on rapid messages ──
  String? _lastMemoryQuery;
  List<String> _cachedMemories = [];
  DateTime _memoryCacheTime = DateTime(2000);
  static const Duration _memoryCacheTTL = Duration(seconds: 30);

  ContextBuilderService(this._memoryService, this._documentService);

  Future<String> buildPrompt({
    required String userMessage,
    required List<String> chatHistory,
    bool includeMemories = true,
    bool includeDocuments = true,
  }) async {
    final systemContext = await buildSystemContext(
      userMessage: userMessage,
      chatHistory: chatHistory,
      includeMemories: includeMemories,
      includeDocuments: includeDocuments,
    );
    return '$systemContext\n\n$userMessage';
  }

  /// Build ONLY the system context (persona + memories + docs + history).
  /// The user message is NOT included — caller passes it separately to chat().
  /// This allows the prompt template to properly separate system vs user roles.
  Future<String> buildSystemContext({
    required String userMessage,
    required List<String> chatHistory,
    bool includeMemories = true,
    bool includeDocuments = true,
  }) async {
    final buffer = StringBuffer();

    // 1. System Instruction
    final basePrompt = personaSystemPrompt ??
        'You are AURA, a helpful, knowledgeable AI assistant. '
        'You provide detailed, accurate, and helpful responses to any question.';

    if (modelTier.isSmall || modelTier == ModelTier.medium) {
      buffer.writeln(basePrompt);
    } else {
      buffer.writeln('$basePrompt '
          'Answer the user thoroughly. Be natural and conversational. '
          'If you don\'t know something, say so honestly.');
    }

    // 2. Memory Context
    if (includeMemories) {
      final memories = await _getMemoriesCached(userMessage);
      if (memories.isNotEmpty) {
        final limit = (modelTier.isSmall || modelTier == ModelTier.medium) ? 2 : 3;
        final topMemories = memories.take(limit).toList();
        buffer.writeln('\nRelevant context:');
        for (var mem in topMemories) {
          buffer.writeln('- $mem');
        }
      }
    }

    // 3. Document Context
    if (includeDocuments) {
      final docContext = await _documentService.retrieveRelevantContext(userMessage);
      if (docContext.isNotEmpty) {
        final limit = (modelTier.isSmall || modelTier == ModelTier.medium) ? 1 : 2;
        final topDocs = docContext.take(limit).toList();
        buffer.writeln('\nDocument context:');
        for (var chunk in topDocs) {
          buffer.writeln(chunk);
        }
      }
    }

    // 4. Chat History
    if (chatHistory.isNotEmpty) {
      final historyLimit = (modelTier.isSmall || modelTier == ModelTier.medium) ? 4 : 10;
      final limitedHistory = chatHistory.length > historyLimit
          ? chatHistory.sublist(chatHistory.length - historyLimit)
          : chatHistory;

      buffer.writeln('\nConversation so far:');
      for (var msg in limitedHistory) {
        buffer.writeln(msg);
      }
    }

    return buffer.toString().trim();
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

  /// Returns cached memories if the same query was asked within the TTL window.
  /// Avoids redundant embedding generation + DB scan on rapid follow-up messages.
  Future<List<String>> _getMemoriesCached(String query) async {
    final now = DateTime.now();
    if (_lastMemoryQuery == query && now.difference(_memoryCacheTime) < _memoryCacheTTL) {
      return _cachedMemories;
    }

    final memories = await _memoryService.retrieveRelevantMemories(query);
    _lastMemoryQuery = query;
    _cachedMemories = memories;
    _memoryCacheTime = now;
    return memories;
  }
}
