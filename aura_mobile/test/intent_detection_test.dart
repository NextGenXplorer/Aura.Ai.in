import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = IntentDetectionService();

  group('IntentDetectionService Tests', () {
    test('Detects URL Scrape Intent (Priority 1)', () async {
      expect(await service.detectIntent('check this link: https://google.com'), IntentType.urlScrape);
      expect(await service.detectIntent('https://example.com is cool'), IntentType.urlScrape);
    });

    test('Detects Memory Store Intent (Priority 2)', () async {
      expect(await service.detectIntent('remember that I need milk'), IntentType.memoryStore);
      expect(await service.detectIntent('save this idea'), IntentType.memoryStore);
      expect(await service.detectIntent('note that the sky is blue'), IntentType.memoryStore);
    });

    test('Detects Memory Retrieve Intent (Priority 3)', () async {
      expect(await service.detectIntent('what did i say about milk'), IntentType.memoryRetrieve);
      expect(await service.detectIntent('when is my meeting'), IntentType.memoryRetrieve);
      expect(await service.detectIntent('what is my pet name'), IntentType.memoryRetrieve);
    });

    test('Detects Web Search Intent (Priority 4)', () async {
      expect(await service.detectIntent('search for news'), IntentType.webSearch);
      expect(await service.detectIntent('latest tech updates'), IntentType.webSearch);
      expect(await service.detectIntent('who is the president'), IntentType.webSearch);
    });

    test('Defaults to Normal Chat if no trigger', () async {
      expect(await service.detectIntent('hello world'), IntentType.normalChat);
      expect(await service.detectIntent('how are you'), IntentType.normalChat);
    });

    test('Extracts Memory Content Correctly', () {
      expect(service.extractMemoryContent('remember that buy eggs'), 'buy eggs');
      expect(service.extractMemoryContent('save this meeting at 5pm'), 'meeting at 5pm');
      expect(service.extractMemoryContent('note that the sky is blue'), 'the sky is blue');
    });

    test('Extracts SMS Details Correctly', () {
      // Standard: first token = name, rest = body (no "to" separator)
      expect(service.extractSMSDetails('Text John Hello'), {'name': 'John', 'message': 'Hello'});
      
      // Spaced Number — "as" is the separator, so message is everything after it
      expect(service.extractSMSDetails('Text 90196 71670 as hai'), {'name': '90196 71670', 'message': 'hai'});
      
      // Country Code — with separator keyword (as) works correctly
      expect(service.extractSMSDetails('Text +91 90196 71670 as works'), {'name': '+91 90196 71670', 'message': 'works'});
      // Without a separator, first token is treated as the name (ambiguous by design)
      expect(service.extractSMSDetails('Text +91 90196 71670'), {'name': '+91', 'message': '90196 71670'});
      
      // "Send [body] to [name]" — the core grammar fix
      expect(service.extractSMSDetails('Send hello to John'), {'name': 'John', 'message': 'hello'});
      expect(service.extractSMSDetails('send hyy to pooja'), {'name': 'pooja', 'message': 'hyy'});
      expect(service.extractSMSDetails('send good morning to rahul'), {'name': 'rahul', 'message': 'good morning'});
      expect(service.extractSMSDetails('msg hello there to mom'), {'name': 'mom', 'message': 'hello there'});

      // No "to" — first token is the name (existing behaviour must not break)
      expect(service.extractSMSDetails('text Pooja how are you'), {'name': 'Pooja', 'message': 'how are you'});
    });
  });
}
