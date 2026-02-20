import 'package:flutter/foundation.dart';
import 'package:aura_mobile/core/services/app_control_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/core/services/web_service.dart';
import 'package:aura_mobile/domain/services/scraper_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/context_builder_service.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:aura_mobile/domain/services/memory_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final orchestratorServiceProvider = Provider((ref) => OrchestratorService(
  ref.watch(intentDetectionServiceProvider),
  ref.watch(memoryServiceProvider),
  ref.watch(contextBuilderServiceProvider),
  ref.watch(llmServiceProvider),
  ref.watch(webServiceProvider),
  ref.watch(scraperServiceProvider),
  ref.watch(appControlServiceProvider),
));

class OrchestratorService {
  final IntentDetectionService _intentService;
  final MemoryService _memoryService;
  final ContextBuilderService _contextBuilder;
  final LLMService _llmService;
  final WebService _webService;
  final ScraperService _scraperService;
  final AppControlService _appControlService;

  OrchestratorService(
    this._intentService,
    this._memoryService,
    this._contextBuilder,
    this._llmService,
    this._webService,
    this._scraperService,
    this._appControlService,
  );

  Stream<String> processMessage({
    required String message,
    required List<String> chatHistory,
    bool hasDocuments = false,
  }) async* {
    // 1. Intent Detection
    final intent = await _intentService.detectIntent(message, hasDocuments: hasDocuments);
    debugPrint("ORCHESTRATOR: Detected intent -> $intent");

    // 2. Routing
    switch (intent) {
      case IntentType.memoryStore:
        await _handleStoreMemory(message);
        yield "Memory saved in your local vault.";
        break;

      case IntentType.memoryRetrieve:
        yield* _handleMemoryRetrieve(message);
        break;

      case IntentType.webSearch:
        yield* _handleWebSearch(message);
        break;

      case IntentType.urlScrape:
        yield* _handleUrlScrape(message);
        break;

      case IntentType.openApp:
        final appName = _intentService.extractAppName(message);
        yield "🚀 **Opening $appName...**";
        await _appControlService.openApp(appName);
        break;

      case IntentType.closeApp:
        // Note: Android restricts closing other apps. This is a best-effort.
        final appName = _intentService.extractAppName(message);
        yield "⚠️ **Closing apps is restricted by Android security.**";
        await _appControlService.closeApp(appName);
        break;

      case IntentType.openSettings:
        final type = _intentService.extractSettingsType(message);
        yield "⚙️ **Opening ${type == 'general' ? 'Settings' : '$type Settings'}...**";
        await _appControlService.openSettings(type);
        break;

      case IntentType.openCamera:
        yield "📸 **Opening Camera...**";
        await _appControlService.openCamera();
        break;

      case IntentType.dialContact:
        final contactName = _intentService.extractContactName(message);
        final matches = await _appControlService.resolveContacts(contactName);

        if (matches.isEmpty) {
           // Fallback to old behavior (let dialer handle it or say not found)
           yield "📞 **Dialing $contactName...**";
           await _appControlService.dialContact(contactName);
        } else if (matches.length == 1) {
           final number = matches.first.phones.isNotEmpty ? matches.first.phones.first.number : '';
           if (number.isNotEmpty) {
             yield "📞 **Dialing ${matches.first.displayName}...**";
             await _appControlService.dialContact(number);
           } else {
             yield "❌ Contact ${matches.first.displayName} has no phone number.";
           }
        } else {
           // Multiple matches
           final options = matches.take(5).map((c) {
              final number = c.phones.isNotEmpty ? c.phones.first.number : '';
              return "${c.displayName}|Call $number"; 
           }).join(",");
           yield "I found multiple contacts for '$contactName'. Who did you mean? [[OPTIONS:$options]]";
        }
        break;

      case IntentType.sendSMS:
        final details = _intentService.extractSMSDetails(message);
        final name = details['name'] ?? '';
        final body = details['message'] ?? '';
        
        if (name.isNotEmpty) {
           final matches = await _appControlService.resolveContacts(name);
           
           if (matches.isEmpty) {
              yield "📨 **Opening SMS to $name...**";
              await _appControlService.sendSMS(name, body);
           } else if (matches.length == 1) {
              final number = matches.first.phones.isNotEmpty ? matches.first.phones.first.number : '';
              if (number.isNotEmpty) {
                 yield "📨 **Opening SMS to ${matches.first.displayName}...**\nMessage: \"$body\"";
                 await _appControlService.sendSMS(number, body);
              } else {
                 yield "❌ Contact ${matches.first.displayName} has no phone number.";
              }
           } else {
              // Multiple matches
              final options = matches.take(5).map((c) {
                 final number = c.phones.isNotEmpty ? c.phones.first.number : '';
                 return "${c.displayName}|Text $number $body";
              }).join(",");
              yield "I found multiple contacts for '$name'. Who did you mean? [[OPTIONS:$options]]";
           }
        } else {
           yield "❌ I couldn't understand who to send the message to. Please try 'Send SMS to [Name] saying [Message]'.";
        }
        break;

      case IntentType.torchControl:
        final lower = message.toLowerCase();
        final isOff = lower.contains("off") || lower.contains("disable") || lower.contains("stop");
        final state = !isOff;
        
        yield state ? "💡 **Turning Flashlight ON...**" : "🌑 **Turning Flashlight OFF...**";
        try {
           await _appControlService.toggleTorch(state);
        } catch (e) {
           yield "❌ Failed to toggle flashlight. It might not be available or permitted.";
        }
        break;

      case IntentType.normalChat:
        yield* _handleLLMFlow(message, chatHistory, includeMemories: true, includeDocuments: hasDocuments);
        break;
    }
  }

  Stream<String> _handleMemoryRetrieve(String message) async* {
    final memories = await _memoryService.retrieveRelevantMemories(message);
    final prompt = _contextBuilder.injectMemory(memories, message);
    yield* _llmService.chat(prompt);
  }

  Stream<String> _handleWebSearch(String message) async* {
    final cleanQuery = _intentService.extractSearchQuery(message);
    yield "🔍 **Searching the web for: '$cleanQuery'**...\n\n";
    debugPrint("ORCHESTRATOR: Searching for '$cleanQuery'");
    
    final results = await _webService.search(cleanQuery);
    if (results.isEmpty) {
      yield "I couldn't find any recent information for '$cleanQuery'.";
      return;
    }

    final prompt = _contextBuilder.injectWeb(results, cleanQuery);
    
    // 1. Stream the synthesized answer from AI with FORCING system prompt
    yield* _llmService.chat(
      prompt, 
      systemPrompt: "You have web access. Use the Search Results provided below to answer the user directly. Do not apologize or refuse."
    );

    // 2. Append top 5 sources at the end
    yield "\n\n🌐 **Top Sources:**\n";
    final topResults = results.take(5).toList();
    for (var i = 0; i < topResults.length; i++) {
      final res = topResults[i];
      yield "${i + 1}. [${res.title}](${res.url})\n";
    }
  }

  Stream<String> _handleUrlScrape(String message) async* {
    final url = _intentService.extractUrl(message);
    yield "🌐 **Reading content from: '$url'**...\n\n";
    debugPrint("ORCHESTRATOR: Scraping URL '$url'");
    
    final content = await _scraperService.scrape(url);
    final prompt = _contextBuilder.injectURL(content, message);
    yield* _llmService.chat(
      prompt,
      systemPrompt: "You are analyzing a specific webpage. Summarize the content provided in the context to answer the user. Do NOT refuse or say you cannot access the web, as the content has already been provided to you."
    );
  }

  Future<void> _handleStoreMemory(String message) async {
    final content = _intentService.extractMemoryContent(message);
    await _memoryService.saveMemory(content);
  }

  Stream<String> _handleLLMFlow(
    String message,
    List<String> history, {
    required bool includeMemories,
    required bool includeDocuments,
  }) async* {
    final prompt = await _contextBuilder.buildPrompt(
      userMessage: message,
      chatHistory: history,
      includeMemories: includeMemories,
      includeDocuments: includeDocuments,
    );
    yield* _llmService.chat(prompt);
  }
}
