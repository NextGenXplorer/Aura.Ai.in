import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/features/orchestrator/orchestrator_service.dart';

final assistantAiBridgeProvider = Provider((ref) {
  return AssistantAiBridge(ref);
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
      if (_isProcessing) {
        print('AI_BRIDGE: Already processing, queuing response');
        await Future.delayed(const Duration(seconds: 2));
      }
      await _processQuery(query);
    }
  }

  Future<void> _processQuery(String query) async {
    try {
      final llmService = _ref.read(llmServiceProvider);

      // Auto-load model if not loaded yet
      if (!llmService.isModelLoaded) {
        print('AI_BRIDGE: Model not loaded, attempting auto-load...');
        final prefs = await SharedPreferences.getInstance();
        final modelPath = prefs.getString('selected_model_path');
        if (modelPath != null && modelPath.isNotEmpty) {
          await llmService.initialize();
          await llmService.loadModel(modelPath);
          print('AI_BRIDGE: Model auto-loaded');
        } else {
          await _sendResponse('Please open the app and download a model first.');
          return;
        }
      }

      // Wait briefly if model might be busy from a text chat
      await Future.delayed(const Duration(milliseconds: 300));

      print('AI_BRIDGE: Model ready, calling orchestrator...');
      final orchestrator = _ref.read(orchestratorServiceProvider);

      // Try up to 2 times in case the model was busy
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final stream = orchestrator.processMessage(
            message: query,
            chatHistory: [],
            hasDocuments: false,
            isVoiceQuery: true,
          );

          String fullText = '';
          bool sentAnything = false;

          await for (final chunk in stream) {
            fullText += chunk;

            // Check for dismiss marker — close overlay after action
            if (fullText.contains('__DISMISS__')) {
              fullText = fullText.replaceAll('__DISMISS__', '').trim();
              // Send any remaining text before dismissing
              if (fullText.isNotEmpty) {
                final cleaned = _stripMarkdown(fullText);
                if (cleaned.trim().isNotEmpty) {
                  await _channel.invokeMethod('sendAIChunk', cleaned);
                  sentAnything = true;
                }
              }
              // Signal completion and dismiss
              await _channel.invokeMethod('sendAIComplete', null);
              print('AI_BRIDGE: __DISMISS__ received — closing overlay');
              return;
            }

            // Check for hallucination markers
            final cutIdx = _findHallucinationMarker(fullText);
            if (cutIdx >= 0) {
              fullText = fullText.substring(0, cutIdx).trimRight();
              break;
            }

            // Extract complete sentences and send them for TTS
            final extracted = _extractCompleteSentences(fullText);
            if (extracted.sentences.isNotEmpty) {
              final cleaned = _stripMarkdown(extracted.sentences);
              if (cleaned.trim().isNotEmpty) {
                await _channel.invokeMethod('sendAIChunk', cleaned);
                sentAnything = true;
              }
              fullText = extracted.remainder;
            }
          }

          // Send remaining text
          if (fullText.trim().isNotEmpty) {
            final cleaned = _stripMarkdown(fullText.trim());
            if (cleaned.trim().isNotEmpty) {
              await _channel.invokeMethod('sendAIChunk', cleaned);
              sentAnything = true;
            }
          }

          if (!sentAnything) {
            if (attempt == 0) {
              // First attempt failed silently — retry after a pause
              print('AI_BRIDGE: No output on attempt $attempt, retrying...');
              await Future.delayed(const Duration(seconds: 1));
              continue;
            }
            await _channel.invokeMethod('sendAIChunk', 'Sorry, I could not generate a response.');
          }

          await _channel.invokeMethod('sendAIComplete', null);
          print('AI_BRIDGE: Response complete');
          return; // Success — exit retry loop
        } catch (e) {
          print('AI_BRIDGE: Attempt $attempt failed: $e');
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 1));
            continue; // Retry
          }
          rethrow; // Let outer catch handle it
        }
      }
    } catch (e) {
      print('AI_BRIDGE: ERROR: $e');
      try {
        await _channel.invokeMethod('sendAIChunk', 'Sorry, something went wrong. Please try again.');
        await _channel.invokeMethod('sendAIComplete', null);
      } catch (_) {}
    }
  }

  /// Helper to send a single response and complete
  Future<void> _sendResponse(String text) async {
    await _channel.invokeMethod('sendAIChunk', text);
    await _channel.invokeMethod('sendAIComplete', null);
  }

  int _findHallucinationMarker(String text) {
    const markers = [
      '<|endoftext|>', '<|im_end|>', '<|im_start|>',
      '\nHuman:', '\nUser:', 'Human: ', 'User: ',
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

  _SentenceExtraction _extractCompleteSentences(String text) {
    int lastBoundary = -1;
    for (int i = 0; i < text.length - 1; i++) {
      final c = text[i];
      if (c == '.' || c == '!' || c == '?') {
        final next = text[i + 1];
        if (next == ' ' || next == '\n' || next == '\r') {
          lastBoundary = i + 1;
        }
      } else if (c == '\n') {
        lastBoundary = i + 1;
      }
    }

    if (lastBoundary > 0) {
      return _SentenceExtraction(
        sentences: text.substring(0, lastBoundary).trim(),
        remainder: text.substring(lastBoundary),
      );
    }

    return _SentenceExtraction(sentences: '', remainder: text);
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

class _SentenceExtraction {
  final String sentences;
  final String remainder;
  _SentenceExtraction({required this.sentences, required this.remainder});
}
