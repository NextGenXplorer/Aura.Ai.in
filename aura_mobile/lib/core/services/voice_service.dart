import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Simple, reliable voice service.
/// Listen → get final text → done. No complex auto-restart logic.
class VoiceService {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isInitialized = false;
  bool _isListening = false;
  bool _isSpeaking = false;

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);

      _isInitialized = await _speechToText.initialize(
        onError: (error) => debugPrint('VoiceService STT Error: ${error.errorMsg}'),
        onStatus: (status) => debugPrint('VoiceService STT Status: $status'),
      );

      return _isInitialized;
    } catch (e) {
      debugPrint('VoiceService init failed: $e');
      return false;
    }
  }

  /// Start listening. Calls onResult(text, true) when speech is final.
  /// Uses enhanced settings for better accuracy with names and mixed language.
  Future<void> startListening({required Function(String, bool) onResult}) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) {
        onResult('', true);
        return;
      }
    }

    // Stop TTS first so mic doesn't pick up speaker
    if (_isSpeaking) {
      await stopSpeaking();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _isListening = true;

    try {
      await _speechToText.listen(
        onResult: (SpeechRecognitionResult result) {
          final text = result.recognizedWords;
          if (result.finalResult) {
            _isListening = false;
            onResult(text, true);
          } else {
            onResult(text, false);
          }
        },
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
        listenFor: const Duration(seconds: 60), // Extended from 30s to 60s
        pauseFor: const Duration(seconds: 4), // Extended from 3s to 4s — more time between words
        // Use the device's default locale for better name recognition
        localeId: null, // null = device default (supports Hindi-English mix)
      );
    } catch (e) {
      debugPrint('VoiceService listen failed: $e');
      _isListening = false;
      onResult('', true);
    }
  }

  Future<void> stopListening() async {
    _isListening = false;
    try {
      await _speechToText.stop();
    } catch (_) {}
  }

  /// Speak text aloud. Cleans markdown/code before speaking.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    _isSpeaking = true;

    try {
      final cleaned = _cleanForTTS(text);
      if (cleaned.isEmpty) {
        _isSpeaking = false;
        return;
      }

      // Set await mode so speak() returns only after done
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.speak(cleaned);
      _isSpeaking = false;
    } catch (e) {
      debugPrint('VoiceService speak failed: $e');
      _isSpeaking = false;
    }
  }

  Future<void> stopSpeaking() async {
    _isSpeaking = false;
    await _flutterTts.stop();
  }

  String _cleanForTTS(String text) {
    return text
        .replaceAll(RegExp(r'```[\s\S]*?```'), 'Here is the code.')
        .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1')
        .replaceAll(RegExp(r'__(.+?)__'), r'$1')
        .replaceAll(RegExp(r'_(.+?)_'), r'$1')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'$1')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
