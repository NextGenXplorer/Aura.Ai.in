import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum IntentType {
  normalChat,
  webSearch,
  urlScrape,
  memoryStore,
  memoryRetrieve,
  openApp,
  closeApp,
  openSettings,
  openCamera,
  dialContact,
  sendSMS
}

final intentDetectionServiceProvider = Provider((ref) => IntentDetectionService());

class IntentDetectionService {
  /// Strictly rule-based intent detection as per SuperGravity architecture.
  /// Does NOT use LLM.
  Future<IntentType> detectIntent(String message, {List<Map<String, String>>? history, bool hasDocuments = false}) async {
    debugPrint("INTENT_DETECTION: Analyzing message: '$message'");
    final lowerMessage = message.trim().toLowerCase();

    // 1️⃣ Memory Store
    if (lowerMessage.startsWith("remember that") ||
        lowerMessage.startsWith("save this") ||
        lowerMessage.startsWith("note that")) {
      debugPrint("INTENT_DETECTION: Detected Memory Store trigger -> memoryStore");
      return IntentType.memoryStore;
    }

    // 2️⃣ Memory Retrieve
    if (lowerMessage.contains("what did i say") ||
        lowerMessage.contains("when is my") ||
        lowerMessage.contains("what is my") ||
        lowerMessage.contains("do you remember") ||
        lowerMessage.contains("recall")) {
      debugPrint("INTENT_DETECTION: Detected Memory Retrieval keywords -> memoryRetrieve");
      return IntentType.memoryRetrieve;
    }

    // 3️⃣ App Control / Device Actions
    if (lowerMessage.startsWith("open ") || lowerMessage.startsWith("launch ")) {
       if (lowerMessage.contains("settings")) return IntentType.openSettings;
       if (lowerMessage.contains("camera")) return IntentType.openCamera;
       return IntentType.openApp;
    }

    if (lowerMessage.startsWith("close ") || lowerMessage.startsWith("kill ")) {
      return IntentType.closeApp;
    }

    if (lowerMessage.contains("open settings") || 
        lowerMessage.contains("wifi settings") || 
        lowerMessage.contains("bluetooth settings")) {
      return IntentType.openSettings;
    }

    if (lowerMessage.contains("open camera") || lowerMessage.contains("take a photo")) {
      return IntentType.openCamera;
    }

    if (lowerMessage.startsWith("call ") || lowerMessage.startsWith("dial ")) {
      return IntentType.dialContact;
    }

    if (lowerMessage.startsWith("send sms") || 
        lowerMessage.startsWith("text ") || 
        lowerMessage.startsWith("message ")) {
      return IntentType.sendSMS;
    }

    // 4️⃣ Web Search (Explicit Commands & Keywords)
    final searchKeywords = RegExp(r'\b(search|research|lookup|browse|find)\b', caseSensitive: false);
    final contextKeywords = RegExp(r'\b(latest|news|who is|current|weather|whether|gold rate|price of)\b', caseSensitive: false);

    if (lowerMessage.startsWith("[search]") ||
        searchKeywords.hasMatch(lowerMessage) ||
        contextKeywords.hasMatch(lowerMessage)) {
      debugPrint("INTENT_DETECTION: Detected search keywords -> webSearch");
      return IntentType.webSearch;
    }

    // 5️⃣ URL Detection (Fallback for direct URL input)
    if (containsURL(message)) {
      debugPrint("INTENT_DETECTION: Detected URL -> urlScrape");
      return IntentType.urlScrape;
    }

    // 5️⃣ Default
    return IntentType.normalChat;
  }

  bool containsURL(String text) {
    // Matches http/https OR common domain patterns like domain.com
    final urlRegex = RegExp(
      r'((https?:\/\/)|(www\.)|([-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-z]{2,6}))[^\s]*',
      caseSensitive: false
    );
    return urlRegex.hasMatch(text);
  }

  /// Extracts the clean search query by stripping command words.
  String extractSearchQuery(String message) {
    String clean = message.trim();
    final lower = clean.toLowerCase();
    
    final commands = ["[search]", "search", "research", "lookup", "browse", "find"];
    for (final cmd in commands) {
      if (lower.startsWith(cmd)) {
        clean = clean.substring(cmd.length).trim();
        break;
      }
    }
    return clean.isEmpty ? message : clean;
  }

  /// Extracts the URL from a message, potentially stripping "search" or "analyze"
  String extractUrl(String message) {
    final urlRegex = RegExp(
      r'((https?:\/\/)|(www\.)|([-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-z]{2,6}))[^\s]*',
      caseSensitive: false
    );
    final match = urlRegex.firstMatch(message);
    return match?.group(0) ?? message;
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
    if (lowerMessage.startsWith("note that")) {
      return message.substring("note that".length).trim();
    }
    return message;
  }
  String extractAppName(String message) {
    String clean = message.trim();
    final lower = clean.toLowerCase();
    
    final commands = ["open ", "launch ", "close ", "kill "];
    for (final cmd in commands) {
      if (lower.startsWith(cmd)) {
        return clean.substring(cmd.length).trim();
      }
    }
    return clean;
  }

  String extractSettingsType(String message) {
    final lower = message.toLowerCase();
    if (lower.contains("wifi")) return "wifi";
    if (lower.contains("bluetooth")) return "bluetooth";
    return "general";
  }

  String extractContactName(String message) {
    String clean = message.trim();
    final lower = clean.toLowerCase();
    
    final commands = ["call ", "dial "];
    for (final cmd in commands) {
      if (lower.startsWith(cmd)) {
        return clean.substring(cmd.length).trim();
      }
    }
    return clean;
  }

  Map<String, String> extractSMSDetails(String message) {
    String clean = message.trim();
    // formats: 
    // "Send SMS to [Name] saying [Message]"
    // "Text [Name] [Message]"
    // "Message [Name] [Message]"
    
    // Simple parsing for "to X saying Y" pattern which is most natural
    final lower = clean.toLowerCase();
    
    String name = "";
    String body = "";

    if (lower.contains(" to ") && lower.contains(" saying ")) {
      final toIndex = lower.indexOf(" to ");
      final sayingIndex = lower.indexOf(" saying ");
      
      if (toIndex != -1 && sayingIndex != -1 && sayingIndex > toIndex) {
        name = clean.substring(toIndex + 4, sayingIndex).trim();
        body = clean.substring(sayingIndex + 8).trim();
        return {'name': name, 'message': body};
      }
    }

    // Fallback: Check for start commands
    final commands = ["send sms to ", "text ", "message "];
    for (final cmd in commands) {
      if (lower.startsWith(cmd)) {
        String remaining = clean.substring(cmd.length).trim();
        // Assume first word is name, rest is message if no "saying"
        final parts = remaining.split(' ');
        if (parts.isNotEmpty) {
           name = parts.first;
           body = parts.skip(1).join(' ');
        }
        return {'name': name, 'message': body};
      }
    }

    return {'name': '', 'message': ''};
  }
}
