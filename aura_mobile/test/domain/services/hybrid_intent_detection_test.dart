import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';

/// Tests for hybrid intent detection - verifying that ambiguous messages
/// are properly identified and routed to LLM classification
void main() {
  late IntentDetectionService service;

  setUp(() {
    // Create service without LLM (for testing ambiguity detection only)
    service = IntentDetectionService();
  });

  group('Hybrid Intent Detection - Ambiguity Detection', () {
    test('should recognize CLEAR commands as NOT ambiguous', () {
      final clearCommands = [
        'call John',
        'dial 9876543210',
        'text Mom',
        'open WhatsApp',
        'search for Python',
        'remind me at 5pm',
        'navigate to mall',
        'email john@example.com',
      ];

      for (final command in clearCommands) {
        final isAmbiguous = service.isAmbiguous(command, command.toLowerCase());
        expect(isAmbiguous, false, reason: '"$command" should NOT be ambiguous');
      }
    });

    test('should recognize AMBIGUOUS conversational requests', () {
      final ambiguousRequests = [
        'can you call John',
        'please open WhatsApp',
        'i want to text Mom',
        'i need to search for Python',
        'could you remind me at 5pm',
        'would you navigate to the mall',
        'help me open Instagram',
        'i would like to call Dad',
      ];

      for (final request in ambiguousRequests) {
        final isAmbiguous = service.isAmbiguous(request, request.toLowerCase());
        expect(isAmbiguous, true, reason: '"$request" SHOULD be ambiguous');
      }
    });

    test('should recognize NON-ENGLISH word order as ambiguous', () {
      final nonEnglishOrder = [
        'John ko call karo',          // Hinglish: "call John" - has "call" keyword
        'Mom ko text bhejo',           // Hinglish: "send text to Mom" - has "text" keyword
      ];

      for (final request in nonEnglishOrder) {
        final isAmbiguous = service.isAmbiguous(request, request.toLowerCase());
        expect(isAmbiguous, true, reason: '"$request" SHOULD be ambiguous (non-English order)');
      }

      // "WhatsApp kholna hai" is NOT ambiguous because "WhatsApp" is not an action word
      // It would be detected by rules as containing no action keywords
      final noActionWord = 'WhatsApp kholna hai';
      expect(service.isAmbiguous(noActionWord, noActionWord.toLowerCase()), false,
          reason: '"$noActionWord" has no recognized action word');
    });

    test('should recognize NORMAL CHAT as NOT ambiguous (no action words)', () {
      final normalChat = [
        'hello',
        'how are you',
        'what is quantum physics',
        'tell me a joke',
        'good morning',
        'thanks for your help',
      ];

      for (final message in normalChat) {
        final isAmbiguous = service.isAmbiguous(message, message.toLowerCase());
        expect(isAmbiguous, false, reason: '"$message" should NOT be ambiguous (normal chat)');
      }
    });

    test('should handle edge cases correctly', () {
      // Action word at start → NOT ambiguous (rules handle it)
      expect(service.isAmbiguous('call', 'call'), false);
      expect(service.isAmbiguous('open', 'open'), false);

      // Conversational fluff + action word → IS ambiguous (even if action is second word)
      expect(service.isAmbiguous('please call John', 'please call john'), true,
          reason: '"please" is conversational fluff, making it ambiguous');

      // Just conversational words → NOT ambiguous (no action words)
      expect(service.isAmbiguous('can you help me', 'can you help me'), false);

      // Action word in middle → ambiguous
      expect(service.isAmbiguous('John call please', 'john call please'), true);
    });
  });

  group('Hybrid Intent Detection - Rule-based Fast Path', () {
    test('should use rules for obvious commands (bypassing LLM)', () async {
      final intent1 = await service.detectIntent('call John');
      expect(intent1, IntentType.dialContact);

      final intent2 = await service.detectIntent('open WhatsApp');
      expect(intent2, IntentType.openApp);

      final intent3 = await service.detectIntent('search for Python');
      expect(intent3, IntentType.webSearch);

      final intent4 = await service.detectIntent('text Mom hello');
      expect(intent4, IntentType.sendSMS);

      // These should be detected instantly by rules, NOT routed to LLM
    });

    test('should handle greetings without LLM', () async {
      final greetings = [
        'hi',
        'hello',
        'hey',
        'good morning',
        'how are you',
      ];

      for (final greeting in greetings) {
        final intent = await service.detectIntent(greeting);
        expect(intent, IntentType.normalChat);
      }
    });
  });

  group('Hybrid Intent Detection - Explanation', () {
    test('demonstrates the hybrid approach', () {
      // This test just documents how the system works

      print('\n=== HYBRID INTENT DETECTION ===\n');

      print('FAST PATH (Rule-based):');
      print('  ✅ "call John" → IntentType.dialContact (instant)');
      print('  ✅ "open WhatsApp" → IntentType.openApp (instant)');
      print('  ✅ "search Python" → IntentType.webSearch (instant)');

      print('\nSLOW PATH (LLM Fallback):');
      print('  🤖 "can you call John" → LLM classifies → IntentType.dialContact');
      print('  🤖 "please open WhatsApp" → LLM classifies → IntentType.openApp');
      print('  🤖 "I want to search for Python" → LLM classifies → IntentType.webSearch');
      print('  🤖 "John ko call karo" (Hinglish) → LLM classifies → IntentType.dialContact');

      print('\nNORMAL CHAT (Default):');
      print('  💬 "hello" → IntentType.normalChat (no action words)');
      print('  💬 "how are you" → IntentType.normalChat (conversation)');

      print('\n================================\n');
    });
  });
}
