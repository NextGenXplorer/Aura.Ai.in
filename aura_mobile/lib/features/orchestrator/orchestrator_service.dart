import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'package:aura_mobile/core/services/app_control_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/core/providers/workflow_providers.dart';
import 'package:aura_mobile/core/services/web_service.dart';
import 'package:aura_mobile/domain/services/scraper_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/context_builder_service.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:aura_mobile/domain/services/memory_service.dart';
import 'package:aura_mobile/domain/services/date_time_parser.dart';
import 'package:aura_mobile/domain/services/workflow_splitter_service.dart';
import 'package:aura_mobile/domain/services/workflow_engine_service.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';
import 'package:aura_mobile/domain/services/study_service.dart';
import 'package:aura_mobile/core/services/smart_app_actions_service.dart';
import 'package:aura_mobile/features/orchestrator/tool_definition.dart';
import 'package:aura_mobile/features/orchestrator/function_call_coordinator.dart';
import 'package:aura_mobile/data/datasources/image_generation_service.dart';
import 'package:aura_mobile/features/document_gen/document_generation_service.dart';
import 'package:aura_mobile/core/services/connector_services.dart';
import 'package:aura_mobile/core/services/connectors_service.dart';

final orchestratorServiceProvider = Provider((ref) {
  final orchestrator = OrchestratorService(
    ref.watch(intentDetectionServiceProvider),
    ref.watch(memoryServiceProvider),
    ref.watch(contextBuilderServiceProvider),
    ref.watch(llmServiceProvider),
    ref.watch(webServiceProvider),
    ref.watch(scraperServiceProvider),
    ref.watch(appControlServiceProvider),
    ref.watch(workflowSplitterServiceProvider),
    ref.watch(studyServiceProvider),
    ref.watch(smartAppActionsProvider),
  );
  // WorkflowEngine is constructed here to avoid a Riverpod circular dependency.
  // It receives processMessage as a function reference rather than the whole service.
  orchestrator.attachWorkflowEngine(ref.watch(llmServiceProvider));
  return orchestrator;
});

class OrchestratorService {
  final IntentDetectionService _intentService;
  final MemoryService _memoryService;
  final ContextBuilderService _contextBuilder;
  final LLMService _llmService;
  final WebService _webService;
  final ScraperService _scraperService;
  final AppControlService _appControlService;
  final WorkflowSplitterService _workflowSplitter;
  final StudyService _studyService;
  final SmartAppActionsService _smartAppActions;
  final ErrorHandlerService _errorHandler = ErrorHandlerService();
  WorkflowEngineService? _workflowEngine;

  // Response-style hints are passed per request into _handleLLMFlow so
  // overlapping turns (voice overlay + text chat) never overwrite each other.

  /// Free online text-to-image generation (Pollinations.ai, no key). Stateless,
  /// so it is constructed directly rather than injected.
  final ImageGenerationService _imageGen = ImageGenerationService();

  /// The tool-definition set provided to tool-calling-capable models on each
  /// inference call (Requirement 5.1). Each definition maps a tool name to one
  /// of the orchestrator's existing handlers (memory, web search, app control,
  /// etc.).
  final List<ToolDefinition> _toolDefinitions = _buildToolDefinitions();

  /// Parses and validates a tool-calling model's function-call emissions into
  /// dispatchable requests (Requirements 5.2, 5.5, 5.6, 5.7).
  late final FunctionCallCoordinator _functionCallCoordinator =
      FunctionCallCoordinator.fromDefinitions(_toolDefinitions);

  OrchestratorService(
    this._intentService,
    this._memoryService,
    this._contextBuilder,
    this._llmService,
    this._webService,
    this._scraperService,
    this._appControlService,
    this._workflowSplitter,
    this._studyService,
    this._smartAppActions,
  );

  /// Attaches the workflow engine and dependency-injects the processing function.
  void attachWorkflowEngine(LLMService llmService) {
    _workflowEngine = WorkflowEngineService(processMessage, llmService);
    debugPrint('ORCHESTRATOR: WorkflowEngine attached');
  }

  /// Process a message through intent detection and routing.
  /// [isVoiceQuery] skips the LLM classifier to avoid double inference + timeout.
  /// [forceNormalChat] bypasses ALL intent detection and goes straight to LLM.
  /// [isConcise] tells the LLM to keep responses short (passed as system hint,
  /// NOT injected into the message text — avoids polluting intent detection).
  /// [isVoice] tells the LLM to be conversational and brief for TTS.
  Stream<String> processMessage({
    required String message,
    required List<String> chatHistory,
    bool hasDocuments = false,
    bool isVoiceQuery = false,
    bool forceNormalChat = false,
    bool isConcise = false,
    bool isVoice = false,
  }) async* {
    // Per-request response-style hints, applied via the system prompt only.
    final voiceStyle = isVoice;
    final conciseStyle = isConcise;
    // Sync model tier to context builder so prompts adapt to model size
    _contextBuilder.modelTier = _llmService.modelTier;
    // If forced to chat (e.g. email draft prompt), skip all intent detection
    if (forceNormalChat) {
      yield* _handleLLMFlow(
        message,
        chatHistory,
        includeMemories: true,
        includeDocuments: hasDocuments,
        voice: voiceStyle,
        concise: conciseStyle,
      );
      return;
    }

    // 0a. Image generation (works for ALL models, online & free via Pollinations).
    // "draw a cat", "generate an image of a sunset", etc. The generated image is
    // a URL rendered inline by the chat bubble's markdown image support.
    if (!forceNormalChat) {
      final imgPrompt = ImageGenerationService.extractImagePrompt(message);
      if (imgPrompt != null) {
        debugPrint('ORCHESTRATOR: Image generation request -> "$imgPrompt"');
        yield '🎨 Generating an image of "$imgPrompt"...\n\n';
        yield _imageGen.buildChatImageMarkdown(imgPrompt);
        return;
      }
    }

    // 0. Native function calling (Layer 0) — only for tool-calling-capable models.
    //
    // When the active model exposes native function calling (Req 5.4), the model
    // itself decides which tool to invoke, so we provide it the full tool
    // definition set on the inference call (Req 5.1), then parse/validate/dispatch
    // its emission to the same handlers the rule-based path uses (Req 5.3).
    // Non-tool-calling models fall through to the existing rule-based detection
    // below (Req 2.5, 5.4).
    if (_llmService.supportsToolCalling) {
      // Fast-path guard: trivially short messages, greetings, and general questions
      // should NEVER go through the tool-calling prompt — small models hallucinate
      // tool calls. Route them straight to the normal chat flow.
      final msgTrimmed = message.trim();
      final msgLower = msgTrimmed.toLowerCase();
      final _greetGuard = RegExp(
        r'^(hi+|hey+|hello+|hai|heyy+|hyy*|yo+|sup|howdy|greetings|namaste|'
        r'good\s*(morning|afternoon|evening|night)|whats\s*up|'
        r'how\s+are\s+you|how\s+r\s+u|hows\s+it\s+going|thanks|thank\s+you|'
        r'ok|okay|bye|gm|gn|hola|bonjour|ciao)\s*[!?.]*$',
        caseSensitive: false,
      );
      final words = msgLower
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();

      // Skip tool-calling for:
      // 1. Greetings
      // 2. Short messages (≤3 words) without device-action keywords
      // 3. Questions/conversational messages (starts with can/what/how/why/tell/explain/help etc.)
      final isDeviceAction = RegExp(
        r'\b(torch|flashlight|camera|photo|selfie|call|dial|sms|text|'
        r'email|mail|search|open|launch|remember|recall|settings|wifi|bluetooth|'
        r'navigate|directions|remind|alarm|timer|play|spotify|whatsapp|upi|pay|'
        r'book\s+(uber|ola|ride|cab)|order\s+food)\b',
        caseSensitive: false,
      ).hasMatch(msgLower);

      final isConversational = RegExp(
        r'^(can\s+you|could\s+you|would\s+you|please|help|tell\s+me|explain|'
        r'what\s+(is|are|was|were|do|does|did|about|should|would|can)|'
        r'how\s+(to|do|does|can|should|would|is|are|much|many)|'
        r'why\s+(is|are|do|does|did|should|would|can)|'
        r'who\s+(is|was|are)|where\s+(is|are|can|do)|when\s+(is|was|did|does)|'
        r'is\s+(it|there|this|that)|are\s+(there|you)|do\s+you|'
        r'give\s+me|show\s+me|write|create|generate|list|suggest|recommend)',
        caseSensitive: false,
      ).hasMatch(msgLower);

      if (_greetGuard.hasMatch(msgLower) ||
          (words.length <= 3 && !isDeviceAction) ||
          (isConversational && !isDeviceAction)) {
        yield* _handleLLMFlow(
          message,
          chatHistory,
          includeMemories: true,
          includeDocuments: hasDocuments,
          voice: voiceStyle,
          concise: conciseStyle,
        );
        return;
      }
      yield* _handleFunctionCalling(
        message,
        chatHistory,
        hasDocuments: hasDocuments,
      );
      return;
    }

    // 1. Check for compound multi-intent commands (Workflow Engine)
    if (!isVoiceQuery && !forceNormalChat) {
      try {
        final plan = await _workflowSplitter.splitWorkflow(message);
        if (plan != null && _workflowEngine != null) {
          debugPrint(
            'ORCHESTRATOR: Handing off compound command to Workflow Engine',
          );
          await for (final chunk in _workflowEngine!.execute(
            plan,
            chatHistory,
          )) {
            yield chunk;
          }
          return;
        }
      } catch (e) {
        // Workflow splitting/validation failed — fall through to normal intent
        // detection instead of showing a raw error to the user.
        debugPrint('ORCHESTRATOR: Workflow split failed, falling through: $e');
      }
    }

    // 1. Rule-based Intent Detection (Layer 1)
    var intent = await _intentService.detectIntent(
      message,
      hasDocuments: hasDocuments,
    );
    debugPrint("ORCHESTRATOR: Rule-based intent -> $intent");

    // 2. LLM Fallback Classification (Layer 2) is intentionally absent.
    //
    // The on-device engine exposes a single inference context, so running a
    // classifier here consumed the context the follow-up chat() call needs.
    // Rule-based detection (Layer 1) covers the supported intents, and
    // anything it cannot classify goes to normalChat. Parameter extraction
    // therefore comes from IntentDetectionService, not from a classifier.
    //
    // 3. Routing
    switch (intent) {
      case IntentType.memoryStore:
        try {
          await _handleStoreMemory(message);
          yield "✅ Memory saved in your local vault.";
        } catch (e) {
          final errorMsg = _errorHandler.handleError(e);
          yield "❌ Failed to save memory: $errorMsg";
        }
        break;

      case IntentType.memoryRetrieve:
        try {
          yield* _handleMemoryRetrieve(message);
        } catch (e) {
          final errorMsg = _errorHandler.handleError(e);
          yield "❌ Failed to retrieve memories: $errorMsg";
        }
        break;

      case IntentType.webSearch:
        // Search results are synthesized into an answer for both typed and
        // spoken requests. Opening a browser is reserved for explicit app/URL
        // navigation, so a search request never dismisses chat unexpectedly.
        yield* _handleWebSearch(message, voice: voiceStyle);
        break;

      case IntentType.urlScrape:
        try {
          yield* _handleUrlScrape(message);
        } catch (e) {
          final errorMsg = _errorHandler.handleError(e);
          yield "❌ Failed to read webpage: $errorMsg";
        }
        break;

      case IntentType.emailDraft:
        yield* _handleEmailDraft(message);
        break;

      case IntentType.reminderSet:
        yield* _handleReminderSet(message);
        break;

      case IntentType.openApp:
        final appName = _intentService.extractAppName(message);
        yield "Opening $appName";
        await _appControlService.openApp(appName);
        yield "__DISMISS__";
        break;

      case IntentType.closeApp:
        yield "⚠️ Android does not allow Aura to force-close other apps. No app was closed.";
        break;

      case IntentType.openSettings:
        final type = _intentService.extractSettingsType(message);
        yield "⚙️ **Opening ${type == 'general' ? 'Settings' : '$type Settings'}...**";
        await _appControlService.openSettings(type);
        break;

      case IntentType.openCamera:
        yield "Opening Camera";
        await _appControlService.openCamera();
        yield "__DISMISS__";
        break;

      case IntentType.dialContact:
        final contactName = _intentService.extractContactName(message);
        final matches = await _appControlService.resolveContacts(contactName);

        if (matches.isEmpty) {
          yield "Couldn't find a contact named $contactName. Try again with the exact name.";
        } else if (matches.length == 1) {
          final number = matches.first.phones.isNotEmpty
              ? matches.first.phones.first.number
              : '';
          if (number.isNotEmpty) {
            yield "Calling ${matches.first.displayName}";
            await _appControlService.dialContact(number);
            yield "__DISMISS__";
          } else {
            yield "Contact ${matches.first.displayName} has no phone number.";
          }
        } else {
          // Multiple matches — give voice-friendly numbered list
          final names = matches.take(5).toList();
          final nameList = names
              .asMap()
              .entries
              .map((e) => "${e.key + 1}. ${e.value.displayName}")
              .join(", ");
          yield "I found ${names.length} contacts similar to $contactName: $nameList. Say the number or tap to select. [[OPTIONS:${names.map((c) {
            final number = c.phones.isNotEmpty ? c.phones.first.number : '';
            return "${c.displayName}|call $number";
          }).join(",")}]]";
        }
        break;

      case IntentType.sendSMS:
        final details = _intentService.extractSMSDetails(message);
        final name = details['name'] ?? '';
        var smsBody = details['message'] ?? '';

        // AI message enhancement: if the body looks like an instruction, compose it
        if (smsBody.isNotEmpty && _llmService.isModelLoaded) {
          smsBody = await _enhanceSMSBody(smsBody, name);
        }

        if (name.isNotEmpty) {
          final matches = await _appControlService.resolveContacts(name);

          if (matches.isEmpty) {
            yield "Opening SMS to $name${smsBody.isNotEmpty ? ' with message: $smsBody' : ''}";
            await _appControlService.sendSMS(name, smsBody);
            yield "__DISMISS__";
          } else if (matches.length == 1) {
            final number = matches.first.phones.isNotEmpty
                ? matches.first.phones.first.number
                : '';
            if (number.isNotEmpty) {
              yield "Sending SMS to ${matches.first.displayName}${smsBody.isNotEmpty ? ': $smsBody' : ''}";
              await _appControlService.sendSMS(number, smsBody);
              yield "__DISMISS__";
            } else {
              yield "Contact ${matches.first.displayName} has no phone number.";
            }
          } else {
            // Multiple matches — voice-friendly numbered list
            final names = matches.take(5).toList();
            final nameList = names
                .asMap()
                .entries
                .map((e) => "${e.key + 1}. ${e.value.displayName}")
                .join(", ");
            yield "I found ${names.length} contacts similar to $name: $nameList. Say the number or tap to select. [[OPTIONS:${names.map((c) {
              final number = c.phones.isNotEmpty ? c.phones.first.number : '';
              return "${c.displayName}|text $number $smsBody";
            }).join(",")}]]";
          }
        } else {
          yield "I couldn't understand who to send the message to. Please try again with the contact name.";
        }
        break;

      case IntentType.torchControl:
        final lower = message.toLowerCase();
        final isOff =
            lower.contains("off") ||
            lower.contains("disable") ||
            lower.contains("stop");
        final state = !isOff;

        yield state
            ? "💡 **Turning Flashlight ON...**"
            : "🌑 **Turning Flashlight OFF...**";
        try {
          await _appControlService.toggleTorch(state);
        } catch (e) {
          yield "❌ Failed to toggle flashlight. It might not be available or permitted.";
        }
        break;

      case IntentType.navigation:
        final destination = _intentService.extractNavigationDestination(
          message,
        );
        yield "Getting directions to $destination";
        await _appControlService.openApp("navigate:$destination");
        yield "__DISMISS__";
        break;

      case IntentType.weatherSearch:
        try {
          final location = _extractWeatherLocation(message);
          yield '🌤️ Checking weather for **$location**...\n\n';
          final connectors = ConnectorsService();
          final weatherData = await connectors.getWeather(location);
          yield connectors.formatWeatherResponse(weatherData);
        } catch (e) {
          yield* _handleWebSearch("weather $message");
        }
        break;

      case IntentType.viewCalendar:
        yield "📅 **Opening Calendar...**";
        await _appControlService.openApp("calendar");
        break;

      case IntentType.createEvent:
        yield "📅 Aura can't create calendar events directly yet. Opening Calendar so you can add it safely.";
        await _appControlService.openApp("calendar");
        break;

      case IntentType.getNextEvent:
        yield "📅 Aura can't read your calendar events yet. Opening Calendar so you can check them.";
        await _appControlService.openApp("calendar");
        break;

      case IntentType.mediaControl:
        yield "🎵 Media playback controls aren't connected in this version yet.";
        break;

      case IntentType.setBrightness:
        yield "🔆 Aura can't change screen brightness yet. Use Android Quick Settings to adjust it.";
        break;

      case IntentType.screenshot:
        yield "📸 Aura can't capture screenshots yet. Use your phone's screenshot buttons or Quick Settings.";
        break;

      case IntentType.readMessages:
        yield "📬 Message reading isn't connected yet, so Aura did not access or read any messages.";
        break;

      case IntentType.readNotifications:
        yield "🔔 Notification reading isn't connected to chat yet, so Aura did not read any notifications.";
        break;

      case IntentType.createNote:
        yield "📝 A notes integration isn't available yet. You can say ‘remember that …’ to save something privately in Aura's local memory.";
        break;

      case IntentType.calculate:
        final expression = message;
        yield "🧮 **Calculating: $expression**";
        yield* _handleLLMFlow(
          "Calculate: $expression",
          chatHistory,
          includeMemories: false,
          includeDocuments: false,
          voice: voiceStyle,
          concise: conciseStyle,
        );
        break;

      case IntentType.convert:
        yield* _handleLLMFlow(
          "Convert: $message",
          chatHistory,
          includeMemories: false,
          includeDocuments: false,
          voice: voiceStyle,
          concise: conciseStyle,
        );
        break;

      // ── Camera / OCR Scan ──────────────────────────────────────────────────
      case IntentType.scanImage:
        yield "📷 **Opening Scanner...**\n\nUse the camera or gallery to capture text from images!";
        yield "__NAVIGATE__:camera_scan";
        break;

      // ── Study Buddy Intents ───────────────────────────────────────────────
      case IntentType.studyCreateFlashcards:
        yield* _handleStudyCreateFlashcards(message);
        break;

      case IntentType.studyQuizMe:
        yield "🧠 **Opening Quiz Mode...**\n\nOpen **Study Buddy** from the sidebar to select a deck and start a quiz!";
        yield "__NAVIGATE__:study_dashboard";
        break;

      case IntentType.studyReviewCards:
        yield "📚 **Opening Flashcard Review...**\n\nOpen **Study Buddy** from the sidebar to review your due cards!";
        yield "__NAVIGATE__:study_dashboard";
        break;

      case IntentType.studyShowStats:
        yield "📊 **Opening Study Stats...**\n\nOpen **Study Buddy** from the sidebar to see your progress!";
        yield "__NAVIGATE__:study_dashboard";
        break;

      case IntentType.studyScheduleExam:
        yield* _handleStudyScheduleExam(message);
        break;

      case IntentType.studyOpenDashboard:
        yield "📚 **Opening Study Buddy...**";
        yield "__NAVIGATE__:study_dashboard";
        break;

      // ═══ SMART APP ACTIONS ═══

      case IntentType.sendWhatsApp:
        final contact = _extractWhatsAppContact(message);
        final msg = _extractWhatsAppMessage(message);
        if (contact.isEmpty) {
          yield "Who should I message on WhatsApp? Try: WhatsApp Priya saying I'm running late.";
          break;
        }
        // Deep links prefill the chat; the user still taps send.
        yield "Opening WhatsApp for **$contact** with the message ready to send...";
        try {
          await _smartAppActions.sendWhatsApp(contact, msg);
        } catch (e) {
          yield "Failed to open WhatsApp: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.searchOnApp:
        final searchQuery = _intentService.extractSearchQuery(message);
        yield "Searching the web for **$searchQuery** instead — in-app search targets aren't detected reliably yet.\n\n";
        yield* _handleWebSearch(message, voice: voiceStyle);
        break;

      case IntentType.upiPayment:
        yield "Opening your UPI app. You'll need to enter the recipient and amount, then approve the payment yourself.";
        try {
          await _smartAppActions.makeUpiPayment();
        } catch (e) {
          yield "Failed to open UPI: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.playOnSpotify:
        final query = _extractSpotifyQuery(message);
        if (query.isEmpty) {
          yield "What should I play on Spotify?";
          break;
        }
        yield "Opening Spotify for **$query**...";
        try {
          await _smartAppActions.playOnSpotify(query);
        } catch (e) {
          yield "Failed to open Spotify: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.bookRide:
        final destination = _extractRideDestination(message);
        if (destination.isEmpty) {
          yield "Where do you want the ride to go?";
          break;
        }
        yield "Opening your ride app for **$destination**. Confirm the booking there.";
        try {
          await _smartAppActions.bookRide(destination);
        } catch (e) {
          yield "Failed to open ride app: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.orderFood:
        yield "Opening your food delivery app. Pick the restaurant and place the order there.";
        try {
          await _smartAppActions.orderFood();
        } catch (e) {
          yield "Failed to open food app: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.shareContent:
        final lastAnswer = _lastAssistantMessage(chatHistory);
        if (lastAnswer.trim().isEmpty) {
          yield "There's nothing to share yet. Ask me something first, then say share it.";
          break;
        }
        yield "Opening the share sheet with my last answer...";
        try {
          await _smartAppActions.shareText(lastAnswer);
        } catch (e) {
          yield "Failed to share: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.openProfile:
        yield "Opening a specific social profile isn't supported yet — Aura can't reliably tell the platform and username apart. Try: open Instagram.";
        break;

      case IntentType.normalChat:
        // Let the model ANSWER by default. Only redirect to web search when the
        // message genuinely needs CURRENT/real-time info the model can't know
        // (news, prices, weather, live scores). Conversational, creative,
        // opinion, and advice questions are always answered by the model —
        // even a small model does far better than a useless web search.
        if (_needsWebSearch(message) && !hasDocuments) {
          debugPrint('ORCHESTRATOR: Real-time info query — using web search');
          yield* _handleWebSearch(message, voice: voiceStyle);
        } else {
          yield* _handleLLMFlow(
            message,
            chatHistory,
            includeMemories: true,
            includeDocuments: hasDocuments,
            voice: voiceStyle,
            concise: conciseStyle,
          );
        }
        break;

      // ═══ DOCUMENT GENERATION ═══

      case IntentType.generateDocument:
        final docGenService = DocumentGenerationService(_llmService);
        final lastAnswer = _lastAssistantMessage(chatHistory);
        final topic = _extractDocTopic(message);
        final isConvert = _isPdfConvertRequest(message);

        if (isConvert && lastAnswer.isNotEmpty) {
          // BEST CASE: put the previous answer into a PDF. No model needed —
          // we already have the content, so this always works even on weak models.
          yield '📄 Creating a PDF from the previous answer...\n\n';
          yield* docGenService.generateAndExportPdf(
            topic: topic.isNotEmpty ? topic : 'AURA Notes',
            style: 'document',
            preGeneratedContent: lastAnswer,
          );
        } else if (topic.isNotEmpty &&
            topic.split(RegExp(r'\s+')).length >= 2) {
          // Fresh generation about a real, substantial topic.
          yield* docGenService.generateAndExportPdf(
            topic: topic,
            style: _extractDocStyle(message),
          );
        } else {
          // Nothing to work with — guide the user instead of making a broken PDF.
          yield 'What should the PDF be about?\n\n'
              '• Ask me something first, then say **"make it a pdf"** to save that answer, or\n'
              '• Tell me the topic directly, like **"generate a pdf about Newton\'s laws"**.';
        }
        break;

      case IntentType.generateCode:
        final docGenService = DocumentGenerationService(_llmService);
        final description = _extractCodeDescription(message);
        final language = _extractCodeLanguage(message);
        yield* docGenService.generateAndExportCode(
          description: description,
          language: language,
        );
        break;

      case IntentType.generateCsv:
        final docGenService = DocumentGenerationService(_llmService);
        final description = message
            .replaceAll(
              RegExp(
                r'\b(create|generate|make|export)\s+(a\s+)?(csv|spreadsheet|excel|table\s+data)\s*(for|about|of|on)?\s*',
                caseSensitive: false,
              ),
              '',
            )
            .trim();
        yield* docGenService.generateAndExportCsv(
          description: description.isEmpty ? message : description,
        );
        break;

      case IntentType.summarizeChat:
        final docGenService = DocumentGenerationService(_llmService);
        // Get current chat messages from history
        final messages = chatHistory.map((h) {
          final parts = h.split(': ');
          final role = parts[0].toLowerCase() == 'user' ? 'user' : 'assistant';
          final content = parts.length > 1 ? parts.sublist(1).join(': ') : h;
          return {'role': role, 'content': content};
        }).toList();
        yield* docGenService.summarizeAndExportPdf(messages: messages);
        break;

      // ═══ CONNECTORS ═══

      case IntentType.getWeather:
        try {
          final city = _extractWeatherLocation(message);
          yield '🌤️ Checking weather for **$city**...\n\n';
          final weatherService = WeatherService();
          final data = await weatherService.getWeather(city);
          yield weatherService.formatWeatherResponse(data);
        } catch (e) {
          yield '❌ Failed to get weather: $e';
        }
        break;

      case IntentType.getWikipedia:
        try {
          final topic = message
              .replaceAll(
                RegExp(
                  r'\b(wiki|wikipedia|look\s+up|search)\b',
                  caseSensitive: false,
                ),
                '',
              )
              .trim();
          yield '📖 Looking up **$topic** on Wikipedia...\n\n';
          final wikiService = WikipediaService();
          final data = await wikiService.getSummary(topic);
          yield wikiService.formatWikiResponse(data);
        } catch (e) {
          yield '❌ Failed to fetch from Wikipedia: $e';
        }
        break;

      case IntentType.getNews:
        try {
          final query = message
              .replaceAll(
                RegExp(
                  r'\b(news|headlines|latest\s+news|show|get|tell\s+me)\b',
                  caseSensitive: false,
                ),
                '',
              )
              .replaceAll(
                RegExp(r'\b(about|on|for)\b', caseSensitive: false),
                '',
              )
              .trim();
          yield '📰 Fetching news${query.isNotEmpty ? ' about **$query**' : ''}...\n\n';
          final newsService = NewsService();
          final articles = await newsService.getHeadlines(
            query: query.isNotEmpty ? query : null,
          );
          yield newsService.formatNewsResponse(
            articles,
            query: query.isNotEmpty ? query : null,
          );
        } catch (e) {
          yield '❌ Failed to fetch news: $e';
        }
        break;

      case IntentType.youtubeSearch:
        try {
          final query = message
              .replaceAll(
                RegExp(
                  r'\b(youtube|yt|search|find|play|watch|show|on)\b',
                  caseSensitive: false,
                ),
                '',
              )
              .trim();
          yield '🎬 Searching YouTube for **$query**...\n';
          final ytService = YouTubeService();
          await ytService.searchOnYouTube(query);
          yield '__DISMISS__';
        } catch (e) {
          yield '❌ Failed to open YouTube: $e';
        }
        break;

      case IntentType.translateText:
        try {
          final translationService = TranslationService();
          // Extract target language and text
          final langMatch = RegExp(
            r'\b(to|into|in)\s+(\w+)',
            caseSensitive: false,
          ).firstMatch(message);
          final targetLang = langMatch?.group(2) ?? 'English';
          final textToTranslate = message
              .replaceAll(RegExp(r'^translate\s*', caseSensitive: false), '')
              .replaceAll(
                RegExp(r'\s*(to|into|in)\s+\w+\s*$', caseSensitive: false),
                '',
              )
              .trim();

          yield '🌐 Translating to **$targetLang**...\n\n';
          final prompt = translationService.buildTranslationPrompt(
            textToTranslate,
            targetLang,
          );
          yield* _llmService.chat(
            prompt,
            systemPrompt: 'Output ONLY the translation. Nothing else.',
            temperature: 0.2,
            maxTokens: 256,
          );
        } catch (e) {
          yield '❌ Translation failed: $e';
        }
        break;

      case IntentType.generateQRCode:
        try {
          final content = message
              .replaceAll(
                RegExp(
                  r'\b(generate|create|make)\s+(a\s+)?qr\s*code\s*(for|of|with)?\s*',
                  caseSensitive: false,
                ),
                '',
              )
              .trim();
          final qrService = QRCodeService();
          yield qrService.formatQRResponse(
            content.isNotEmpty ? content : 'https://aura.ai',
          );
        } catch (e) {
          yield '❌ Failed to generate QR code: $e';
        }
        break;

      case IntentType.getSystemInfo:
        try {
          yield '📱 Getting device information...\n\n';
          final sysService = SystemInfoService();
          final info = await sysService.getSystemInfo();
          yield sysService.formatSystemInfo(info);
        } catch (e) {
          yield '❌ Failed to get system info: $e';
        }
        break;

      case IntentType.findNearby:
        try {
          final place = message
              .replaceAll(
                RegExp(
                  r'\b(find|show|nearby|near\s+me|closest|nearest|where)\b',
                  caseSensitive: false,
                ),
                '',
              )
              .trim();
          yield '📍 Searching for **$place** nearby...\n';
          final locService = LocationService();
          await locService.searchNearby('$place near me');
          yield '__DISMISS__';
        } catch (e) {
          yield '❌ Failed to search nearby: $e';
        }
        break;
    }
  }

  // ── Native Function Calling (Requirement 5) ──────────────────────────────

  /// Builds the tool-definition set handed to tool-calling-capable models on
  /// every inference call (Requirement 5.1). Every tool name maps to one of the
  /// orchestrator's existing handlers; each definition declares its parameters
  /// and which are required so the [FunctionCallCoordinator] can validate
  /// emissions (Requirement 5.6).
  static List<ToolDefinition> _buildToolDefinitions() {
    return const [
      ToolDefinition(
        name: 'store_memory',
        parameters: [ToolParameter(name: 'content', required: true)],
      ),
      ToolDefinition(
        name: 'retrieve_memory',
        parameters: [ToolParameter(name: 'query', required: true)],
      ),
      ToolDefinition(
        name: 'web_search',
        parameters: [ToolParameter(name: 'query', required: true)],
      ),
      ToolDefinition(
        name: 'scrape_url',
        parameters: [ToolParameter(name: 'url', required: true)],
      ),
      ToolDefinition(
        name: 'open_app',
        parameters: [ToolParameter(name: 'appName', required: true)],
      ),
      ToolDefinition(
        name: 'open_settings',
        parameters: [ToolParameter(name: 'type')],
      ),
      ToolDefinition(name: 'open_camera'),
      ToolDefinition(
        name: 'dial_contact',
        parameters: [ToolParameter(name: 'contactName', required: true)],
      ),
      ToolDefinition(
        name: 'send_sms',
        parameters: [
          ToolParameter(name: 'name', required: true),
          ToolParameter(name: 'message'),
        ],
      ),
      ToolDefinition(
        name: 'set_reminder',
        parameters: [
          ToolParameter(name: 'time', required: true),
          ToolParameter(name: 'title'),
        ],
      ),
      ToolDefinition(
        name: 'navigation',
        parameters: [ToolParameter(name: 'destination', required: true)],
      ),
      ToolDefinition(
        name: 'toggle_torch',
        parameters: [ToolParameter(name: 'state')],
      ),
      ToolDefinition(
        name: 'generate_image',
        parameters: [ToolParameter(name: 'prompt', required: true)],
      ),
    ];
  }

  /// The tool-definition set this orchestrator presents to tool-calling models.
  /// Exposed for property tests verifying Requirement 5.1 (the set handed to the
  /// model equals the registry exactly).
  @visibleForTesting
  List<ToolDefinition> get toolDefinitions => _toolDefinitions;

  /// Describes the available tools to the model as part of the system prompt so
  /// a tool-calling model receives the full tool-definition set on the inference
  /// call (Requirement 5.1).
  String _buildToolSystemPrompt() => buildToolSystemPrompt(_toolDefinitions);

  /// Pure encoding of a tool registry into the system prompt presented to a
  /// tool-calling model. Every tool in [tools] is rendered as a
  /// `- name(param[ (required)], ...)` line under an `Available tools:` header,
  /// so the presentation losslessly carries each tool name and its declared
  /// parameters (Requirement 5.1). Extracted as a pure function so the
  /// registry→presentation mapping is directly testable.
  @visibleForTesting
  static String buildToolSystemPrompt(List<ToolDefinition> tools) {
    final buffer = StringBuffer()
      ..writeln(
        'You are AURA, a helpful AI assistant. For device actions, respond with a JSON tool call. For everything else (questions, conversations, help), respond normally in plain text.',
      )
      ..writeln()
      ..writeln(
        'Tool call format: {"name": "<tool>", "arguments": {"param": "value"}}',
      )
      ..writeln()
      ..writeln('Available tools:');
    for (final tool in tools) {
      // Present EVERY declared parameter, not just the required ones: a model
      // that never sees an optional parameter cannot fill it, which silently
      // loses capability (e.g. send_sms's message, open_settings's type).
      final params = tool.parameters
          .map((p) => '${p.name} (string${p.required ? ', required' : ''})')
          .join(', ');
      buffer.writeln('  - ${tool.name}($params)');
    }
    buffer.writeln();
    buffer.writeln(
      'Only use a tool when the user clearly wants a device action. For everything else, answer normally.',
    );
    return buffer.toString();
  }

  /// Converts Gemma 4 native tool call format to standard JSON.
  /// Input: `<|tool_call>call:functionName{param:<|"|>value<|"|>}<tool_call|>`
  /// Output: `{"name": "functionName", "arguments": {"param": "value"}}`
  String _convertNativeToolCall(String raw) {
    final nativeMatch = RegExp(
      r'<\|tool_call>call:(\w+)\{(.*?)\}<tool_call\|>',
      dotAll: true,
    ).firstMatch(raw);

    if (nativeMatch == null) return raw; // Not native format, return as-is

    final name = nativeMatch.group(1)!;
    final argsRaw = nativeMatch.group(2)!;

    // Parse native args format: key:<|"|>value<|"|>,key2:<|"|>value2<|"|>
    final args = <String, String>{};
    final argMatches = RegExp(r'(\w+):<\|"\|>(.*?)<\|"\|>').allMatches(argsRaw);
    for (final match in argMatches) {
      args[match.group(1)!] = match.group(2)!;
    }
    // Also handle non-quoted values: key:value
    final simpleMatches = RegExp(r'(\w+):([^,}<|]+)').allMatches(argsRaw);
    for (final match in simpleMatches) {
      final key = match.group(1)!;
      if (!args.containsKey(key)) {
        args[key] = match.group(2)!.trim();
      }
    }

    // Build standard JSON
    final argsJson = args.entries
        .map((e) => '"${e.key}": "${e.value}"')
        .join(', ');
    return '{"name": "$name", "arguments": {$argsJson}}';
  }

  /// Runs the native function-calling flow for a tool-calling-capable model.
  ///
  /// The model is given the full tool-definition set (Req 5.1); its emission is
  /// parsed and validated by the [FunctionCallCoordinator]:
  /// - a valid request is dispatched to its handler with the parsed parameters
  ///   (Req 5.3);
  /// - an unknown tool yields an unavailable-tool error and invokes no handler
  ///   (Req 5.5);
  /// - missing required parameters yield an error naming each one and invokes no
  ///   handler (Req 5.6);
  /// - an emission that is not a tool-call (the model chose to answer directly)
  ///   is streamed back as the conversational response.
  Stream<String> _handleFunctionCalling(
    String message,
    List<String> chatHistory, {
    bool hasDocuments = false,
  }) async* {
    // ── Streaming-first approach to avoid double-inference deadlock ───────────
    //
    // The previous approach buffered ALL tokens, parsed for a JSON tool call,
    // then re-ran _handleLLMFlow if the output was plain text (FunctionCallUnparseable).
    // This causes Gemma (LiteRT) to deadlock: opening a second session on a model
    // that just finished inference produces no tokens and hangs "Thinking...".
    //
    // Fix: check the first ~100 chars of the stream. If it starts like a JSON
    // tool call, buffer fully and parse. If it's plain conversational text,
    // stream it directly — no second inference needed.
    //
    // This also makes Gemma responses feel instant (streaming) vs. waiting for
    // the entire generation before showing anything.

    final previewBuf = StringBuffer();
    bool isToolCall = false;
    bool decided = false;
    final fullBuf = StringBuffer();

    // Temp stream buffer for the tokens received before we decide
    final pendingTokens = <String>[];

    try {
      await for (final token in _llmService.chat(
        message,
        systemPrompt: _buildToolSystemPrompt(),
        temperature: 0.3,
      )) {
        fullBuf.write(token);

        if (!decided) {
          previewBuf.write(token);
          pendingTokens.add(token);

          // After accumulating ~80 chars, decide: tool call or plain text?
          if (previewBuf.length >= 80 || token.contains('\n')) {
            final preview = previewBuf.toString().trimLeft();
            // Tool calls always start with `{` (JSON object) or Gemma 4 native `<|tool_call>`
            isToolCall =
                RegExp(
                  r'^\{\s*"(name|tool|toolName|function)"\s*:',
                ).hasMatch(preview) ||
                preview.contains('<|tool_call>');
            decided = true;

            if (!isToolCall) {
              // Plain text response — stream pending tokens out immediately
              for (final t in pendingTokens) {
                yield t;
              }
              pendingTokens.clear();
            }
          }
        } else if (!isToolCall) {
          // Already decided it's plain text — keep streaming
          yield token;
        }
        // If isToolCall, we're still buffering in fullBuf
      }
    } catch (e) {
      yield "❌ ${_errorHandler.handleError(e)}";
      return;
    }

    // If we never decided (very short output), decide now
    if (!decided) {
      final preview = previewBuf.toString().trimLeft();
      isToolCall =
          RegExp(
            r'^\{\s*"(name|tool|toolName|function)"\s*:',
          ).hasMatch(preview) ||
          preview.contains('<|tool_call>');
      if (!isToolCall) {
        for (final t in pendingTokens) {
          yield t;
        }
      }
    }

    // If it was plain text, we're done — already streamed everything
    if (!isToolCall) return;

    // It looks like a tool call — parse the full buffered output
    final raw = fullBuf.toString().trim();
    // Convert Gemma 4 native tool call format if detected
    final normalizedRaw = _convertNativeToolCall(raw);
    final result = _functionCallCoordinator.parse(normalizedRaw);

    switch (result) {
      case FunctionCallParsed(:final request):
        debugPrint(
          'ORCHESTRATOR: Function call -> ${request.toolName} ${request.arguments}',
        );
        yield* _dispatchToolCall(
          request,
          chatHistory,
          hasDocuments: hasDocuments,
        );
        break;
      case FunctionCallUnknownTool(:final toolName):
        yield "❌ The requested tool \"$toolName\" is unavailable.";
        break;
      case FunctionCallMissingParams(:final toolName, :final missing):
        yield "❌ The tool \"$toolName\" is missing required parameter(s): ${missing.join(', ')}.";
        break;
      case FunctionCallUnparseable():
        // Model produced something starting with `{` but it wasn't a valid tool call.
        // Yield the raw text directly — no second inference (avoids Gemma deadlock).
        if (raw.isNotEmpty) yield raw;
        break;
    }
  }

  /// Routes a validated [request] to the handler associated with its tool name,
  /// passing the parsed parameter values (Requirement 5.3). Each branch reuses
  /// the same actions the rule-based intent path invokes.
  Stream<String> _dispatchToolCall(
    FunctionCallRequest request,
    List<String> chatHistory, {
    bool hasDocuments = false,
  }) async* {
    final args = request.arguments;
    String argStr(String key) => (args[key]?.toString() ?? '').trim();

    switch (request.toolName) {
      case 'store_memory':
        try {
          await _memoryService.saveMemory(argStr('content'));
          yield "✅ Memory saved in your local vault.";
        } catch (e) {
          yield "❌ Failed to save memory: ${_errorHandler.handleError(e)}";
        }
        break;

      case 'retrieve_memory':
        try {
          yield* _handleMemoryRetrieve(argStr('query'));
        } catch (e) {
          yield "❌ Failed to retrieve memories: ${_errorHandler.handleError(e)}";
        }
        break;

      case 'web_search':
        try {
          yield* _handleWebSearch(argStr('query'));
        } catch (e) {
          yield "Web search failed: ${_errorHandler.handleError(e)}";
        }
        break;

      case 'scrape_url':
        try {
          yield* _handleUrlScrape(argStr('url'));
        } catch (e) {
          yield "❌ Failed to read webpage: ${_errorHandler.handleError(e)}";
        }
        break;

      case 'open_app':
        final appName = argStr('appName');
        yield "Opening $appName";
        await _appControlService.openApp(appName);
        yield "__DISMISS__";
        break;

      case 'open_settings':
        final type = args['type'] != null && argStr('type').isNotEmpty
            ? argStr('type')
            : 'general';
        yield "⚙️ **Opening ${type == 'general' ? 'Settings' : '$type Settings'}...**";
        await _appControlService.openSettings(type);
        break;

      case 'open_camera':
        yield "Opening Camera";
        await _appControlService.openCamera();
        yield "__DISMISS__";
        break;

      case 'dial_contact':
        yield* _dispatchDialContact(argStr('contactName'));
        break;

      case 'send_sms':
        yield* _dispatchSendSms(argStr('name'), argStr('message'));
        break;

      case 'set_reminder':
        final title = argStr('title');
        final time = argStr('time');
        final reminderMessage = title.isNotEmpty
            ? 'remind me to $title at $time'
            : 'remind me at $time';
        yield* _handleReminderSet(reminderMessage);
        break;

      case 'navigation':
        final destination = argStr('destination');
        yield "Getting directions to $destination";
        await _appControlService.openApp("navigate:$destination");
        yield "__DISMISS__";
        break;

      case 'toggle_torch':
        final stateArg = argStr('state').toLowerCase();
        final state =
            !(stateArg == 'off' ||
                stateArg == 'false' ||
                stateArg == 'disable');
        yield state
            ? "💡 **Turning Flashlight ON...**"
            : "🌑 **Turning Flashlight OFF...**";
        try {
          await _appControlService.toggleTorch(state);
        } catch (e) {
          yield "❌ Failed to toggle flashlight. It might not be available or permitted.";
        }
        break;

      case 'generate_image':
        final imgPrompt = argStr('prompt');
        if (imgPrompt.isEmpty) {
          yield "❌ Please describe the image you want generated.";
        } else {
          yield '🎨 Generating an image of "$imgPrompt"...\n\n';
          yield _imageGen.buildChatImageMarkdown(imgPrompt);
        }
        break;

      default:
        // Defensive: the coordinator only emits FunctionCallParsed for known
        // tools, so this is unreachable for registered tools.
        yield "❌ The requested tool \"${request.toolName}\" is unavailable.";
    }
  }

  /// Dial-contact dispatch shared shape with the rule-based handler, driven by
  /// the structured `contactName` parameter.
  Stream<String> _dispatchDialContact(String contactName) async* {
    final matches = await _appControlService.resolveContacts(contactName);
    if (matches.isEmpty) {
      yield "Couldn't find a contact named $contactName. Try again with the exact name.";
    } else if (matches.length == 1) {
      final number = matches.first.phones.isNotEmpty
          ? matches.first.phones.first.number
          : '';
      if (number.isNotEmpty) {
        yield "Calling ${matches.first.displayName}";
        await _appControlService.dialContact(number);
        yield "__DISMISS__";
      } else {
        yield "Contact ${matches.first.displayName} has no phone number.";
      }
    } else {
      final names = matches.take(5).toList();
      final nameList = names
          .asMap()
          .entries
          .map((e) => "${e.key + 1}. ${e.value.displayName}")
          .join(", ");
      yield "I found ${names.length} contacts similar to $contactName: $nameList. Say the number or tap to select. [[OPTIONS:${names.map((c) {
        final number = c.phones.isNotEmpty ? c.phones.first.number : '';
        return "${c.displayName}|call $number";
      }).join(",")}]]";
    }
  }

  /// Send-SMS dispatch driven by structured `name` and `message` parameters.
  Stream<String> _dispatchSendSms(String name, String smsBody) async* {
    if (name.isEmpty) {
      yield "I couldn't understand who to send the message to. Please try again with the contact name.";
      return;
    }

    // Reuse the existing AI body-enhancement heuristic.
    if (smsBody.isNotEmpty && _llmService.isModelLoaded) {
      smsBody = await _enhanceSMSBody(smsBody, name);
    }

    final matches = await _appControlService.resolveContacts(name);
    if (matches.isEmpty) {
      yield "Opening SMS to $name${smsBody.isNotEmpty ? ' with message: $smsBody' : ''}";
      await _appControlService.sendSMS(name, smsBody);
      yield "__DISMISS__";
    } else if (matches.length == 1) {
      final number = matches.first.phones.isNotEmpty
          ? matches.first.phones.first.number
          : '';
      if (number.isNotEmpty) {
        yield "Sending SMS to ${matches.first.displayName}${smsBody.isNotEmpty ? ': $smsBody' : ''}";
        await _appControlService.sendSMS(number, smsBody);
        yield "__DISMISS__";
      } else {
        yield "Contact ${matches.first.displayName} has no phone number.";
      }
    } else {
      final names = matches.take(5).toList();
      final nameList = names
          .asMap()
          .entries
          .map((e) => "${e.key + 1}. ${e.value.displayName}")
          .join(", ");
      yield "I found ${names.length} contacts similar to $name: $nameList. Say the number or tap to select. [[OPTIONS:${names.map((c) {
        final number = c.phones.isNotEmpty ? c.phones.first.number : '';
        return "${c.displayName}|text $number $smsBody";
      }).join(",")}]]";
    }
  }

  Stream<String> _handleMemoryRetrieve(String message) async* {
    try {
      final memories = await _memoryService.retrieveRelevantMemories(message);

      if (memories.isEmpty) {
        yield "I couldn't find any relevant memories for that query. Try asking about something you've previously saved.";
        return;
      }

      final prompt = _contextBuilder.injectMemory(memories, message);
      yield* _llmService.chat(prompt, temperature: 0.3);
    } catch (e) {
      _errorHandler.handleError(e);
      rethrow;
    }
  }

  Stream<String> _handleWebSearch(String message, {bool voice = false}) async* {
    try {
      final cleanQuery = _intentService.extractSearchQuery(message);
      if (!voice) {
        yield "🔍 **Searching the web for: '$cleanQuery'**...\n\n";
      }
      _errorHandler.logInfo("Web search: '$cleanQuery'");

      final results = await _webService.search(cleanQuery);

      if (results.isEmpty) {
        yield voice
            ? "I couldn't find current information about that."
            : "I couldn't find any recent information for '$cleanQuery'. Try rephrasing your query.";
        return;
      }

      final prompt = _contextBuilder.injectWeb(results, cleanQuery);

      // 1. Stream the synthesized answer from AI — grounded in search results
      final isSmall = _llmService.modelTier.isSmall;
      final searchSystemPrompt = voice
          ? "Answer the question using ONLY the search results above. Reply in "
                "1-3 short spoken sentences with no markdown, links, or lists. "
                "If the results don't answer it, say so briefly."
          : isSmall
          ? "Answer using ONLY the search results above. If not found, say so."
          : "You have web access. Use ONLY the Search Results provided below to answer the user. If the results don't fully answer the question, state what you found and what is missing. Never invent facts not present in the results.";
      yield* _llmService.chat(
        prompt,
        systemPrompt: searchSystemPrompt,
        temperature: 0.3,
        maxTokens: voice
            ? 200
            : isSmall
            ? 256
            : 512,
      );

      // 2. Append top 5 sources at the end (skipped for spoken answers).
      if (voice) return;
      yield "\n\n🌐 **Top Sources:**\n";
      final topResults = results.take(5).toList();
      for (var i = 0; i < topResults.length; i++) {
        final res = topResults[i];
        yield "${i + 1}. [${res.title}](${res.url})\n";
      }
    } catch (e) {
      _errorHandler.handleError(e);
      rethrow;
    }
  }

  Stream<String> _handleUrlScrape(String message) async* {
    try {
      final url = _intentService.extractUrl(message);
      yield "🌐 **Reading content from: '$url'**...\n\n";
      _errorHandler.logInfo("URL scrape: '$url'");

      final content = await _scraperService.scrape(url);

      if (content.snippet.isEmpty ||
          content.snippet == 'No readable content found') {
        yield "I couldn't extract readable content from that webpage. It may contain only images or restricted content.";
        return;
      }

      final prompt = _contextBuilder.injectURL(content, message);
      yield* _llmService.chat(
        prompt,
        systemPrompt:
            "You are analyzing a specific webpage. Summarize ONLY the content provided in the context to answer the user. Do NOT add information not found in the provided content. The content has already been fetched for you.",
        temperature: 0.3,
      );
    } catch (e) {
      _errorHandler.handleError(e);
      rethrow;
    }
  }

  Stream<String> _handleEmailDraft(String message) async* {
    final address =
        _intentService.extractEmailAddress(message) ?? 'the recipient';
    final topic = _intentService.extractEmailTopic(message, address);
    final topicText = topic.isNotEmpty ? topic : 'the discussed topic';

    debugPrint('ORCHESTRATOR: Drafting email to $address about "$topicText"');

    // Magic marker: chat_provider intercepts this and inserts the system message.
    // It is NEVER shown to the user.
    yield '__EMAIL_DRAFT__:$address\n';

    final isSmall = _llmService.modelTier.isSmall;

    if (isSmall) {
      // Small model: use a concrete example-based prompt (no placeholders to confuse it)
      final prompt =
          'Write a short professional email.\n'
          'To: $address\n'
          'About: $topicText\n\n'
          'Example:\n'
          'Subject: Meeting Tomorrow\n\n'
          'Dear Team,\n\n'
          'I wanted to discuss our project timeline. Please let me know your availability.\n\n'
          'Regards,\nAura User\n\n'
          'Now write the real email about "$topicText":';

      yield* _llmService.chat(
        prompt,
        systemPrompt: 'Write a short email. No extra text.',
        temperature: 0.5,
        maxTokens: 200,
      );
    } else {
      final prompt =
          'Write a professional email to $address about: $topicText.\n'
          'Reply ONLY in this exact format — no extra commentary:\n\n'
          'Subject: (one short subject line)\n\n'
          '(email body paragraphs)\n\n'
          'Regards,\nAura User';

      yield* _llmService.chat(
        prompt,
        systemPrompt:
            'You are a professional email writing assistant. '
            'Write clear, concise, well-structured emails. '
            'Never use placeholder text in brackets in your output. '
            'Always write real content.',
        temperature: 0.6,
      );
    }
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
      final isSmall = _llmService.modelTier.isSmall;
      final buffer = StringBuffer();
      await for (final token in _llmService.chat(
        isSmall
            ? 'Write a short SMS to $recipientName: $body\nSMS:'
            : 'Compose a short, friendly SMS message for the following instruction. '
                  'Recipient: $recipientName. Instruction: "$body". '
                  'Reply with ONLY the message text, nothing else.',
        systemPrompt: isSmall
            ? 'Write only the SMS text. Nothing else.'
            : 'You compose short SMS messages. Reply with only the message text. Keep it under 160 characters when possible. Be natural and friendly.',
        maxTokens: isSmall ? 40 : 60,
        temperature: 0.5,
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
    bool voice = false,
    bool concise = false,
  }) async* {
    // Build system context (instructions + memories + docs + history)
    // separately from the user message so the prompt template can format them
    // correctly (system goes into the system role, message into user role).
    var systemContext = await _contextBuilder.buildSystemContext(
      userMessage: message,
      chatHistory: history,
      includeMemories: includeMemories,
      includeDocuments: includeDocuments,
    );

    // Apply response-style hints (concise / voice) via the system prompt.
    // These are NEVER injected into the message text so they can't leak into
    // the chat display or intent detection.
    if (voice) {
      systemContext +=
          '\n\nThis is a spoken voice conversation. Answer the question '
          'directly in 1-3 short sentences of plain speech. Never use '
          'markdown, bullet points, code blocks, emoji, or URLs. If you are '
          'unsure, say what you do know briefly instead of staying silent.';
    } else if (concise) {
      systemContext +=
          '\n\nKeep your response concise and direct, '
          'under 2-3 sentences.';
    }

    final tier = _llmService.modelTier;
    final lowerMsg = message.toLowerCase();

    // ── Detect if this is a long-form writing task ──────────────────────────
    final needsMoreTokens =
        lowerMsg.contains('write') ||
        lowerMsg.contains('code') ||
        lowerMsg.contains('script') ||
        lowerMsg.contains('program') ||
        lowerMsg.contains('create') ||
        lowerMsg.contains('generate') ||
        lowerMsg.contains('build') ||
        lowerMsg.contains('implement') ||
        lowerMsg.contains('essay') ||
        lowerMsg.contains('explain in detail') ||
        lowerMsg.contains('list all') ||
        lowerMsg.contains('step by step');

    // ── Token budget ────────────────────────────────────────────────────────
    // On-device models are capped aggressively to stay fast and fit their small
    // context. Online / large-context models (big context window) are given
    // room to finish a complete answer — a low cap here was truncating long
    // replies mid-sentence.
    final int maxTokens;
    final int contextWindow = _llmService.contextTokens;
    if (contextWindow >= 16000) {
      // Online provider or large-context model. Output tokens are free of any
      // device-memory pressure here, so give the model plenty of room to finish
      // a complete answer (tables, lists and multi-section replies were being
      // cut off mid-line at a 2048 cap). We still clamp to a fraction of the
      // reported window so we never ask for more output than the model allows.
      final int roomy = needsMoreTokens ? 8192 : 4096;
      final int windowCap = (contextWindow * 0.6).floor();
      maxTokens = roomy < windowCap ? roomy : windowCap;
    } else if (tier.isSmall) {
      maxTokens = needsMoreTokens ? 384 : 192;
    } else if (tier == ModelTier.medium) {
      maxTokens = needsMoreTokens ? 768 : 384;
    } else {
      // On-device large model: raise the ceiling so answers are not cut short,
      // while still leaving context headroom for the prompt.
      maxTokens = needsMoreTokens ? 2048 : 1024;
    }

    // ── Temperature: factual/grounded tasks get lower temp
    final double temperature;
    if (includeDocuments || includeMemories) {
      temperature = 0.3;
    } else if (tier.isSmall || tier == ModelTier.medium) {
      temperature = 0.4;
    } else {
      temperature = 0.65;
    }

    yield* _llmService.chat(
      message,
      systemPrompt: systemContext,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  /// Returns true ONLY when a message genuinely needs current/real-time web
  /// data that no local model could know (breaking news, live prices, weather,
  /// scores, very recent events).
  ///
  /// Everything else — general knowledge, conversation, advice, suggestions,
  /// creative tasks, opinions, how-to help — is answered by the local model.
  /// This keeps the assistant conversational instead of constantly redirecting
  /// to the browser.
  bool _needsWebSearch(String message) {
    final lower = message.toLowerCase().trim();

    // NOTE: weather is NOT here — it's handled by the getWeather intent (Open-Meteo API).
    return RegExp(
      r'\b(latest\s+news|breaking\s+news|current\s+news|'
      r"today'?s?\s+(news|headlines|score|match|price|rate)|"
      r'news\s+(about|on|regarding)|'
      r'stock\s+price|share\s+price|price\s+of|cost\s+of|exchange\s+rate|'
      r'live\s+(score|match|update)|match\s+(score|result)|'
      r'cricket\s+score|football\s+score|who\s+won\s+(the|yesterday|today)|'
      r'release\s+date|when\s+(is|does)\s+.+\s+(releasing|coming\s+out|launch)|'
      r'trending\s+(now|today))\b',
      caseSensitive: false,
    ).hasMatch(lower);
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
        'preReminderEnabled': true,
      });

      final hour = scheduledTime.hour % 12 == 0 ? 12 : scheduledTime.hour % 12;
      final minute = scheduledTime.minute.toString().padLeft(2, '0');
      final amPm = scheduledTime.hour < 12 ? 'AM' : 'PM';
      final now2 = DateTime.now();
      final isToday =
          scheduledTime.day == now2.day && scheduledTime.month == now2.month;
      final isTomorrow =
          scheduledTime.day == now2.day + 1 &&
          scheduledTime.month == now2.month;
      final dayStr = isToday
          ? 'today'
          : isTomorrow
          ? 'tomorrow'
          : '${scheduledTime.day}/${scheduledTime.month}';
      yield "✅ Got it! I'll remind you to **$title** $dayStr at **$hour:$minute $amPm**.";
    } catch (e) {
      debugPrint("Failed to set native reminder: $e");
      yield "Sorry, an error occurred while scheduling the reminder on your device.";
    }
  }

  // ── Study Buddy Handlers ────────────────────────────────────────────────

  Stream<String> _handleStudyCreateFlashcards(String message) async* {
    try {
      yield "📝 **Generating flashcards...**\n";

      // Extract a name from the message
      final nameMatch = RegExp(
        r'(?:from|about|for|on)\s+(.+)',
        caseSensitive: false,
      ).firstMatch(message);
      final deckName = nameMatch?.group(1)?.trim() ?? 'Study Deck';

      // Create deck and guide the user to add cards
      await _studyService.createEmptyDeck(
        deckName,
        description: 'Created from chat command',
      );

      yield "✅ **Created study deck: \"$deckName\"**\n\n";
      yield "To add flashcards:\n";
      yield "• Open **Study Buddy** from the sidebar\n";
      yield "• Select your deck and tap **+** to add cards\n";
      yield "• Or upload a PDF and I'll auto-generate cards from it!\n";
      yield "\n__NAVIGATE__:study_dashboard";
    } catch (e) {
      final errorMsg = _errorHandler.handleError(e);
      yield "❌ Failed to create flashcards: $errorMsg";
    }
  }

  Stream<String> _handleStudyScheduleExam(String message) async* {
    try {
      // Extract exam name and date from message
      final lo = message.toLowerCase();

      // Try to extract exam name
      final nameMatch = RegExp(
        r'(?:have\s+(?:a|an)\s+|schedule\s+(?:an?\s+)?|add\s+)'
        r'(\w[\w\s]*?)\s+(?:exam|test|quiz)',
        caseSensitive: false,
      ).firstMatch(lo);
      final examName = nameMatch?.group(1)?.trim() ?? 'Exam';

      // Try to extract date
      final dateMatch = RegExp(
        r'(?:on|at|in)\s+(\w+\s+\d{1,2}(?:st|nd|rd|th)?(?:\s*,?\s*\d{4})?)',
        caseSensitive: false,
      ).firstMatch(lo);

      DateTime examDate;
      if (dateMatch != null) {
        // Simple date parsing — try common formats
        examDate =
            _parseSimpleDate(dateMatch.group(1)!) ??
            DateTime.now().add(const Duration(days: 7));
      } else {
        // Default: 7 days from now
        examDate = DateTime.now().add(const Duration(days: 7));
      }

      final exam = await _studyService.scheduleExam(
        '${examName[0].toUpperCase()}${examName.substring(1)} Exam',
        examDate,
      );

      final daysLeft = exam.daysRemaining;
      final revisionDates = _studyService.getRevisionSchedule(examDate);
      final intensity = _studyService.getStudyIntensity(daysLeft);

      yield "📅 **Exam Scheduled!**\n\n";
      yield "**${exam.name}** — $daysLeft days remaining\n\n";
      yield "**Study Plan:** ${intensity.label}\n";
      yield "${intensity.description}\n\n";

      if (revisionDates.isNotEmpty) {
        yield "**Revision Schedule:**\n";
        for (final date in revisionDates) {
          yield "• ${date.day}/${date.month}/${date.year}\n";
        }
      }

      yield "\nOpen **Study Buddy** to track your progress!";
    } catch (e) {
      final errorMsg = _errorHandler.handleError(e);
      yield "❌ Failed to schedule exam: $errorMsg";
    }
  }

  // ── Smart App Actions Extraction Helpers ─────────────────────────────

  String _extractWhatsAppContact(String message) {
    final lo = message.toLowerCase();
    final match = RegExp(
      r'(?:whatsapp|message)\s+(\w+)',
      caseSensitive: false,
    ).firstMatch(lo);
    return match?.group(1) ?? '';
  }

  String _extractWhatsAppMessage(String message) {
    final match = RegExp(
      r'(?:saying|that|with\s+message|as)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(message);
    return match?.group(1)?.trim() ?? '';
  }

  String _extractSpotifyQuery(String message) {
    final match = RegExp(
      r'(?:play|listen\s+to)\s+(.+?)(?:\s+on\s+spotify)',
      caseSensitive: false,
    ).firstMatch(message);
    return match?.group(1)?.trim() ?? message;
  }

  String _extractRideDestination(String message) {
    final match = RegExp(
      r'(?:to)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(message);
    return match?.group(1)?.trim() ?? message;
  }

  // ── Document Generation Helpers ─────────────────────────────────────────

  String _extractWeatherLocation(String message) {
    // Extract location from weather queries: "weather in London", "what's the weather in Tokyo"
    final match = RegExp(
      r'(?:weather|temperature|forecast)\s+(?:in|at|for|of)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(message);
    if (match != null) return match.group(1)!.trim();

    // Fallback: remove weather keywords and use the rest
    return message
        .replaceAll(
          RegExp(
            r'\b(what.?s\s+the|how.?s\s+the|check|get|show)\s+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(weather|temperature|forecast|climate)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(today|now|currently|right\s+now|outside)\b',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  String _extractDocTopic(String message) {
    // Remove trigger words to get the topic
    return message
        .replaceAll(
          RegExp(
            r'\b(write|create|generate|make)\s+(a\s+)?(report|essay|letter|resume|cv|document|notes|pdf)\s*(about|on|for|of)?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(and\s+)?(save|export|download|convert|put|give|send)\s*(this|it|that)?\s*(as|to|in)?\s*(a\s+)?(pdf|file|document)?\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\b(please|plese|pls)\b', caseSensitive: false), '')
        .trim();
  }

  /// True when the message is a short request to convert the previous answer
  /// into a PDF (e.g. "generate in pdf", "make it a pdf", "send as pdf"),
  /// rather than a request to write a fresh document about a specific topic.
  bool _isPdfConvertRequest(String message) {
    final lo = message.toLowerCase().trim();
    // References to existing content: "this", "it", "that", "the answer",
    // "in pdf", "as pdf", or a short message that just mentions pdf.
    final hasReference = RegExp(
      r'\b(this|it|that|the\s+(answer|response|list|above)|our\s+(chat|conversation))\b',
      caseSensitive: false,
    ).hasMatch(lo);
    final isShortPdfRequest =
        lo.split(RegExp(r'\s+')).length <= 8 &&
        RegExp(r'\bpdf\b', caseSensitive: false).hasMatch(lo);
    final isConvertVerb = RegExp(
      r'\b(convert|export|save|download|put|make\s+it|give\s+me|send)\b.*\bpdf\b|'
      r'\b(in|as|to)\s+(a\s+)?pdf\b',
      caseSensitive: false,
    ).hasMatch(lo);
    return hasReference || isShortPdfRequest || isConvertVerb;
  }

  /// Extracts the most recent SUBSTANTIAL assistant answer from chat history.
  /// History entries are formatted as "User: ..." / "Assistant: ...".
  ///
  /// Skips: the empty placeholder for the current turn, PDF/status messages
  /// (e.g. "Creating a PDF...", "PDF exported"), and trivially short replies —
  /// so "make it a pdf" always grabs the real content, not a status line.
  String _lastAssistantMessage(List<String> chatHistory) {
    for (int i = chatHistory.length - 1; i >= 0; i--) {
      final entry = chatHistory[i];
      if (!entry.startsWith('Assistant:')) continue;
      final content = entry.substring('Assistant:'.length).trim();
      if (content.length < 40) continue; // skip empty/short/status replies
      if (content.contains('📄') ||
          content.contains('Creating a PDF') ||
          content.contains('Creating PDF') ||
          content.contains('PDF exported') ||
          content.contains('What should the PDF')) {
        continue; // skip our own PDF status/prompt messages
      }
      return content;
    }
    return '';
  }

  String _extractDocStyle(String message) {
    final lo = message.toLowerCase();
    if (lo.contains('resume') || lo.contains('cv')) return 'resume';
    if (lo.contains('letter')) return 'letter';
    if (lo.contains('notes') || lo.contains('study')) return 'notes';
    if (lo.contains('essay')) return 'essay';
    return 'report';
  }

  String _extractCodeDescription(String message) {
    return message
        .replaceAll(
          RegExp(
            r'\b(write|create|generate|make|export)\s+(a\s+)?',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(python|javascript|dart|java|html|css|sql|typescript|kotlin|swift|rust|go|ruby|php|c\+\+|c)\s+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'\b(code|script|program|file)\b', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(and\s+)?(save|export|download)\s*(as|to)?\s*(file)?\b',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  String _extractCodeLanguage(String message) {
    final lo = message.toLowerCase();
    if (lo.contains('python')) return 'python';
    if (lo.contains('javascript') || lo.contains(' js ')) return 'javascript';
    if (lo.contains('typescript') || lo.contains(' ts ')) return 'typescript';
    if (lo.contains('dart')) return 'dart';
    if (lo.contains('java') && !lo.contains('javascript')) return 'java';
    if (lo.contains('kotlin')) return 'kotlin';
    if (lo.contains('swift')) return 'swift';
    if (lo.contains('html')) return 'html';
    if (lo.contains('css')) return 'css';
    if (lo.contains('sql')) return 'sql';
    if (lo.contains('rust')) return 'rust';
    if (lo.contains('go ') || lo.contains('golang')) return 'go';
    if (lo.contains('ruby')) return 'ruby';
    if (lo.contains('php')) return 'php';
    if (lo.contains('c++') || lo.contains('cpp')) return 'cpp';
    return 'python'; // default
  }

  DateTime? _parseSimpleDate(String dateStr) {
    try {
      final months = {
        'jan': 1,
        'january': 1,
        'feb': 2,
        'february': 2,
        'mar': 3,
        'march': 3,
        'apr': 4,
        'april': 4,
        'may': 5,
        'jun': 6,
        'june': 6,
        'jul': 7,
        'july': 7,
        'aug': 8,
        'august': 8,
        'sep': 9,
        'september': 9,
        'oct': 10,
        'october': 10,
        'nov': 11,
        'november': 11,
        'dec': 12,
        'december': 12,
      };
      final parts = dateStr.trim().split(RegExp(r'[\s,]+'));
      if (parts.length >= 2) {
        final month = months[parts[0].toLowerCase()];
        final day = int.tryParse(parts[1].replaceAll(RegExp(r'[^\d]'), ''));
        if (month != null && day != null) {
          final year = parts.length >= 3
              ? int.tryParse(parts[2]) ?? DateTime.now().year
              : DateTime.now().year;
          return DateTime(year, month, day);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Parses a natural-language instruction into a structured tool call JSON.
  /// Returns null if it is normal chat or cannot be parsed.
  Future<String?> parseInstructionToToolCall(String instruction) async {
    // 1. Detect intent using rule-based
    final intent = await _intentService.detectIntent(instruction);

    // 2. Map to structured JSON
    switch (intent) {
      case IntentType.torchControl:
        final lo = instruction.toLowerCase();
        final state =
            !(lo.contains("off") ||
                lo.contains("disable") ||
                lo.contains("stop"));
        return '{"name": "toggle_torch", "arguments": {"state": "${state ? "on" : "off"}"}}';

      case IntentType.openCamera:
        return '{"name": "open_camera", "arguments": {}}';

      case IntentType.openSettings:
        final type = _intentService.extractSettingsType(instruction);
        return '{"name": "open_settings", "arguments": {"type": "$type"}}';

      case IntentType.openApp:
        final appName = _intentService.extractAppName(instruction);
        return '{"name": "open_app", "arguments": {"appName": "$appName"}}';

      case IntentType.dialContact:
        final contactName = _intentService.extractContactName(instruction);
        return '{"name": "dial_contact", "arguments": {"contactName": "$contactName"}}';

      case IntentType.sendSMS:
        final details = _intentService.extractSMSDetails(instruction);
        final name = details['name'] ?? '';
        final body = details['message'] ?? '';
        return '{"name": "send_sms", "arguments": {"name": "$name", "message": "$body"}}';

      case IntentType.reminderSet:
        return '{"name": "set_reminder", "arguments": {"title": "$instruction", "time": "scheduled"}}';

      case IntentType.navigation:
        final dest = _intentService.extractNavigationDestination(instruction);
        return '{"name": "navigation", "arguments": {"destination": "$dest"}}';

      case IntentType.webSearch:
        final query = _intentService.extractSearchQuery(instruction);
        return '{"name": "web_search", "arguments": {"query": "$query"}}';

      case IntentType.urlScrape:
        final url = _intentService.extractUrl(instruction);
        return '{"name": "scrape_url", "arguments": {"url": "$url"}}';

      case IntentType.memoryStore:
        final content = _intentService.extractMemoryContent(instruction);
        return '{"name": "store_memory", "arguments": {"content": "$content"}}';

      case IntentType.memoryRetrieve:
        return '{"name": "retrieve_memory", "arguments": {"query": "$instruction"}}';

      default:
        // Try LLM parsing if loaded
        if (_llmService.isModelLoaded) {
          final buffer = StringBuffer();
          try {
            await for (final token in _llmService.chat(
              instruction,
              systemPrompt: _buildToolSystemPrompt(),
              temperature: 0.3,
            )) {
              buffer.write(token);
            }
            final raw = buffer.toString().trim();
            final result = _functionCallCoordinator.parse(raw);
            if (result is FunctionCallParsed) {
              return raw;
            }
          } catch (e) {
            debugPrint("LLM parsing failed: $e");
          }
        }
        return null;
    }
  }
}
