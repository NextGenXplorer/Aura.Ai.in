import 'dart:async';
import 'package:aura_mobile/core/services/speech_chunker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/features/orchestrator/orchestrator_service.dart';

final assistantAiBridgeProvider = Provider((ref) {
  final bridge = AssistantAiBridge(ref);
  ref.onDispose(bridge.dispose);
  return bridge;
});

class AssistantAiBridge {
  static const _channel = MethodChannel('com.aura.ai/assistant_ai');
  final Ref _ref;
  bool _isProcessing = false;

  AssistantAiBridge(this._ref) {
    _channel.setMethodCallHandler(_handleMethodCall);
    // Poll for pending queries every 2 seconds — catches queries from native
    // service that couldn't reach Flutter via method channel
    _startPolling();
    print('AI_BRIDGE: Bridge initialized');
  }

  Timer? _pollTimer;

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final pending = await _channel.invokeMethod<String>('getPendingQuery');
        if (pending != null && pending.isNotEmpty && !_isProcessing) {
          print('AI_BRIDGE: Got pending query from poll: "$pending"');
          await _processQuery(pending);
        }
      } catch (_) {
        // Channel might not have this method yet on native side — that's OK
      }
    });
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('AI_BRIDGE: handleMethodCall: ${call.method} args=${call.arguments}');
    if (call.method == 'processAIQuery') {
      final query = call.arguments as String? ?? '';
      if (query.isEmpty) return;
      print('AI_BRIDGE: Processing voice query: "$query"');
      while (_isProcessing) {
        print('AI_BRIDGE: Already processing, waiting to queue response');
        await Future.delayed(const Duration(milliseconds: 250));
      }
      await _processQuery(query);
    }
  }

  Future<void> _processQuery(String query) async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final router = _ref.read(llmRouterProvider);

      // Restore the user's explicit local or online selection if needed.
      if (!router.isModelLoaded) {
        print('AI_BRIDGE: Model not loaded, attempting restore...');
        await router.initialize();
        await router.restoreActiveSelection();
        if (!router.isModelLoaded) {
          await _sendResponse(
            'Please open the app and select a local or online model first.',
          );
          return;
        }
        print('AI_BRIDGE: Active model restored');
      }

      // The engine serves one generation at a time. Wait for an in-flight text
      // chat or Brain request instead of failing the spoken question.
      if (!await router.waitUntilIdle()) {
        await _sendResponse(
          'Aura is still finishing another reply. Ask again.',
        );
        return;
      }

      print('AI_BRIDGE: Model ready, calling orchestrator...');
      final orchestrator = _ref.read(orchestratorServiceProvider);

      // Try up to 2 times in case the model was busy
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final stream = orchestrator.processMessage(
            message: query,
            chatHistory: _recentTurns(),
            hasDocuments: false,
            isVoiceQuery: true,
            isVoice: true,
          );

          final chunker = SpeechChunker();
          final spoken = StringBuffer();
          var sentAnything = false;
          var dismissed = false;

          Future<void> speak(String text) async {
            final cleaned = _stripMarkdown(text).trim();
            if (cleaned.isEmpty) return;
            await _channel.invokeMethod('sendAIChunk', cleaned);
            sentAnything = true;
          }

          await for (final rawChunk in stream) {
            var chunk = rawChunk;
            if (chunk.contains('__DISMISS__')) {
              chunk = chunk.replaceAll('__DISMISS__', '');
              dismissed = true;
            }

            // Keep only text generated before any hallucinated turn marker.
            final candidate = spoken.toString() + chunk;
            final markerIdx = _findHallucinationMarker(candidate);
            var truncated = false;
            if (markerIdx >= 0) {
              chunk = markerIdx > spoken.length
                  ? candidate.substring(spoken.length, markerIdx)
                  : '';
              truncated = true;
            }

            spoken.write(chunk);
            chunker.add(chunk);
            String? ready;
            while ((ready = chunker.takeChunk()) != null) {
              await speak(ready!);
            }
            if (truncated || dismissed) break;
          }

          final tail = chunker.drain();
          if (tail != null) await speak(tail);
          _rememberTurn(query, spoken.toString());

          if (!sentAnything && !dismissed) {
            if (attempt == 0) {
              print('AI_BRIDGE: No output on attempt $attempt, retrying...');
              await Future.delayed(const Duration(seconds: 1));
              await router.waitUntilIdle();
              continue;
            }
            await _channel.invokeMethod(
              'sendAIChunk',
              'Sorry, I could not answer that. Please try again.',
            );
          }

          await _channel.invokeMethod('sendAIComplete', null);
          print('AI_BRIDGE: Response complete');
          return; // Success — exit retry loop
        } catch (e) {
          print('AI_BRIDGE: Attempt $attempt failed: $e');
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 1));
            await router.waitUntilIdle();
            continue; // Retry
          }
          rethrow; // Let outer catch handle it
        }
      }
    } catch (e) {
      print('AI_BRIDGE: ERROR: $e');
      try {
        await _channel.invokeMethod(
          'sendAIChunk',
          'Sorry, something went wrong. Please try again.',
        );
        await _channel.invokeMethod('sendAIComplete', null);
      } catch (_) {}
    } finally {
      _isProcessing = false;
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _channel.setMethodCallHandler(null);
  }

  /// Short rolling transcript so spoken follow-ups ("what about tomorrow?")
  /// keep context, mirroring the in-app voice conversation.
  final List<String> _voiceTurns = [];

  List<String> _recentTurns() => List<String>.unmodifiable(_voiceTurns);

  void _rememberTurn(String question, String answer) {
    final cleanAnswer = _stripMarkdown(answer).trim();
    if (cleanAnswer.isEmpty) return;
    _voiceTurns
      ..add('User: $question')
      ..add('Assistant: $cleanAnswer');
    while (_voiceTurns.length > 4) {
      _voiceTurns.removeAt(0);
    }
  }

  /// Helper to send a single response and complete
  Future<void> _sendResponse(String text) async {
    await _channel.invokeMethod('sendAIChunk', text);
    await _channel.invokeMethod('sendAIComplete', null);
  }

  int _findHallucinationMarker(String text) {
    const markers = [
      '<|endoftext|>',
      '<|im_end|>',
      '<|im_start|>',
      '\nHuman:',
      '\nUser:',
      'Human: ',
      'User: ',
    ];
    int earliest = -1;
    for (final m in markers) {
      final idx = text.indexOf(m);
      if (idx >= 0 && (earliest == -1 || idx < earliest)) {
        earliest = idx;
      }
    }
    return earliest;
  }

  String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1')
        .replaceAll(RegExp(r'__(.+?)__'), r'$1')
        .replaceAll(RegExp(r'_(.+?)_'), r'$1')
        .replaceAll(RegExp(r'~~(.+?)~~'), r'$1')
        .replaceAll(RegExp(r'`(.+?)`'), r'$1')
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'$1')
        .replaceAll(RegExp(r'!\[.*?\]\(.+?\)'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
