import 'package:flutter_riverpod/flutter_riverpod.dart';

enum IntentType {
  normalChat,
  storeMemory,
  retrieveMemory,
  queryDocument,
  webSearch,
}

final intentDetectionServiceProvider = Provider((ref) => IntentDetectionService());

class IntentDetectionService {
  /// Strictly rule-based intent detection as per SuperGravity architecture.
  /// Does NOT use LLM.
  Future<IntentType> detectIntent(String message, {List<Map<String, String>>? history, bool hasDocuments = false}) async {
    print("INTENT_DETECTION: Analyzing message: '$message'");
    final lowerMessage = message.trim().toLowerCase();

    // 0. Explicit Web Search (from UI command)
    // We'll use a prefix convention like "[SEARCH]" or just check keywords if UI doesn't inject prefix.
    // Ideally UI should strip prefix, but if we want to detect it here:
    if (message.startsWith("[SEARCH]")) {
      print("INTENT_DETECTION: Detected [SEARCH] prefix -> webSearch");
      return IntentType.webSearch;
    }

    // 1. Memory Store Rules
    if (lowerMessage.startsWith("remember that") ||
        lowerMessage.startsWith("save this")) {
      return IntentType.storeMemory;
    }

    // 2. Memory Retrieval Rules
    // "If message asks about past saved info -> Memory Retrieval"
    if (lowerMessage.contains("what did i") ||
        lowerMessage.contains("do you remember") ||
        lowerMessage.contains("retrieve") ||
        lowerMessage.contains("recall") ||
        lowerMessage.contains("remind me")) {
      return IntentType.retrieveMemory;
    }

    // 3. Document Mode Rules
    // "If documents exist and similarity score high -> Document Mode"
    if (hasDocuments) {
       // Heuristic: If it's a question and we have docs, prefer checking docs.
       // Or if explicitly asking to "read" or "summarize".
       if (lowerMessage.contains("read file") || 
           lowerMessage.contains("summarize") || 
           lowerMessage.contains("document") ||
           lowerMessage.contains("pdf")) {
         return IntentType.queryDocument;
       }
    }

    // 4. Web Search Keywords (Fallback if not explicit)
    if (lowerMessage.startsWith("search for") ||
        lowerMessage.startsWith("search web") ||
        lowerMessage.startsWith("find online") ||
        lowerMessage.startsWith("google")) {
      return IntentType.webSearch;
    }

    // Default: Normal Chat
    return IntentType.normalChat;
  }

  /// Extracts the content to be saved from a memory command.
  String extractMemoryContent(String message) {
    final lowerMessage = message.toLowerCase();
    if (lowerMessage.startsWith("remember that")) {
      return message.substring("remember that".length).trim();
    }
    if (lowerMessage.startsWith("save this")) {
      return message.substring("save this".length).trim();
    }
    return message;
  }
}
