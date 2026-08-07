import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/app_navigator.dart';
import 'package:aura_mobile/core/services/speech_chunker.dart';
import 'package:aura_mobile/domain/services/document_service.dart';
import 'package:aura_mobile/core/services/voice_service.dart';
import 'package:aura_mobile/features/orchestrator/orchestrator_service.dart';
import 'package:aura_mobile/features/interactive_agent/interactive_agent_providers.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
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
  bool _cancelRequested = false;
  int _generationSequence = 0;
  int? _activeGenerationId;
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
      final router = _ref.read(llmRouterProvider);
      await router.initialize();

      final prefs = await SharedPreferences.getInstance();
      final isOffline = prefs.getString('active_llm_backend') != 'online';
      final crashed = prefs.getBool('model_load_crashed_sentinel') ?? false;
      if (isOffline && crashed) {
        debugPrint(
          'ChatNotifier: Detected crash during the previous local model load.',
        );
        await router.removeLocalSelection();
        await prefs.setBool('model_load_crashed_sentinel', false);
        return;
      }

      await router.restoreActiveSelection();
      if (!router.isModelLoaded) {
        debugPrint('ChatNotifier: No usable local or online model selected.');
      }
      _ref
          .read(contextWindowProvider.notifier)
          .updateModelTier(router.modelTier);
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
    _ref
        .read(contextWindowProvider.notifier)
        .updateFromMessagesFast(state.messages);
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
        title = content.length > 30
            ? "${content.substring(0, 30)}..."
            : content;
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
  /// True when either a local model or an explicitly selected online model can
  /// serve the turn.
  bool _hasUsableModel() {
    if (_ref.read(modelSelectorProvider).activeModelId != null) return true;
    return _ref.read(llmRouterProvider).isModelLoaded;
  }

  Future<void> sendImageMessage(String prompt, Uint8List imageBytes) async {
    if (!_hasUsableModel() || state.isModelLoading) {
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
      messages: [
        ...state.messages,
        {'role': 'user', 'content': prompt},
      ],
      isThinking: true,
    );
    _saveChat();
    state = state.copyWith(
      messages: [
        ...state.messages,
        {'role': 'assistant', 'content': ''},
      ],
    );

    try {
      String fullResponse = '';
      await for (final chunk in llmService.chat(
        prompt,
        imageBytes: imageBytes,
        temperature: 0.4,
        maxTokens: 1024,
      )) {
        final scannedUpTo = fullResponse.length;
        fullResponse += chunk;
        final cleaned = _truncateAtHallucination(
          fullResponse,
          scannedUpTo: scannedUpTo,
        );
        if (cleaned != null) {
          fullResponse = cleaned;
          break;
        }
        _queueStreamUpdate(fullResponse);
      }
      _commitStreamUpdate(fullResponse);
      if (fullResponse.isEmpty) {
        _updateLastMessage(
          "I couldn't analyze that image. Try a clearer photo or a different model.",
        );
      }
      _saveChat();
      _ref
          .read(contextWindowProvider.notifier)
          .updateFromMessagesFast(state.messages);
    } catch (e) {
      _cancelStreamUpdates();
      debugPrint('Error in sendImageMessage: $e');
      _updateLastMessage(
        "I couldn't analyze that image. Make sure a vision model (e.g. Gemma 4) is loaded.",
      );
    } finally {
      _cancelStreamUpdates();
      state = state.copyWith(isThinking: false);
      _isProcessing = false;
    }
  }

  Future<void> sendMessage(String text) async {
    // 0. Safety Checks
    if (!_hasUsableModel() || state.isModelLoading) {
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
        if (rule.isEnabled &&
            rule.triggerType == TriggerType.conversationPattern) {
          final pattern = rule.condition ?? '';
          if (pattern.isNotEmpty &&
              text.toLowerCase().contains(pattern.toLowerCase())) {
            _isProcessing = true;
            state = state.copyWith(
              messages: [
                ...state.messages,
                {'role': 'user', 'content': text},
              ],
              isThinking: true,
            );
            _saveChat();

            final result = await engine.executeRuleNow(rule);

            state = state.copyWith(
              messages: [
                ...state.messages,
                {
                  'role': 'system',
                  'content': 'automation_triggered:${rule.name} - $result',
                },
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
    _cancelRequested = false;
    final generationId = ++_generationSequence;
    _activeGenerationId = generationId;
    bool isCancelled() =>
        _cancelRequested || _activeGenerationId != generationId;
    OrchestratorService? requestOrchestrator;
    List<String> requestHistory = const [];
    var requestHasDocuments = false;
    var requestIsConcise = false;

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
      messages: [
        ...state.messages,
        {'role': 'user', 'content': text},
      ],
      isThinking: true,
    );
    _saveChat(); // Save after user message
    _ref
        .read(contextWindowProvider.notifier)
        .updateFromMessagesFast(state.messages);
    final baselineTokens = _ref.read(contextWindowProvider).estimatedTokens;

    // Placeholder for Assistant Response
    state = state.copyWith(
      messages: [
        ...state.messages,
        {'role': 'assistant', 'content': ''},
      ],
    );

    try {
      final orchestrator = _ref.read(orchestratorServiceProvider);
      requestOrchestrator = orchestrator;

      // Get chat history for context
      final allHistory = state.messages
          .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
          .map(
            (m) =>
                "${m['role'] == 'user' ? 'User' : 'Assistant'}: ${m['content']}",
          )
          .toList();

      // Pass a generous slice of recent history; the context builder applies
      // the final, tier-aware pruning to fit the model's context window.
      final history = allHistory.length > 12
          ? allHistory.sublist(allHistory.length - 12)
          : allHistory;
      requestHistory = history;

      // Check if documents are available
      final documentService = _ref.read(documentServiceProvider);
      final hasDocuments = await documentService.hasDocuments();
      requestHasDocuments = hasDocuments;

      // Delegate to Orchestrator
      debugPrint("ChatNotifier: Delegating message to Orchestrator");
      final isConcise = _ref.read(conciseModeProvider);
      requestIsConcise = isConcise;
      final stream = orchestrator.processMessage(
        message: text,
        chatHistory: history,
        hasDocuments: hasDocuments,
        isConcise: isConcise,
      );

      String fullResponse = '';
      bool emailMarkerHandled = false;
      await for (final rawChunk in stream) {
        if (isCancelled()) break;
        // Navigation markers are control signals, not text. Strip them and open
        // the requested screen instead of printing the marker in the bubble.
        final chunk = _consumeNavigationMarkers(rawChunk);
        if (chunk.isEmpty) continue;
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
          final lastAssistantIdx = msgs.lastIndexWhere(
            (m) => m['role'] == 'assistant',
          );
          if (lastAssistantIdx >= 0) {
            msgs.insert(lastAssistantIdx, {
              'role': 'system',
              'content': 'drafting_email_to:$address',
            });
          } else {
            msgs.add({
              'role': 'system',
              'content': 'drafting_email_to:$address',
            });
          }
          state = state.copyWith(messages: msgs);
          emailMarkerHandled = true;
          continue; // Don't show the marker in the assistant response
        }
        final scannedUpTo = fullResponse.length;
        fullResponse += chunk;

        // Anti-hallucination: check for leaked stop markers / fake conversation
        // turns. Only the newly arrived tail is scanned. If found, truncate and
        // stop.
        final cleaned = _truncateAtHallucination(
          fullResponse,
          scannedUpTo: scannedUpTo,
        );
        if (cleaned != null) {
          fullResponse = cleaned;
          _commitStreamUpdate(fullResponse, baselineTokens: baselineTokens);
          debugPrint(
            'ChatNotifier: Hallucination marker detected — truncated response',
          );
          break; // Stop consuming the stream entirely
        }

        _queueStreamUpdate(fullResponse, baselineTokens: baselineTokens);
      }
      // Publish whatever is still buffered before leaving the streaming path.
      _commitStreamUpdate(fullResponse, baselineTokens: baselineTokens);
      if (isCancelled()) {
        debugPrint('ChatNotifier: Generation cancelled by user.');
        _saveChat();
        return;
      }
      debugPrint(
        'ChatNotifier: Stream completed. Full response length: ${fullResponse.length}',
      );
      _saveChat(); // Save after full response
      _ref
          .read(contextWindowProvider.notifier)
          .updateFromMessagesFast(state.messages);
    } catch (error) {
      // Drop any buffered chunk so a late flush can't overwrite the message
      // this handler is about to write.
      _cancelStreamUpdates();
      if (error is GenerationCancelledException || isCancelled()) {
        debugPrint('ChatNotifier: Generation cancelled by user.');
        _saveChat();
        return;
      }
      debugPrint('Error in sendMessage: $error');
      final lastMsg = state.messages.isNotEmpty ? state.messages.last : null;
      final hasContent =
          lastMsg != null &&
          lastMsg['role'] == 'assistant' &&
          (lastMsg['content'] ?? '').trim().isNotEmpty;
      if (!hasContent &&
          requestOrchestrator != null &&
          _isRetryableGenerationError(error)) {
        try {
          debugPrint('ChatNotifier: Retrying inference...');
          if (isCancelled()) return;
          await Future.delayed(const Duration(milliseconds: 500));
          if (isCancelled()) return;
          final retryStream = requestOrchestrator.processMessage(
            message: text,
            chatHistory: requestHistory,
            hasDocuments: requestHasDocuments,
            isConcise: requestIsConcise,
          );
          if (isCancelled()) return;
          String retryResponse = '';
          await for (final rawChunk in retryStream) {
            if (isCancelled()) break;
            final chunk = _consumeNavigationMarkers(rawChunk);
            if (chunk.isEmpty) continue;
            final scannedUpTo = retryResponse.length;
            retryResponse += chunk;
            final cleaned = _truncateAtHallucination(
              retryResponse,
              scannedUpTo: scannedUpTo,
            );
            if (cleaned != null) {
              retryResponse = cleaned;
              break;
            }
            _queueStreamUpdate(retryResponse);
          }
          _commitStreamUpdate(retryResponse);
          if (isCancelled()) {
            _saveChat();
            return;
          }
          if (retryResponse.isEmpty) {
            _updateLastMessage(
              'The AI model is having trouble responding. Try restarting the app or using a simpler prompt.',
            );
          }
        } catch (retryError) {
          if (retryError is GenerationCancelledException || isCancelled()) {
            debugPrint('ChatNotifier: Retry cancelled by user.');
            _saveChat();
            return;
          }
          debugPrint('ChatNotifier: Retry also failed: $retryError');
          _updateLastMessage(
            'The AI model is having trouble responding. Try restarting the app or using a simpler prompt.',
          );
        }
      } else if (!hasContent) {
        _updateLastMessage(
          error is AIServiceException
              ? error.userMessage
              : 'The AI model could not respond. Please try again.',
        );
      }
    } finally {
      _cancelStreamUpdates();
      if (_activeGenerationId == generationId) {
        state = state.copyWith(isThinking: false);
        _isProcessing = false;
        _cancelRequested = false;
        _activeGenerationId = null;
      }
    }
  }

  /// Removes `__NAVIGATE__:<target>` control markers from [chunk] and performs
  /// the requested navigation. Returns the displayable remainder.
  String _consumeNavigationMarkers(String chunk) {
    if (!chunk.contains(AppNavigator.marker)) return chunk;

    return chunk.replaceAllMapped(
      RegExp('${RegExp.escape(AppNavigator.marker)}([a-z_]+)'),
      (match) {
        final target = match.group(1) ?? '';
        if (!AppNavigator.open(target)) {
          debugPrint('ChatNotifier: unknown navigation target "$target"');
        }
        return '';
      },
    );
  }

  bool _isRetryableGenerationError(Object error) {
    if (error is! AIServiceException) return false;
    return const {
      'AI_PROVIDER_TIMEOUT',
      'AI_PROVIDER_OFFLINE',
      'AI_PROVIDER_REQUEST_FAILED',
      'AI_PROVIDER_INCOMPLETE_STREAM',
      'AI_INFERENCE_TIMEOUT',
    }.contains(error.errorCode);
  }

  Future<void> stopGeneration() async {
    if (!_isProcessing) return;
    _cancelRequested = true;
    final service = _ref.read(llmServiceProvider);
    if (service is CancellableLLMService) {
      await (service as CancellableLLMService).cancelGeneration();
    }
    state = state.copyWith(isThinking: false);
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

  /// Longest marker length, used to overlap the scan window so a marker that
  /// straddles two chunks is still detected.
  static final int _longestMarkerLength = _hallucinationMarkers
      .map((m) => m.length)
      .reduce((a, b) => a > b ? a : b);

  /// [scannedUpTo] is the length of [response] that was already checked by a
  /// previous call. Only the new tail (plus a marker-length overlap) is
  /// re-scanned, so the check costs O(chunk) per token instead of O(response) —
  /// the old behaviour re-scanned the whole answer against 13 markers on every
  /// single token, which grew quadratically over a long reply.
  String? _truncateAtHallucination(String response, {int scannedUpTo = 0}) {
    var from = scannedUpTo - _longestMarkerLength;
    if (from < 0) from = 0;

    int earliestIdx = -1;
    for (final marker in _hallucinationMarkers) {
      final idx = response.indexOf(marker, from);
      if (idx >= 0 && (earliestIdx == -1 || idx < earliestIdx)) {
        earliestIdx = idx;
      }
    }
    if (earliestIdx >= 0) {
      return response.substring(0, earliestIdx).trimRight();
    }
    return null;
  }

  // ── Streaming update coalescing ───────────────────────────────────────────
  // Models emit tokens far faster than the UI can usefully repaint (commonly
  // 30-60 chunks/second). Publishing new state per chunk forced a full
  // rebuild — and a full markdown re-parse of the growing answer — per token,
  // which overran the frame budget and made the screen feel frozen while a
  // reply was coming in. Chunks are buffered instead and written to state at
  // most once per [_streamFlushInterval], so text still flows continuously but
  // at a repaint rate the device can actually sustain.
  static const Duration _streamFlushInterval = Duration(milliseconds: 60);
  Timer? _streamFlushTimer;
  String? _pendingStreamText;
  int _streamBaselineTokens = 0;

  /// Buffers [content] as the latest assistant text, scheduling a flush.
  void _queueStreamUpdate(String content, {int? baselineTokens}) {
    if (baselineTokens != null) _streamBaselineTokens = baselineTokens;
    _pendingStreamText = content;
    _streamFlushTimer ??= Timer(_streamFlushInterval, () {
      _streamFlushTimer = null;
      final pending = _pendingStreamText;
      if (pending == null) return;
      _pendingStreamText = null;
      _writeStreamText(pending);
    });
  }

  /// Writes [content] immediately and drops any queued flush. Used at turn
  /// boundaries (stream end, truncation, cancel, error) so the final text is
  /// never left sitting in the buffer.
  void _commitStreamUpdate(String content, {int? baselineTokens}) {
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _pendingStreamText = null;
    if (baselineTokens != null) _streamBaselineTokens = baselineTokens;
    _writeStreamText(content);
  }

  /// Discards buffered text without publishing it.
  void _cancelStreamUpdates() {
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _pendingStreamText = null;
  }

  void _writeStreamText(String content) {
    _updateLastMessage(content);
    // Token estimate rides along with the text update instead of firing its
    // own notification per chunk (that was a second full rebuild per token).
    _ref
        .read(contextWindowProvider.notifier)
        .updateStreamingTokens(_streamBaselineTokens, content);
  }

  void _updateLastMessage(String newContent) {
    final messages = state.messages;
    if (messages.isEmpty || messages.last['role'] != 'assistant') return;
    // Identical text would still hand the UI a brand-new list and trigger a
    // rebuild, so drop the write entirely.
    if (messages.last['content'] == newContent) return;

    final newMessages = List<Map<String, String>>.from(messages);
    newMessages.last = {'role': 'assistant', 'content': newContent};
    state = state.copyWith(messages: newMessages);
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

    await voiceService.startListening(
      onResult: (text, isFinal) {
        if (isFinal && text.isNotEmpty) {
          // Got final text — stop listening.
          state = state.copyWith(isListening: false, partialVoiceText: '');
          // When Interactive Mode is active, a spoken phrase is a command for
          // the agent, not a chat turn. Submit it and do NOT re-enter the voice
          // conversation loop (the agent run drives the interaction instead).
          final interactive = _ref.read(interactiveModeControllerProvider);
          if (interactive.active) {
            _ref
                .read(interactiveModeControllerProvider.notifier)
                .submitCommand(text);
            return;
          }
          // Otherwise: send message, speak response, then listen again.
          _sendSpeakAndListenAgain(text);
        } else if (text.isNotEmpty) {
          // Partial — update live text
          state = state.copyWith(partialVoiceText: text);
        }
      },
    );
  }

  /// Voice conversation loop: Send → Get AI response → Speak it → Listen again.
  /// This creates a continuous back-and-forth conversation experience.
  bool _isVoiceConversationActive = false;

  Future<void> _sendSpeakAndListenAgain(String text) async {
    _isVoiceConversationActive = true;

    // 1. Add User Message
    if (!_hasUsableModel() || state.isModelLoading) {
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
      messages: [
        ...state.messages,
        {'role': 'user', 'content': text},
      ],
      isThinking: true,
    );
    _saveChat();

    state = state.copyWith(
      messages: [
        ...state.messages,
        {'role': 'assistant', 'content': ''},
      ],
    );

    // Voice flows through the orchestrator like text chat. The orchestrator
    // decides internally whether a message needs web search (only for genuine
    // real-time info) or a direct model answer — so voice stays conversational.
    String fullResponse = '';
    final voiceService = _ref.read(voiceServiceProvider);

    // Streaming TTS: speak sentences as they arrive instead of waiting for full response
    final chunker = SpeechChunker();
    bool firstSentenceSpoken = false;

    try {
      // Wait out any in-flight generation so the spoken turn is not rejected.
      await _ref.read(llmRouterProvider).waitUntilIdle();
      final orchestrator = _ref.read(orchestratorServiceProvider);
      final history = state.messages
          .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
          .map(
            (m) =>
                "${m['role'] == 'user' ? 'User' : 'Assistant'}: ${m['content']}",
          )
          .toList();
      final limitedHistory = history.length > 3
          ? history.sublist(history.length - 3)
          : history;

      final isConcise = _ref.read(conciseModeProvider);
      final stream = orchestrator.processMessage(
        message: text,
        chatHistory: limitedHistory,
        hasDocuments: false,
        isVoiceQuery: true,
        isConcise: isConcise,
        isVoice: true,
      );

      await for (final rawChunk in stream) {
        var chunk = _consumeNavigationMarkers(rawChunk);
        var stopAfterChunk = false;

        // If action completed (app opened, search done) — stop voice loop
        if (chunk.contains('__DISMISS__')) {
          chunk = chunk.replaceAll('__DISMISS__', '');
          _isVoiceConversationActive = false;
          stopAfterChunk = true;
        }

        // Anti-hallucination: keep only text produced before a fake turn.
        final candidate = fullResponse + chunk;
        final marker = _truncateAtHallucination(candidate);
        if (marker != null) {
          chunk = marker.length > fullResponse.length
              ? marker.substring(fullResponse.length)
              : '';
          stopAfterChunk = true;
        }

        fullResponse += chunk;
        _queueStreamUpdate(fullResponse);

        // STREAMING TTS: speak as soon as a speakable chunk is available.
        if (_isVoiceConversationActive) {
          chunker.add(chunk);
          String? toSpeak;
          while ((toSpeak = chunker.takeChunk()) != null) {
            if (!firstSentenceSpoken) {
              firstSentenceSpoken = true;
              debugPrint('VOICE: first spoken chunk ready');
            }
            await voiceService.speakChunk(toSpeak!);
          }
        }

        if (stopAfterChunk) break;
      }
      _commitStreamUpdate(fullResponse);

      // Speak any remaining text that didn't end with punctuation
      final remaining = chunker.drain();
      if (remaining != null && _isVoiceConversationActive) {
        await voiceService.speakChunk(remaining);
      }
      if (fullResponse.trim().isEmpty && _isVoiceConversationActive) {
        fullResponse = "I didn't catch an answer for that. Please ask again.";
        _commitStreamUpdate(fullResponse);
        await voiceService.speakChunk(fullResponse);
      }
      voiceService.markSpeakingDone();

      _saveChat();
      _ref
          .read(contextWindowProvider.notifier)
          .updateFromMessagesFast(state.messages);
    } catch (e) {
      _cancelStreamUpdates();
      debugPrint('Voice sendMessage error: $e');
      if (fullResponse.isEmpty) {
        fullResponse = "Sorry, I couldn't process that. Try again.";
        _updateLastMessage(fullResponse);
        if (_isVoiceConversationActive) {
          await voiceService.speakChunk(fullResponse);
          voiceService.markSpeakingDone();
        }
      }
    } finally {
      _cancelStreamUpdates();
      voiceService.markSpeakingDone();
      state = state.copyWith(isThinking: false);
      _isProcessing = false;
    }

    // Automatically start listening again for continuous conversation
    if (_isVoiceConversationActive) {
      await Future.delayed(const Duration(milliseconds: 300));
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
    } catch (_) {
      /* best-effort cleanup */
    }
    _saveDebounce?.cancel();
    _cancelStreamUpdates();
    super.dispose();
  }

  void addOfflineMessage(Map<String, String> message) {
    state = state.copyWith(messages: [...state.messages, message]);
    _saveChat();
  }
}

class ConciseModeNotifier extends StateNotifier<bool> {
  ConciseModeNotifier() : super(false);
  void toggle() => state = !state;
}

final conciseModeProvider = StateNotifierProvider<ConciseModeNotifier, bool>((
  ref,
) {
  return ConciseModeNotifier();
});

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref);
});
