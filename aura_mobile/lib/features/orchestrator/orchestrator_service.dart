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
import 'package:aura_mobile/domain/services/llm_intent_classifier.dart';
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

final orchestratorServiceProvider = Provider((ref) {
  final orchestrator = OrchestratorService(
    ref.watch(intentDetectionServiceProvider),
    ref.watch(memoryServiceProvider),
    ref.watch(contextBuilderServiceProvider),
    ref.watch(llmServiceProvider),
    ref.watch(webServiceProvider),
    ref.watch(scraperServiceProvider),
    ref.watch(appControlServiceProvider),
    ref.watch(llmIntentClassifierProvider),
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
  final LLMIntentClassifier _llmClassifier;
  final WorkflowSplitterService _workflowSplitter;
  final StudyService _studyService;
  final SmartAppActionsService _smartAppActions;
  final ErrorHandlerService _errorHandler = ErrorHandlerService();
  WorkflowEngineService? _workflowEngine;

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
    this._llmClassifier,
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
  Stream<String> processMessage({
    required String message,
    required List<String> chatHistory,
    bool hasDocuments = false,
    bool isVoiceQuery = false,
    bool forceNormalChat = false,
  }) async* {
    // Sync model tier to context builder so prompts adapt to model size
    _contextBuilder.modelTier = _llmService.modelTier;
    // If forced to chat (e.g. email draft prompt), skip all intent detection
    if (forceNormalChat) {
      yield* _handleLLMFlow(message, chatHistory, includeMemories: true, includeDocuments: hasDocuments);
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
      // Fast-path guard: trivially short messages and greetings should NEVER
      // go through the tool-calling prompt — small models hallucinate tool calls
      // (e.g. "hy" → open_settings). Route them straight to chat.
      final msgTrimmed = message.trim();
      final msgLower = msgTrimmed.toLowerCase();
      final _greetGuard = RegExp(
        r'^(hi+|hey+|hello+|hai|heyy+|hyy*|yo+|sup|howdy|greetings|namaste|'
        r'good\s*(morning|afternoon|evening|night)|whats\s*up|'
        r'how\s+are\s+you|how\s+r\s+u|hows\s+it\s+going|thanks|thank\s+you|'
        r'ok|okay|bye|gm|gn|hola|bonjour|ciao)\s*[!?.]*$',
        caseSensitive: false,
      );
      final words = msgLower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final isShortNoKeyword = words.length <= 2 && !RegExp(
        r'\b(torch|flashlight|camera|photo|selfie|call|dial|sms|text|'
        r'email|mail|search|open|launch|remember|recall|settings|wifi|bluetooth)\b',
        caseSensitive: false,
      ).hasMatch(msgLower);
      if (_greetGuard.hasMatch(msgLower) || isShortNoKeyword) {
        yield* _handleLLMFlow(message, chatHistory, includeMemories: true, includeDocuments: hasDocuments);
        return;
      }
      yield* _handleFunctionCalling(message, chatHistory, hasDocuments: hasDocuments);
      return;
    }

    // 1. Check for compound multi-intent commands (Workflow Engine)
    if (!isVoiceQuery && !forceNormalChat) {
      final plan = await _workflowSplitter.splitWorkflow(message);
      if (plan != null && _workflowEngine != null) {
        debugPrint('ORCHESTRATOR: Handing off compound command to Workflow Engine');
        await for (final chunk in _workflowEngine!.execute(plan, chatHistory)) {
          yield chunk;
        }
        return;
      }
    }

    // 1. Rule-based Intent Detection (Layer 1)
    var intent = await _intentService.detectIntent(message, hasDocuments: hasDocuments);
    debugPrint("ORCHESTRATOR: Rule-based intent -> $intent");

    // 2. LLM Fallback Classification (Layer 2) — DISABLED
    // 
    // IMPORTANT: The on-device LLM (fllama) uses a SINGLE inference context.
    // Running the classifier here consumes that context, and if it times out
    // or runs long, the subsequent chat() call fails with AI_INFERENCE_FAILED
    // because the native engine is still processing the classification prompt.
    //
    // The rule-based detector (Layer 1) handles 50+ intent types and is fast.
    // For messages it can't classify, we simply go to normalChat — which is
    // correct 95% of the time for creative/conversational queries anyway.
    //
    // TODO: Re-enable when fllama supports multiple contexts or cancellation.
    ClassifiedIntent? classifiedIntent;


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
        try {
          final cleanQuery = _intentService.extractSearchQuery(message);
          yield "Searching for $cleanQuery";
          await _appControlService.openApp("navigate:https://www.google.com/search?q=${Uri.encodeComponent(cleanQuery)}");
          yield "__DISMISS__";
        } catch (e) {
          final errorMsg = _errorHandler.handleError(e);
          yield "Web search failed: $errorMsg";
        }
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
        final appName = classifiedIntent?.params['appName'] ?? _intentService.extractAppName(message);
        yield "Opening $appName";
        await _appControlService.openApp(appName);
        yield "__DISMISS__";
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
        yield "Opening Camera";
        await _appControlService.openCamera();
        yield "__DISMISS__";
        break;

      case IntentType.dialContact:
        final contactName = classifiedIntent?.params['contactName'] ?? _intentService.extractContactName(message);
        final matches = await _appControlService.resolveContacts(contactName);

        if (matches.isEmpty) {
           yield "Couldn't find a contact named $contactName. Try again with the exact name.";
        } else if (matches.length == 1) {
           final number = matches.first.phones.isNotEmpty ? matches.first.phones.first.number : '';
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
           final nameList = names.asMap().entries.map((e) => "${e.key + 1}. ${e.value.displayName}").join(", ");
           yield "I found ${names.length} contacts similar to $contactName: $nameList. Say the number or tap to select. [[OPTIONS:${names.map((c) {
              final number = c.phones.isNotEmpty ? c.phones.first.number : '';
              return "${c.displayName}|call $number";
           }).join(",")}]]";
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
              yield "Opening SMS to $name${smsBody.isNotEmpty ? ' with message: $smsBody' : ''}";
              await _appControlService.sendSMS(name, smsBody);
              yield "__DISMISS__";
           } else if (matches.length == 1) {
              final number = matches.first.phones.isNotEmpty ? matches.first.phones.first.number : '';
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
              final nameList = names.asMap().entries.map((e) => "${e.key + 1}. ${e.value.displayName}").join(", ");
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
        yield "Getting directions to $destination";
        await _appControlService.openApp("navigate:$destination");
        yield "__DISMISS__";
        break;

      case IntentType.weatherSearch:
        yield* _handleWebSearch("weather $message");
        break;

      case IntentType.viewCalendar:
        yield "📅 **Opening Calendar...**";
        await _appControlService.openApp("calendar");
        break;

      case IntentType.createEvent:
        yield "📅 **Creating event...**";
        await _appControlService.openApp("calendar");
        break;

      case IntentType.getNextEvent:
        yield "📅 **Checking next event...**";
        await _appControlService.openApp("calendar");
        break;

      case IntentType.mediaControl:
        final action = classifiedIntent?.params['action'] ?? 'play';
        yield "🎵 **Media: $action**";
        break;

      case IntentType.setBrightness:
        final level = classifiedIntent?.params['level'] ?? '50';
        yield "🔆 **Setting brightness to $level%...**";
        break;

      case IntentType.screenshot:
        yield "📸 **Taking screenshot...**";
        break;

      case IntentType.readMessages:
        final app = classifiedIntent?.params['app'] ?? '';
        yield "📬 **Reading messages${app.isNotEmpty ? ' from $app' : ''}...**";
        break;

      case IntentType.readNotifications:
        yield "🔔 **Reading notifications...**";
        break;

      case IntentType.createNote:
        final content = classifiedIntent?.params['content'] ?? '';
        yield "📝 **Creating note...**${content.isNotEmpty ? '\n"$content"' : ''}";
        break;

      case IntentType.calculate:
        final expression = classifiedIntent?.params['expression'] ?? message;
        yield "🧮 **Calculating: $expression**";
        yield* _handleLLMFlow("Calculate: $expression", chatHistory, includeMemories: false, includeDocuments: false);
        break;

      case IntentType.convert:
        yield* _handleLLMFlow("Convert: $message", chatHistory, includeMemories: false, includeDocuments: false);
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
        final contact = classifiedIntent?.params['contact'] ?? _extractWhatsAppContact(message);
        final msg = classifiedIntent?.params['message'] ?? _extractWhatsAppMessage(message);
        yield "Sending WhatsApp message to **$contact**...";
        try {
          await _smartAppActions.sendWhatsApp(contact, msg);
        } catch (e) {
          yield "Failed to send WhatsApp message: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.searchOnApp:
        final appName = classifiedIntent?.params['appName'] ?? '';
        final query = classifiedIntent?.params['query'] ?? '';
        yield "Searching **$query** on **$appName**...";
        try {
          await _smartAppActions.searchOnApp(appName, query);
        } catch (e) {
          yield "Failed to search: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.upiPayment:
        final upiId = classifiedIntent?.params['upiId'];
        final amount = classifiedIntent?.params['amount'];
        final note = classifiedIntent?.params['note'];
        final amountText = amount != null && amount.isNotEmpty ? " of Rs.$amount" : "";
        yield "Opening UPI payment$amountText...";
        try {
          await _smartAppActions.makeUpiPayment(
            upiId: upiId?.isNotEmpty == true ? upiId : null,
            amount: amount?.isNotEmpty == true ? amount : null,
            note: note?.isNotEmpty == true ? note : null,
          );
        } catch (e) {
          yield "Failed to open UPI: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.playOnSpotify:
        final query = classifiedIntent?.params['query'] ?? _extractSpotifyQuery(message);
        yield "Playing **$query** on Spotify...";
        try {
          await _smartAppActions.playOnSpotify(query);
        } catch (e) {
          yield "Failed to play on Spotify: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.bookRide:
        final destination = classifiedIntent?.params['destination'] ?? _extractRideDestination(message);
        final app = classifiedIntent?.params['app'];
        final appText = app != null && app.isNotEmpty ? " via $app" : "";
        yield "Booking a ride to **$destination**$appText...";
        try {
          await _smartAppActions.bookRide(
            destination,
            app: app?.isNotEmpty == true ? app : null,
          );
        } catch (e) {
          yield "Failed to book ride: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.orderFood:
        final restaurant = classifiedIntent?.params['restaurant'];
        final app = classifiedIntent?.params['app'];
        final restaurantText = restaurant != null && restaurant.isNotEmpty ? " from $restaurant" : "";
        final appText = app != null && app.isNotEmpty ? " on $app" : "";
        yield "Ordering food$restaurantText$appText...";
        try {
          await _smartAppActions.orderFood(
            restaurant: restaurant?.isNotEmpty == true ? restaurant : null,
            app: app?.isNotEmpty == true ? app : null,
          );
        } catch (e) {
          yield "Failed to order food: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.shareContent:
        final text = classifiedIntent?.params['text'] ?? '';
        final app = classifiedIntent?.params['app'];
        final appText = app != null && app.isNotEmpty ? " to $app" : "";
        yield "Sharing content$appText...";
        try {
          await _smartAppActions.shareText(
            text,
            app: app?.isNotEmpty == true ? app : null,
          );
        } catch (e) {
          yield "Failed to share: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.openProfile:
        final platform = classifiedIntent?.params['platform'] ?? '';
        final username = classifiedIntent?.params['username'] ?? '';
        yield "Opening **@$username** on **$platform**...";
        try {
          await _smartAppActions.openProfile(platform, username);
        } catch (e) {
          yield "Failed to open profile: ${_errorHandler.handleError(e)}";
        }
        break;

      case IntentType.normalChat:
        // For small models (0.5B): auto-redirect factual questions to web search
        // Small models hallucinate heavily on knowledge questions
        if (_llmService.modelTier.isSmall && _looksFactual(message) && !hasDocuments) {
          debugPrint('ORCHESTRATOR: Small model detected factual question, redirecting to web search');
          yield* _handleWebSearch(message);
        } else {
          yield* _handleLLMFlow(message, chatHistory, includeMemories: true, includeDocuments: hasDocuments);
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
      ToolDefinition(name: 'store_memory', parameters: [
        ToolParameter(name: 'content', required: true),
      ]),
      ToolDefinition(name: 'retrieve_memory', parameters: [
        ToolParameter(name: 'query', required: true),
      ]),
      ToolDefinition(name: 'web_search', parameters: [
        ToolParameter(name: 'query', required: true),
      ]),
      ToolDefinition(name: 'scrape_url', parameters: [
        ToolParameter(name: 'url', required: true),
      ]),
      ToolDefinition(name: 'open_app', parameters: [
        ToolParameter(name: 'appName', required: true),
      ]),
      ToolDefinition(name: 'open_settings', parameters: [
        ToolParameter(name: 'type'),
      ]),
      ToolDefinition(name: 'open_camera'),
      ToolDefinition(name: 'dial_contact', parameters: [
        ToolParameter(name: 'contactName', required: true),
      ]),
      ToolDefinition(name: 'send_sms', parameters: [
        ToolParameter(name: 'name', required: true),
        ToolParameter(name: 'message'),
      ]),
      ToolDefinition(name: 'set_reminder', parameters: [
        ToolParameter(name: 'time', required: true),
        ToolParameter(name: 'title'),
      ]),
      ToolDefinition(name: 'navigation', parameters: [
        ToolParameter(name: 'destination', required: true),
      ]),
      ToolDefinition(name: 'toggle_torch', parameters: [
        ToolParameter(name: 'state'),
      ]),
      ToolDefinition(name: 'generate_image', parameters: [
        ToolParameter(name: 'prompt', required: true),
      ]),
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
      ..writeln('You are AURA, an on-device assistant that can call tools.')
      ..writeln('When the user request maps to a tool, reply with ONLY a JSON '
          'object of the form {"name": "<tool>", "arguments": { ... }} and '
          'nothing else.')
      ..writeln('If no tool applies, answer the user normally in plain text.')
      ..writeln()
      ..writeln('Available tools:');
    for (final tool in tools) {
      final params = tool.parameters
          .map((p) => '${p.name}${p.required ? ' (required)' : ''}')
          .join(', ');
      buffer.writeln('- ${tool.name}($params)');
    }
    return buffer.toString();
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
            // Tool calls always start with `{` (JSON object)
            isToolCall = RegExp(r'^\{\s*"(name|tool|toolName|function)"\s*:').hasMatch(preview);
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
      isToolCall = RegExp(r'^\{\s*"(name|tool|toolName|function)"\s*:').hasMatch(preview);
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
    final result = _functionCallCoordinator.parse(raw);

    switch (result) {
      case FunctionCallParsed(:final request):
        debugPrint('ORCHESTRATOR: Function call -> ${request.toolName} ${request.arguments}');
        yield* _dispatchToolCall(request, chatHistory, hasDocuments: hasDocuments);
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
        final reminderMessage =
            title.isNotEmpty ? 'remind me to $title at $time' : 'remind me at $time';
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
        final state = !(stateArg == 'off' || stateArg == 'false' || stateArg == 'disable');
        yield state ? "💡 **Turning Flashlight ON...**" : "🌑 **Turning Flashlight OFF...**";
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
      final number = matches.first.phones.isNotEmpty ? matches.first.phones.first.number : '';
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
      final number = matches.first.phones.isNotEmpty ? matches.first.phones.first.number : '';
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

  Stream<String> _handleWebSearch(String message) async* {
    try {
      final cleanQuery = _intentService.extractSearchQuery(message);
      yield "🔍 **Searching the web for: '$cleanQuery'**...\n\n";
      _errorHandler.logInfo("Web search: '$cleanQuery'");

      final results = await _webService.search(cleanQuery);

      if (results.isEmpty) {
        yield "I couldn't find any recent information for '$cleanQuery'. Try rephrasing your query.";
        return;
      }

      final prompt = _contextBuilder.injectWeb(results, cleanQuery);

      // 1. Stream the synthesized answer from AI — grounded in search results
      final isSmall = _llmService.modelTier.isSmall;
      yield* _llmService.chat(
        prompt,
        systemPrompt: isSmall
            ? "Answer using ONLY the search results above. If not found, say so."
            : "You have web access. Use ONLY the Search Results provided below to answer the user. If the results don't fully answer the question, state what you found and what is missing. Never invent facts not present in the results.",
        temperature: 0.3,
        maxTokens: isSmall ? 256 : 512, // Shorter output for small models = less room to hallucinate
      );

      // 2. Append top 5 sources at the end
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

      if (content.snippet.isEmpty || content.snippet == 'No readable content found') {
        yield "I couldn't extract readable content from that webpage. It may contain only images or restricted content.";
        return;
      }

      final prompt = _contextBuilder.injectURL(content, message);
      yield* _llmService.chat(
        prompt,
        systemPrompt: "You are analyzing a specific webpage. Summarize ONLY the content provided in the context to answer the user. Do NOT add information not found in the provided content. The content has already been fetched for you.",
        temperature: 0.3,
      );
    } catch (e) {
      _errorHandler.handleError(e);
      rethrow;
    }
  }

  Stream<String> _handleEmailDraft(String message) async* {
    final address = _intentService.extractEmailAddress(message) ?? 'the recipient';
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
  }) async* {
    final prompt = await _contextBuilder.buildPrompt(
      userMessage: message,
      chatHistory: history,
      includeMemories: includeMemories,
      includeDocuments: includeDocuments,
    );

    final tier = _llmService.modelTier;
    final lowerMsg = message.toLowerCase();

    // ── Detect if this is a long-form writing task ──────────────────────────
    final needsMoreTokens = lowerMsg.contains('write') ||
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

    // ── Token budget: capped aggressively for small/medium models ───────────
    // Qwen 1.5B hallucinates and repeats when given too many tokens to fill.
    // Short answers = faster + more accurate. Writing tasks get more room.
    final int maxTokens;
    if (tier.isSmall) {
      maxTokens = needsMoreTokens ? 384 : 192; // 0.5B: very tight budget
    } else if (tier == ModelTier.medium) {
      maxTokens = needsMoreTokens ? 512 : 256; // 1.5B: moderate budget
    } else {
      maxTokens = needsMoreTokens ? 1024 : 512; // 3B+: full budget
    }

    // ── Temperature: factual/grounded tasks get lower temp to reduce hallucination
    // Medium models (1.5B) should always run cooler — they hallucinate more
    // at high temperatures than larger models do.
    final double temperature;
    if (includeDocuments || includeMemories) {
      temperature = 0.3; // RAG mode: stay close to source
    } else if (tier.isSmall || tier == ModelTier.medium) {
      temperature = 0.4; // Small/medium models: less creative wandering
    } else {
      temperature = 0.65; // Large models: slightly creative but not wild
    }

    yield* _llmService.chat(prompt, temperature: temperature, maxTokens: maxTokens);
  }

  /// Heuristic: does this message look like a factual/knowledge question?
  /// Used to redirect small-model users to web search instead of hallucinated answers.
  bool _looksFactual(String message) {
    final lower = message.toLowerCase().trim();

    // Question patterns that need real-world knowledge
    final factualPatterns = RegExp(
      r'\b(who is|who was|what is|what are|what was|when did|when was|where is|where was|'
      r'how many|how much|how old|how tall|how far|capital of|president of|'
      r'population of|founder of|ceo of|meaning of|definition of|'
      r'latest|current|today|newest|recent|score|result|news|'
      r'born in|died in|invented|discovered|created by|made by|'
      r'which country|which city|which year|in what year)\b',
      caseSensitive: false,
    );

    // Conversational patterns that DON'T need web search
    final conversationalPatterns = RegExp(
      r'\b(help me|write|create|generate|compose|draft|make|build|code|explain this|'
      r'translate|summarize|rewrite|improve|fix|how to|how do i|how can i|'
      r'tell me a joke|hello|hi |hey |thanks|thank you|good morning|good night|'
      r'remind me|remember|what do you think|your opinion)\b',
      caseSensitive: false,
    );

    // Only redirect if it matches factual AND doesn't match conversational
    return factualPatterns.hasMatch(lower) && !conversationalPatterns.hasMatch(lower);
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
        examDate = _parseSimpleDate(dateMatch.group(1)!) ?? DateTime.now().add(const Duration(days: 7));
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

  DateTime? _parseSimpleDate(String dateStr) {
    try {
      final months = {
        'jan': 1, 'january': 1, 'feb': 2, 'february': 2,
        'mar': 3, 'march': 3, 'apr': 4, 'april': 4,
        'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7,
        'aug': 8, 'august': 8, 'sep': 9, 'september': 9,
        'oct': 10, 'october': 10, 'nov': 11, 'november': 11,
        'dec': 12, 'december': 12,
      };
      final parts = dateStr.trim().split(RegExp(r'[\s,]+'));
      if (parts.length >= 2) {
        final month = months[parts[0].toLowerCase()];
        final day = int.tryParse(parts[1].replaceAll(RegExp(r'[^\d]'), ''));
        if (month != null && day != null) {
          final year = parts.length >= 3 ? int.tryParse(parts[2]) ?? DateTime.now().year : DateTime.now().year;
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
        final state = !(lo.contains("off") || lo.contains("disable") || lo.contains("stop"));
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
