import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'package:aura_mobile/core/services/app_control_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/core/services/web_service.dart';
import 'package:aura_mobile/domain/services/scraper_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/context_builder_service.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:aura_mobile/domain/services/llm_intent_classifier.dart';
import 'package:aura_mobile/domain/services/memory_service.dart';
import 'package:aura_mobile/domain/services/date_time_parser.dart';

final orchestratorServiceProvider = Provider((ref) => OrchestratorService(
  ref.watch(intentDetectionServiceProvider),
  ref.watch(memoryServiceProvider),
  ref.watch(contextBuilderServiceProvider),
  ref.watch(llmServiceProvider),
  ref.watch(webServiceProvider),
  ref.watch(scraperServiceProvider),
  ref.watch(appControlServiceProvider),
  ref.watch(llmIntentClassifierProvider),
));

class OrchestratorService {
  final IntentDetectionService _intentService;
  final MemoryService _memoryService;
  final ContextBuilderService _contextBuilder;
  final LLMService _llmService;
  final WebService _webService;
  final ScraperService _scraperService;
  final AppControlService _appControlService;
  final LLMIntentClassifier _llmClassifier;

  OrchestratorService(
    this._intentService,
    this._memoryService,
    this._contextBuilder,
    this._llmService,
    this._webService,
    this._scraperService,
    this._appControlService,
    this._llmClassifier,
  );

  /// Process a message through intent detection and routing.
  /// [isVoiceQuery] skips the LLM classifier to avoid double inference + timeout.
  /// [forceNormalChat] bypasses ALL intent detection and goes straight to LLM.
  Stream<String> processMessage({
    required String message,
    required List<String> chatHistory,
    bool hasDocuments = false,
    bool isVoiceQuery = false,
    bool forceNormalChat = false,
  }) async* {
    // If forced to chat (e.g. email draft prompt), skip all intent detection
    if (forceNormalChat) {
      yield* _handleLLMFlow(message, chatHistory, includeMemories: true, includeDocuments: hasDocuments);
      return;
    }

    // 1. Rule-based Intent Detection (Layer 1)
    var intent = await _intentService.detectIntent(message, hasDocuments: hasDocuments);
    debugPrint("ORCHESTRATOR: Rule-based intent -> $intent");

    // 2. LLM Fallback Classification (Layer 2) — only for chat UI, not voice
    // Voice queries already went through CommandParser; running classifier + chat
    // would cause two LLM inferences and risk hitting the 30s voice timeout.
    ClassifiedIntent? classifiedIntent;
    if (intent == IntentType.normalChat && !isVoiceQuery) {
      classifiedIntent = await _llmClassifier.classify(message);
      if (classifiedIntent != null && classifiedIntent.type != IntentType.normalChat) {
        debugPrint("ORCHESTRATOR: LLM classified intent -> ${classifiedIntent.type} params=${classifiedIntent.params}");
        intent = classifiedIntent.type;
      }
    }


    // 3. Routing
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

      case IntentType.emailDraft:
        yield* _handleEmailDraft(message);
        break;

      case IntentType.reminderSet:
        yield* _handleReminderSet(message);
        break;

      case IntentType.openApp:
        final appName = classifiedIntent?.params['appName'] ?? _intentService.extractAppName(message);
        yield "🚀 **Opening $appName...**";
        await _appControlService.openApp(appName);
        break;

      case IntentType.closeApp:
        final appName = _intentService.extractAppName(message);
        yield "⚠️ **Closing apps is restricted by Android security.**";
        await _appControlService.closeApp(appName);
        break;

      case IntentType.openSettings:
        final type = classifiedIntent?.params['type'] ?? _intentService.extractSettingsType(message);
        yield "⚙️ **Opening ${type == 'general' ? 'Settings' : '$type Settings'}...**";
        await _appControlService.openSettings(type);
        break;

      case IntentType.openCamera:
        yield "📸 **Opening Camera...**";
        await _appControlService.openCamera();
        break;

      case IntentType.dialContact:
        final contactName = classifiedIntent?.params['contactName'] ?? _intentService.extractContactName(message);
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
        final name = classifiedIntent?.params['name'] ?? details['name'] ?? '';
        var smsBody = classifiedIntent?.params['message'] ?? details['message'] ?? '';

        // AI message enhancement: if the body looks like an instruction, compose it
        if (smsBody.isNotEmpty && _llmService.isModelLoaded) {
          smsBody = await _enhanceSMSBody(smsBody, name);
        }

        if (name.isNotEmpty) {
           final matches = await _appControlService.resolveContacts(name);

           if (matches.isEmpty) {
              yield '📨 **Opening SMS to $name...**${smsBody.isNotEmpty ? '\nMessage: "$smsBody"' : ''}';
              await _appControlService.sendSMS(name, smsBody);
           } else if (matches.length == 1) {
              final number = matches.first.phones.isNotEmpty ? matches.first.phones.first.number : '';
              if (number.isNotEmpty) {
                 yield '📨 **Opening SMS to ${matches.first.displayName}...**${smsBody.isNotEmpty ? '\nMessage: "$smsBody"' : ''}';
                 await _appControlService.sendSMS(number, smsBody);
              } else {
                 yield "❌ Contact ${matches.first.displayName} has no phone number.";
              }
           } else {
              final options = matches.take(5).map((c) {
                 final number = c.phones.isNotEmpty ? c.phones.first.number : '';
                 return "${c.displayName}|Text $number $smsBody";
              }).join(",");
              yield "I found multiple contacts for '$name'. Who did you mean? [[OPTIONS:$options]]";
           }
        } else {
           yield "❌ I couldn't understand who to send the message to. Please try 'Send SMS to [Name] saying [Message]'.";
        }
        break;

      case IntentType.torchControl:
        final lower = message.toLowerCase();
        final bool state;
        if (classifiedIntent?.params['state'] != null) {
          state = classifiedIntent!.params['state'] != 'off';
        } else {
          final isOff = lower.contains("off") || lower.contains("disable") || lower.contains("stop");
          state = !isOff;
        }
        
        yield state ? "💡 **Turning Flashlight ON...**" : "🌑 **Turning Flashlight OFF...**";
        try {
           await _appControlService.toggleTorch(state);
        } catch (e) {
           yield "❌ Failed to toggle flashlight. It might not be available or permitted.";
        }
        break;

      case IntentType.navigation:
        final destination = classifiedIntent?.params['destination'] ?? _intentService.extractNavigationDestination(message);
        yield "🗺️ **Getting directions to $destination...**";
        await _appControlService.openApp("navigate:$destination"); 
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

  Stream<String> _handleEmailDraft(String message) async* {
    final address = _intentService.extractEmailAddress(message) ?? 'the recipient';
    final topic = _intentService.extractEmailTopic(message, address);
    final topicText = topic.isNotEmpty ? topic : 'the discussed topic';

    debugPrint('ORCHESTRATOR: Drafting email to $address about "$topicText"');

    // Magic marker: chat_provider intercepts this and inserts the system message.
    // It is NEVER shown to the user.
    yield '__EMAIL_DRAFT__:$address\n';

    // Clean, simple prompt — no formatting instructions leak to the UI
    final prompt =
        'Write a professional email to $address about: $topicText.\n'
        'Reply ONLY in this exact format — no extra commentary:\n\n'
        'Subject: [one short subject line]\n\n'
        '[email body paragraphs]\n\n'
        'Regards,\nAura User';

    yield* _llmService.chat(
      prompt,
      systemPrompt:
          'You are a professional email writing assistant. '
          'Write clear, concise, well-structured emails. '
          'Never use placeholder text in square brackets in your output. '
          'Always write real content.',
    );
  }

  Future<void> _handleStoreMemory(String message) async {
    final content = _intentService.extractMemoryContent(message);
    await _memoryService.saveMemory(content);
  }

  /// Checks if the SMS body is an instruction rather than a direct message,
  /// and if so, uses the LLM to compose a proper SMS text.
  Future<String> _enhanceSMSBody(String body, String recipientName) async {
    // Heuristic: if the body contains instruction-like words, enhance it
    final lower = body.toLowerCase();
    final instructionPatterns = RegExp(
      r'\b(tell|say|ask|inform|let .* know|remind|compose|write|convey|mention|apologize|thank|congratulate|invite|request)\b',
      caseSensitive: false,
    );

    if (!instructionPatterns.hasMatch(lower)) {
      // Body looks like a direct message, send as-is
      return body;
    }

    try {
      debugPrint("ORCHESTRATOR: Enhancing SMS body via AI: '$body'");
      final buffer = StringBuffer();
      await for (final token in _llmService.chat(
        'Compose a short, friendly SMS message for the following instruction. '
        'Recipient: $recipientName. Instruction: "$body". '
        'Reply with ONLY the message text, nothing else.',
        systemPrompt: 'You compose short SMS messages. Reply with only the message text. Keep it under 160 characters when possible. Be natural and friendly.',
        maxTokens: 60,
      )) {
        buffer.write(token);
      }
      final enhanced = buffer.toString().trim();
      if (enhanced.isNotEmpty) {
        debugPrint("ORCHESTRATOR: Enhanced SMS: '$enhanced'");
        return enhanced;
      }
    } catch (e) {
      debugPrint("ORCHESTRATOR: SMS enhancement failed: $e");
    }
    return body;
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

  // ── Smart Reminder Handler ──
  Stream<String> _handleReminderSet(String message) async* {
    yield "⏰ **Scheduling reminder...**\n";

    final now = DateTime.now();
    final DateTimeParser parser = DateTimeParser();
    final scheduledTime = parser.parseReminderTime(message);

    if (scheduledTime == null || scheduledTime.isBefore(now)) {
      yield "I couldn't understand the exact future time for that reminder. Could you specify it clearly (e.g., 'remind me at 6:45 PM')?";
      return;
    }

    // Extract Title using Regex removals
    var title = message;
    final removals = [
      r'remind\s+(me|us)\s+(to|on|at|about)?',
      r'notify\s+(me|us)\s+(to|on|at|about)?',
      r'set\s+a\s+reminder\s+(to|on|at|about)?',
      r'schedule\s+a\s+reminder\s+(to|on|at|about)?',
      r'in\s+\d+\s*(min|minute|minutes|hr|hour|hours|day|days)\b',
      r'\b(at|on)\s*(1[0-2]|0?[1-9]|2[0-3])(?::([0-5][0-9]))?\s*(am|pm)?\b',
      r'\b(1[0-2]|0?[1-9]|2[0-3])(?::([0-5][0-9]))?\s*(am|pm)?\b',
      r'\btomorrow\b',
      r'\btoday\b',
      r'\bnext\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
      r'\b(\d{1,2})[-/](\d{1,2})(?:[-/](\d{2,4}))?\b',
      r'\b(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})\b',
      r'\b(\d{1,2})\s+(january|february|march|april|may|june|july|august|september|october|november|december)\b',
    ];

    for (var r in removals) {
      title = title.replaceAll(RegExp(r, caseSensitive: false), '');
    }
    title = title.trim();
    if (title.isEmpty) title = "Reminder";

    // Schedule seamlessly
    try {
      final timeInMillis = scheduledTime.millisecondsSinceEpoch;
      final channel = MethodChannel('com.aura.ai/app_control'); 
      await channel.invokeMethod('scheduleReminder', {
        'title': title,
        'description': '',
        'timeInMillis': timeInMillis,
        'preReminderEnabled': true
      });

      final hour = scheduledTime.hour % 12 == 0 ? 12 : scheduledTime.hour % 12;
      final minute = scheduledTime.minute.toString().padLeft(2, '0');
      final amPm = scheduledTime.hour < 12 ? 'AM' : 'PM';
      final now2 = DateTime.now();
      final isToday = scheduledTime.day == now2.day && scheduledTime.month == now2.month;
      final isTomorrow = scheduledTime.day == now2.day + 1 && scheduledTime.month == now2.month;
      final dayStr = isToday ? 'today' : isTomorrow ? 'tomorrow' : '${scheduledTime.day}/${scheduledTime.month}';
      yield "✅ Got it! I'll remind you to **$title** $dayStr at **$hour:$minute $amPm**.";

    } catch (e) {
      debugPrint("Failed to set native reminder: $e");
      yield "Sorry, an error occurred while scheduling the reminder on your device.";
    }
  }
}
