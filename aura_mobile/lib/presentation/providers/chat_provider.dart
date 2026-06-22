import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/domain/services/document_service.dart';
import 'package:aura_mobile/core/services/voice_service.dart';
import 'package:aura_mobile/features/orchestrator/orchestrator_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/presentation/providers/persona_provider.dart';
import 'package:aura_mobile/domain/services/context_builder_service.dart';

import 'package:uuid/uuid.dart';
import 'package:aura_mobile/domain/repositories/chat_history_repository.dart';
import 'package:aura_mobile/core/providers/repository_providers.dart';
import 'package:aura_mobile/presentation/providers/chat_history_provider.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';
import 'package:aura_mobile/presentation/providers/context_window_provider.dart';
import 'package:aura_mobile/features/automation/application/automation_engine.dart';
import 'package:aura_mobile/features/automation/domain/automation_rule.dart';

// Voice Service
final voiceServiceProvider = Provider((ref) => VoiceService());

// Chat State
class ChatState {
  final String? sessionId;
  final List<Map<String, String>> messages;
  final bool isListening;
  final bool isThinking;
  final String partialVoiceText;
  final bool isModelLoading;

  ChatState({
    this.sessionId,
    this.messages = const [],
    this.isThinking = false,
    this.isListening = false,
    this.partialVoiceText = '',
    this.isModelLoading = false,
  });

  ChatState copyWith({
    String? sessionId,
    List<Map<String, String>>? messages,
    bool? isThinking,
    bool? isListening,
    String? partialVoiceText,
    bool? isModelLoading,
  }) {
    return ChatState(
      sessionId: sessionId ?? this.sessionId,
      messages: messages ?? this.messages,
      isThinking: isThinking ?? this.isThinking,
      isListening: isListening ?? this.isListening,
      partialVoiceText: partialVoiceText ?? this.partialVoiceText,
      isModelLoading: isModelLoading ?? this.isModelLoading,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final Ref _ref;
  bool _isProcessing = false; // Mutex for concurrent call prevention
  final _uuid = const Uuid();

  ChatNotifier(this._ref) : super(ChatState()) {
    _initializeAI();
    _startNewSession();
  }

  void _startNewSession() {
    state = state.copyWith(
      sessionId: _uuid.v4(),
      messages: [],
      isThinking: false,
    );
  }

  Future<void> _initializeAI() async {
    try {
      state = state.copyWith(isModelLoading: true);
      final llmService = _ref.read(llmServiceProvider);
      await llmService.initialize();
      
      // Auto-load last selected model
      final prefs = await SharedPreferences.getInstance();
      final modelPath = prefs.getString('selected_model_path');
      
      if (modelPath != null && modelPath.isNotEmpty) {
        // Check if the last load crashed (e.g. native SIGSEGV)
        final crashed = prefs.getBool('model_load_crashed_sentinel') ?? false;
        if (crashed) {
          debugPrint('ChatNotifier: Detected crash during last model load. Clearing model path to prevent boot loop.');
          await prefs.remove('selected_model_path');
          await prefs.remove('active_model_id');
          await prefs.setBool('model_load_crashed_sentinel', false);
          return;
        }

        // Set sentinel before loading
        await prefs.setBool('model_load_crashed_sentinel', true);

        debugPrint('ChatNotifier: Auto-loading model from $modelPath');
        await llmService.loadModel(modelPath);

        // Clear sentinel on success
        await prefs.setBool('model_load_crashed_sentinel', false);
      } else {
        debugPrint('ChatNotifier: No model selected. User must select a model.');
      }
      _ref.read(contextWindowProvider.notifier).updateModelTier(llmService.modelTier);
    } catch (e) {
      debugPrint('Error initializing AI: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('model_load_crashed_sentinel', false);
      } catch (_) {}
    } finally {
      state = state.copyWith(isModelLoading: false);
    }
  }

  Future<void> loadSession(ChatSession session) async {
    // Load full session logic
    // Repository might return metadata only, check if messages are empty
    var fullSession = session;
    if (session.messages.isEmpty) {
        final repo = _ref.read(chatHistoryRepositoryProvider);
        final loaded = await repo.getSession(session.id);
        if (loaded != null) fullSession = loaded;
    }

    state = state.copyWith(
      sessionId: fullSession.id,
      messages: fullSession.messages,
    );
    _ref.read(contextWindowProvider.notifier).updateFromMessagesFast(state.messages);
  }

  // Debounce timer for _saveChat — collapses rapid save calls during streaming
  // into a single SQLite write 800ms after the last update. Prevents the
  // chat-history DB write (~30-100ms each) from being run on every token.
  Timer? _saveDebounce;

  Future<void> _saveChat() async {
    // Debounce: replace any pending save with a new one. The actual write
    // happens 800ms after the LAST call (which is typically when streaming
    // finishes), so the long conversation file is only written once per turn.
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _doSaveChat);
  }

  Future<void> _doSaveChat() async {
    if (state.messages.isEmpty) return;
    
    try {
      final repo = _ref.read(chatHistoryRepositoryProvider);
      
      // Generate a title based on the first user message if possible
      String title = "New Chat";
      final firstUserMsg = state.messages.firstWhere(
        (m) => m['role'] == 'user',
        orElse: () => {},
      );
      if (firstUserMsg.isNotEmpty && firstUserMsg['content'] != null) {
        final content = firstUserMsg['content']!;
        title = content.length > 30 ? "${content.substring(0, 30)}..." : content;
      }

      final session = ChatSession(
        id: state.sessionId ?? _uuid.v4(),
        title: title,
        lastModified: DateTime.now(),
        messages: state.messages,
      );

      // Update state ID if it was null (shouldn't be, but safe)
      if (state.sessionId == null) {
        state = state.copyWith(sessionId: session.id);
      }

      await repo.saveSession(session);
      // Invalidate history provider to refresh list
      _ref.invalidate(chatHistoryProvider);
    } catch (e) {
      debugPrint("Error saving chat: $e");
    }
  }

  /// Sends a [prompt] together with an [imageBytes] image to the active model
  /// for multimodal (vision) analysis. Only works when the active model
  /// reports vision support; otherwise it degrades to a text-only message.
  ///
  /// Vision goes straight to the model (bypassing the rule-based orchestrator
  /// intent layer) because the image itself is the context.
  Future<void> sendImageMessage(String prompt, Uint8List imageBytes) async {
    final modelState = _ref.read(modelSelectorProvider);
    if (modelState.activeModelId == null || state.isModelLoading) {
      return;
    }
    if (_isProcessing) return;

    final llmService = _ref.read(llmServiceProvider);
    // If the active model has no vision, degrade gracefully to a text turn so
    // the user still gets a response instead of a silent failure.
    if (!llmService.supportsVision) {
      await sendMessage(prompt);
      return;
    }

    _isProcessing = true;

    state = state.copyWith(
      messages: [...state.messages, {'role': 'user', 'content': prompt}],
      isThinking: true,
    );
    _saveChat();
    state = state.copyWith(
      messages: [...state.messages, {'role': 'assistant', 'content': ''}],
    );

    try {
      String fullResponse = '';
      await for (final chunk in llmService.chat(
        prompt,
        imageBytes: imageBytes,
        temperature: 0.4,
        maxTokens: 1024,
      )) {
        fullResponse += chunk;
        final cleaned = _truncateAtHallucination(fullResponse);
        if (cleaned != null) {
          fullResponse = cleaned;
          _updateLastMessage(fullResponse);
          break;
        }
        _updateLastMessage(fullResponse);
      }
      if (fullResponse.isEmpty) {
        _updateLastMessage(
            "I couldn't analyze that image. Try a clearer photo or a different model.");
      }
      _saveChat();
      _ref.read(contextWindowProvider.notifier).updateFromMessagesFast(state.messages);
    } catch (e) {
      debugPrint('Error in sendImageMessage: $e');
      _updateLastMessage(
          "I couldn't analyze that image. Make sure a vision model (e.g. Gemma 4) is loaded.");
    } finally {
      state = state.copyWith(isThinking: false);
      _isProcessing = false;
    }
  }

  Future<void> sendMessage(String text) async {
    // 0. Safety Checks
    final modelState = _ref.read(modelSelectorProvider);
    if (modelState.activeModelId == null || state.isModelLoading) {
      debugPrint('Model not ready, ignoring message');
      return;
    }

    // Prevent concurrent LLM calls
    if (_isProcessing) {
      debugPrint('Already processing a message, ignoring new request');
      return;
    }

    // Check conversation triggers
    try {
      final engine = _ref.read(automationEngineProvider);
      final rules = await engine.getAllRules();
      for (final rule in rules) {
        if (rule.isEnabled && rule.triggerType == TriggerType.conversationPattern) {
          final pattern = rule.condition ?? '';
          if (pattern.isNotEmpty && text.toLowerCase().contains(pattern.toLowerCase())) {
            _isProcessing = true;
            state = state.copyWith(
              messages: [...state.messages, {'role': 'user', 'content': text}],
              isThinking: true,
            );
            _saveChat();

            final result = await engine.executeRuleNow(rule);

            state = state.copyWith(
              messages: [
                ...state.messages,
                {
                  'role': 'system',
                  'content': 'automation_triggered:${rule.name} - $result'
                }
              ],
              isThinking: false,
            );
            _saveChat();
            _isProcessing = false;
            return; // Intercepted & processed by workflow
          }
        }
      }
    } catch (e) {
      debugPrint('ChatNotifier: Conversation trigger check failed: $e');
    }

    _isProcessing = true;

    // 0.5. Sync active persona system prompt
    try {
      final persona = _ref.read(personaProvider).activePersona;
      final contextBuilder = _ref.read(contextBuilderServiceProvider);
      contextBuilder.personaSystemPrompt = persona.systemPrompt;
    } catch (_) {
      // Persona provider may not be initialized yet
    }

    // 1. Add User Message
    state = state.copyWith(
      messages: [...state.messages, {'role': 'user', 'content': text}],
      isThinking: true,
    );
    _saveChat(); // Save after user message
    _ref.read(contextWindowProvider.notifier).updateFromMessagesFast(state.messages);
    final baselineTokens = _ref.read(contextWindowProvider).estimatedTokens;
    
    // Placeholder for Assistant Response
    state = state.copyWith(
      messages: [...state.messages, {'role': 'assistant', 'content': ''}],
    );

    try {
      final orchestrator = _ref.read(orchestratorServiceProvider);
      
      // Get chat history for context
      final allHistory = state.messages
            .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
            .map((m) => "${m['role'] == 'user' ? 'User' : 'Assistant'}: ${m['content']}")
            .toList();
            
      // Pass a generous slice of recent history; the context builder applies
      // the final, tier-aware pruning to fit the model's context window.
      final history = allHistory.length > 12
          ? allHistory.sublist(allHistory.length - 12)
          : allHistory;

      // Check if documents are available
      final documentService = _ref.read(documentServiceProvider);
      final hasDocuments = await documentService.hasDocuments();

      // Delegate to Orchestrator
      debugPrint("ChatNotifier: Delegating message to Orchestrator");
      final isConcise = _ref.read(conciseModeProvider);
      final stream = orchestrator.processMessage(
        message: isConcise 
            ? '$text\n\n[System Instruction: Please keep your response extremely concise, direct, and under 2-3 sentences.]'
            : text,
        chatHistory: history,
        hasDocuments: hasDocuments,
      );

      String fullResponse = '';
      bool emailMarkerHandled = false;
      await for (final chunk in stream) {
        // Intercept magic email draft marker emitted by orchestrator.
        // Insert system message for UI chip, then skip this chunk.
        if (!emailMarkerHandled && chunk.startsWith('__EMAIL_DRAFT__:')) {
          final address = chunk
              .replaceFirst('__EMAIL_DRAFT__:', '')
              .replaceAll('\n', '')
              .trim();
          // Insert the system message BEFORE the last assistant placeholder.
          // If we append it after, it becomes the last message and
          // _updateLastMessage() can't find the assistant bubble to stream into.
          final msgs = List<Map<String, String>>.from(state.messages);
          final lastAssistantIdx =
              msgs.lastIndexWhere((m) => m['role'] == 'assistant');
          if (lastAssistantIdx >= 0) {
            msgs.insert(lastAssistantIdx,
                {'role': 'system', 'content': 'drafting_email_to:$address'});
          } else {
            msgs.add(
                {'role': 'system', 'content': 'drafting_email_to:$address'});
          }
          state = state.copyWith(messages: msgs);
          emailMarkerHandled = true;
          continue; // Don't show the marker in the assistant response
        }
        fullResponse += chunk;

        // Anti-hallucination: check the FULL accumulated response for leaked
        // stop markers / fake conversation turns. If found, truncate and stop.
        final cleaned = _truncateAtHallucination(fullResponse);
        if (cleaned != null) {
          fullResponse = cleaned;
          _updateLastMessage(fullResponse);
          debugPrint('ChatNotifier: Hallucination marker detected — truncated response');
          break; // Stop consuming the stream entirely
        }

        _updateLastMessage(fullResponse);
        _ref.read(contextWindowProvider.notifier).updateStreamingTokens(baselineTokens, fullResponse);
      }
      debugPrint('ChatNotifier: Stream completed. Full response length: ${fullResponse.length}');
      _saveChat(); // Save after full response
      _ref.read(contextWindowProvider.notifier).updateFromMessagesFast(state.messages);

    } catch (e) {
      debugPrint('Error in sendMessage: $e');
      // Only show error if we have no partial response — otherwise keep what was generated
      final lastMsg = state.messages.isNotEmpty ? state.messages.last : null;
      final hasContent = lastMsg != null && 
          lastMsg['role'] == 'assistant' && 
          (lastMsg['content'] ?? '').trim().isNotEmpty;
      if (!hasContent) {
        // Retry once before giving up
        try {
          debugPrint('ChatNotifier: Retrying inference...');
          await Future.delayed(const Duration(milliseconds: 500));
          final orchestrator = _ref.read(orchestratorServiceProvider);
          final retryStream = orchestrator.processMessage(
            message: text,
            chatHistory: [],
            hasDocuments: false,
          );
          String retryResponse = '';
          await for (final chunk in retryStream) {
            retryResponse += chunk;
            _updateLastMessage(retryResponse);
          }
          if (retryResponse.isEmpty) {
            _updateLastMessage('The AI model is having trouble responding. Try restarting the app or using a simpler prompt.');
          }
        } catch (retryError) {
          debugPrint('ChatNotifier: Retry also failed: $retryError');
          _updateLastMessage('The AI model is having trouble responding. Try restarting the app or using a simpler prompt.');
        }
      }
    } finally {
      state = state.copyWith(isThinking: false);
      _isProcessing = false; // Release mutex
    }
  }



  /// Detects hallucinated stop markers / fake conversation turns in the full
  /// accumulated response. Returns the truncated clean text if a marker is
  /// found, or null if the response is still clean.
  ///
  /// Markers must appear at line-start (preceded by `\n`) for `Human:`/`User:`/
  /// `Assistant:` to avoid truncating legit prose like
  /// "I told the User: yes, I can help".
  static final List<String> _hallucinationMarkers = [
    // Unconditional control tokens — never appear in valid output
    '<|endoftext|>',
    '<|im_end|>',
    '<|im_start|>',
    '<|end|>',
    'CURRENT USER REQUEST',
    'ASSISTANT RESPONSE',
    'USER REQUEST',
    '__DISMISS__',
    // Line-start hallucination markers — model trying to fake a turn
    '\nHuman:',
    '\nUser:',
    '\nHuman :',
    '\nUser :',
    '\nAssistant:',
  ];

  String? _truncateAtHallucination(String response) {
    int earliestIdx = -1;
    for (final marker in _hallucinationMarkers) {
      final idx = response.indexOf(marker);
      if (idx >= 0 && (earliestIdx == -1 || idx < earliestIdx)) {
        earliestIdx = idx;
      }
    }
    if (earliestIdx >= 0) {
      return response.substring(0, earliestIdx).trimRight();
    }
    return null;
  }

  void _updateLastMessage(String newContent) {
    final newMessages = List<Map<String, String>>.from(state.messages);
    if (newMessages.isNotEmpty && newMessages.last['role'] == 'assistant') {
      newMessages.last = {'role': 'assistant', 'content': newContent};
      state = state.copyWith(messages: newMessages);
    }
  }

  Future<void> stopListening() async {
    final voiceService = _ref.read(voiceServiceProvider);
    await voiceService.stopListening();
    state = state.copyWith(isListening: false);
  }

  Future<void> startListening() async {
    final voiceService = _ref.read(voiceServiceProvider);

    // Ensure initialized
    final ok = await voiceService.initialize();
    if (!ok) {
      debugPrint('VoiceService initialization failed');
      return;
    }

    state = state.copyWith(isListening: true, partialVoiceText: '');

    await voiceService.startListening(onResult: (text, isFinal) {
      if (isFinal && text.isNotEmpty) {
        // Got final text — stop listening, send message, speak response, then listen again
        state = state.copyWith(isListening: false, partialVoiceText: '');
        _sendSpeakAndListenAgain(text);
      } else if (text.isNotEmpty) {
        // Partial — update live text
        state = state.copyWith(partialVoiceText: text);
      }
    });
  }

  /// Voice conversation loop: Send → Get AI response → Speak it → Listen again.
  /// This creates a continuous back-and-forth conversation experience.
  bool _isVoiceConversationActive = false;

  Future<void> _sendSpeakAndListenAgain(String text) async {
    _isVoiceConversationActive = true;

    // 1. Add User Message
    final modelState = _ref.read(modelSelectorProvider);
    if (modelState.activeModelId == null || state.isModelLoading) {
      _isVoiceConversationActive = false;
      return;
    }

    if (_isProcessing) {
      _isVoiceConversationActive = false;
      return;
    }
    _isProcessing = true;

    // Sync persona
    try {
      final persona = _ref.read(personaProvider).activePersona;
      final contextBuilder = _ref.read(contextBuilderServiceProvider);
      contextBuilder.personaSystemPrompt = persona.systemPrompt;
    } catch (_) {}

    state = state.copyWith(
      messages: [...state.messages, {'role': 'user', 'content': text}],
      isThinking: true,
    );
    _saveChat();

    state = state.copyWith(
      messages: [...state.messages, {'role': 'assistant', 'content': ''}],
    );

    String fullResponse = '';
    try {
      final orchestrator = _ref.read(orchestratorServiceProvider);
      final history = state.messages
          .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
          .map((m) => "${m['role'] == 'user' ? 'User' : 'Assistant'}: ${m['content']}")
          .toList();
      final limitedHistory = history.length > 3 ? history.sublist(history.length - 3) : history;

      final isConcise = _ref.read(conciseModeProvider);
      final stream = orchestrator.processMessage(
        message: isConcise
            ? '$text\n\n[System Instruction: Please keep your response extremely concise, direct, and under 2-3 sentences.]'
            : text,
        chatHistory: limitedHistory,
        hasDocuments: false,
        isVoiceQuery: true,
      );

      await for (final chunk in stream) {
        fullResponse += chunk;

        // If action completed (app opened, search done) — stop voice loop
        if (fullResponse.contains('__DISMISS__')) {
          fullResponse = fullResponse.replaceAll('__DISMISS__', '').trim();
          _updateLastMessage(fullResponse);
          _isVoiceConversationActive = false; // Stop the listen loop
          break;
        }

        // Anti-hallucination check
        final cleaned = _truncateAtHallucination(fullResponse);
        if (cleaned != null) {
          fullResponse = cleaned;
          _updateLastMessage(fullResponse);
          break;
        }
        _updateLastMessage(fullResponse);
      }

      _saveChat();
      _ref.read(contextWindowProvider.notifier).updateFromMessagesFast(state.messages);
    } catch (e) {
      debugPrint('Voice sendMessage error: $e');
      if (fullResponse.isEmpty) {
        fullResponse = "Sorry, I couldn't process that. Try again.";
        _updateLastMessage(fullResponse);
      }
    } finally {
      state = state.copyWith(isThinking: false);
      _isProcessing = false;
    }

    // 2. Speak the response
    if (fullResponse.isNotEmpty && _isVoiceConversationActive) {
      try {
        debugPrint('VOICE: Speaking response (${fullResponse.length} chars)');
        final voiceService = _ref.read(voiceServiceProvider);
        await voiceService.speak(fullResponse);
        debugPrint('VOICE: TTS done');
      } catch (e) {
        debugPrint('VOICE: TTS failed: $e');
      }
    }

    // 3. Automatically start listening again for continuous conversation
    if (_isVoiceConversationActive) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isVoiceConversationActive) {
        startListening();
      }
    }
  }

  /// Stop the continuous voice conversation loop
  void stopVoiceConversation() {
    _isVoiceConversationActive = false;
    final voiceService = _ref.read(voiceServiceProvider);
    voiceService.stopListening();
    voiceService.stopSpeaking();
    state = state.copyWith(isListening: false);
  }

  void clearChat() {
    // Stop any active voice conversation loop to prevent the mic from staying
    // open after the user clears the chat (battery + privacy fix).
    stopVoiceConversation();
    _startNewSession();
  }

  @override
  void dispose() {
    // Make sure the voice loop terminates when the notifier is destroyed —
    // otherwise the recursive startListening loop keeps holding the mic.
    _isVoiceConversationActive = false;
    try {
      final voiceService = _ref.read(voiceServiceProvider);
      voiceService.stopListening();
      voiceService.stopSpeaking();
    } catch (_) {/* best-effort cleanup */}
    _saveDebounce?.cancel();
    super.dispose();
  }

  void addOfflineMessage(Map<String, String> message) {
    state = state.copyWith(
      messages: [...state.messages, message],
    );
    _saveChat();
  }
}

class ConciseModeNotifier extends StateNotifier<bool> {
  ConciseModeNotifier() : super(false);
  void toggle() => state = !state;
}

final conciseModeProvider = StateNotifierProvider<ConciseModeNotifier, bool>((ref) {
  return ConciseModeNotifier();
});

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref);
});
