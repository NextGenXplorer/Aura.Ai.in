import 'package:flutter/foundation.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';

/// Carries the classified intent type and extracted parameters.
class ClassifiedIntent {
  final IntentType type;
  final Map<String, String> parameters;

  /// Alias for [parameters] used by the orchestrator.
  Map<String, String> get params => parameters;

  const ClassifiedIntent(this.type, [this.parameters = const {}]);

  @override
  String toString() => 'ClassifiedIntent($type, $parameters)';
}

/// LLM-based fallback intent classifier.
/// Used when rule-based detection returns `normalChat` to catch creative phrasings.
class LLMIntentClassifier {
  final LLMService _llmService;

  LLMIntentClassifier(this._llmService);

  static const _systemPrompt =
      'Classify commands. Reply ONLY with: CATEGORY|params\n'
      'Categories: OPEN_APP|name, DIAL_CONTACT|name, SEND_SMS|name|message, '
      'TORCH|on/off, OPEN_CAMERA, OPEN_SETTINGS|type, WEB_SEARCH|query, '
      'REMINDER_SET|title|time, NAVIGATE|destination, EMAIL_DRAFT|address|topic, '
      'VIEW_CALENDAR, CREATE_EVENT|title, NEXT_EVENT, MEDIA_CONTROL|action, '
      'BRIGHTNESS|level, SCREENSHOT, READ_MESSAGES|app, READ_NOTIFICATIONS, '
      'CREATE_NOTE|content, CALCULATE|expression, CONVERT|amount|from|to, '
      'SEND_WHATSAPP|contact|message, SEARCH_ON_APP|app|query, '
      'UPI_PAYMENT|upiId|amount|note, PLAY_SPOTIFY|query, '
      'BOOK_RIDE|destination|app, ORDER_FOOD|restaurant|app, '
      'SHARE_CONTENT|text|app, OPEN_PROFILE|platform|username, NORMAL_CHAT\n'
      'Examples:\n'
      '"ring up John" -> DIAL_CONTACT|John\n'
      '"fire up Chrome" -> OPEN_APP|Chrome\n'
      '"snap a pic" -> OPEN_CAMERA\n'
      '"drop a text to Mom saying hi" -> SEND_SMS|Mom|hi\n'
      '"turn the light on" -> TORCH|on\n'
      '"show my calendar" -> VIEW_CALENDAR\n'
      '"pause the music" -> MEDIA_CONTROL|pause\n'
      '"make it brighter" -> BRIGHTNESS|75\n'
      '"what\'s 15% of 250" -> CALCULATE|15% of 250\n'
      '"convert 50 km to miles" -> CONVERT|50|km|miles\n'
      '"whatsapp Mom I will be late" -> SEND_WHATSAPP|Mom|I will be late\n'
      '"search shoes on Amazon" -> SEARCH_ON_APP|amazon|shoes\n'
      '"pay 500 to rahul@upi" -> UPI_PAYMENT|rahul@upi|500|\n'
      '"play Arijit on Spotify" -> PLAY_SPOTIFY|Arijit\n'
      '"book uber to airport" -> BOOK_RIDE|airport|uber\n'
      '"order from Swiggy" -> ORDER_FOOD||swiggy\n'
      '"share hello to WhatsApp" -> SHARE_CONTENT|hello|whatsapp\n'
      '"open @elonmusk on Twitter" -> OPEN_PROFILE|twitter|elonmusk\n'
      '"what is quantum physics" -> NORMAL_CHAT';

  /// Classify a user message using the on-device LLM.
  /// Returns `null` if the model is not loaded or classification fails.
  Future<ClassifiedIntent?> classify(String message) async {
    if (!_llmService.isModelLoaded) {
      debugPrint('LLM_CLASSIFIER: Model not loaded, skipping');
      return null;
    }

    try {
      final buffer = StringBuffer();
      await for (final token in _llmService.chat(
        message,
        systemPrompt: _systemPrompt,
        maxTokens: 30,
        temperature: 0.1, // Very low temperature for deterministic classification
      )) {
        buffer.write(token);
      }

      final raw = buffer.toString().trim();
      debugPrint('LLM_CLASSIFIER: Raw output: "$raw"');
      return _parse(raw);
    } catch (e) {
      debugPrint('LLM_CLASSIFIER: Error during classification: $e');
      return null;
    }
  }

  /// Parse the LLM output into a ClassifiedIntent.
  ClassifiedIntent? _parse(String raw) {
    if (raw.isEmpty) return null;

    // Take only the first line
    var line = raw.split('\n').first.trim();

    // Strip leading "-> " if present
    if (line.startsWith('->')) {
      line = line.substring(2).trim();
    }
    // Strip surrounding quotes
    if ((line.startsWith('"') && line.endsWith('"')) ||
        (line.startsWith("'") && line.endsWith("'"))) {
      line = line.substring(1, line.length - 1).trim();
    }

    final parts = line.split('|').map((p) => p.trim()).toList();
    if (parts.isEmpty) return null;

    final category = parts[0].toUpperCase().replaceAll(' ', '_');

    switch (category) {
      case 'OPEN_APP':
        final name = parts.length > 1 ? parts[1] : '';
        if (name.isEmpty) return null;
        return ClassifiedIntent(IntentType.openApp, {'appName': name});

      case 'DIAL_CONTACT':
        final name = parts.length > 1 ? parts[1] : '';
        if (name.isEmpty) return null;
        return ClassifiedIntent(IntentType.dialContact, {'contactName': name});

      case 'SEND_SMS':
        final name = parts.length > 1 ? parts[1] : '';
        final msg = parts.length > 2 ? parts[2] : '';
        if (name.isEmpty) return null;
        return ClassifiedIntent(IntentType.sendSMS, {'name': name, 'message': msg});

      case 'TORCH':
        final state = parts.length > 1 ? parts[1].toLowerCase() : 'on';
        return ClassifiedIntent(IntentType.torchControl, {'state': state});

      case 'OPEN_CAMERA':
        return ClassifiedIntent(IntentType.openCamera);

      case 'OPEN_SETTINGS':
        final type = parts.length > 1 ? parts[1].toLowerCase() : 'general';
        return ClassifiedIntent(IntentType.openSettings, {'type': type});

      case 'WEB_SEARCH':
        final query = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        if (query.isEmpty) return null;
        return ClassifiedIntent(IntentType.webSearch, {'query': query});

      case 'REMINDER_SET':
        final title = parts.length > 1 ? parts[1] : '';
        final time  = parts.length > 2 ? parts[2] : '';
        if (title.isEmpty) return null;
        // Reconstruct a natural reminder phrase the orchestrator can re-parse
        final reminderMsg = time.isNotEmpty
            ? 'remind me to $title at $time'
            : 'remind me to $title';
        return ClassifiedIntent(IntentType.reminderSet, {'rawMessage': reminderMsg});

      case 'NAVIGATE':
        final destination = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        if (destination.isEmpty) return null;
        return ClassifiedIntent(IntentType.navigation, {'destination': destination});

      case 'EMAIL_DRAFT':
        final address = parts.length > 1 ? parts[1] : '';
        final topic   = parts.length > 2 ? parts[2] : '';
        if (address.isEmpty) return null;
        return ClassifiedIntent(IntentType.emailDraft, {'address': address, 'topic': topic});

      // ═══ NEW FEATURES - LLM Classification ═══

      case 'VIEW_CALENDAR':
        return ClassifiedIntent(IntentType.viewCalendar);

      case 'CREATE_EVENT':
        final title = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        if (title.isEmpty) return null;
        return ClassifiedIntent(IntentType.createEvent, {'title': title});

      case 'NEXT_EVENT':
      case 'GET_NEXT_EVENT':
        return ClassifiedIntent(IntentType.getNextEvent);

      case 'MEDIA_CONTROL':
        final action = parts.length > 1 ? parts[1].toLowerCase() : 'play';
        return ClassifiedIntent(IntentType.mediaControl, {'action': action});

      case 'BRIGHTNESS':
      case 'SET_BRIGHTNESS':
        final level = parts.length > 1 ? parts[1] : '50';
        return ClassifiedIntent(IntentType.setBrightness, {'level': level});

      case 'SCREENSHOT':
        return ClassifiedIntent(IntentType.screenshot);

      case 'READ_MESSAGES':
        final app = parts.length > 1 ? parts[1].toLowerCase() : '';
        return ClassifiedIntent(IntentType.readMessages, {'app': app});

      case 'READ_NOTIFICATIONS':
        return ClassifiedIntent(IntentType.readNotifications);

      case 'CREATE_NOTE':
        final content = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        if (content.isEmpty) return null;
        return ClassifiedIntent(IntentType.createNote, {'content': content});

      case 'CALCULATE':
        final expression = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        if (expression.isEmpty) return null;
        return ClassifiedIntent(IntentType.calculate, {'expression': expression});

      case 'CONVERT':
        if (parts.length < 4) return null;
        final amount = parts[1];
        final from = parts[2];
        final to = parts[3];
        return ClassifiedIntent(IntentType.convert, {
          'amount': amount,
          'fromUnit': from,
          'toUnit': to,
        });

      // ═══ SMART APP ACTIONS - LLM Classification ═══

      case 'SEND_WHATSAPP':
        final contact = parts.length > 1 ? parts[1] : '';
        final message = parts.length > 2 ? parts[2] : '';
        if (contact.isEmpty) return null;
        return ClassifiedIntent(IntentType.sendWhatsApp, {'contact': contact, 'message': message});

      case 'SEARCH_ON_APP':
        final app = parts.length > 1 ? parts[1] : '';
        final query = parts.length > 2 ? parts.sublist(2).join(' ') : '';
        if (app.isEmpty || query.isEmpty) return null;
        return ClassifiedIntent(IntentType.searchOnApp, {'appName': app, 'query': query});

      case 'UPI_PAYMENT':
        final upiId = parts.length > 1 ? parts[1] : '';
        final amount = parts.length > 2 ? parts[2] : '';
        final note = parts.length > 3 ? parts[3] : '';
        return ClassifiedIntent(IntentType.upiPayment, {'upiId': upiId, 'amount': amount, 'note': note});

      case 'PLAY_SPOTIFY':
        final query = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        if (query.isEmpty) return null;
        return ClassifiedIntent(IntentType.playOnSpotify, {'query': query});

      case 'BOOK_RIDE':
        final destination = parts.length > 1 ? parts[1] : '';
        final app = parts.length > 2 ? parts[2] : '';
        if (destination.isEmpty) return null;
        return ClassifiedIntent(IntentType.bookRide, {'destination': destination, 'app': app});

      case 'ORDER_FOOD':
        final restaurant = parts.length > 1 ? parts[1] : '';
        final app = parts.length > 2 ? parts[2] : '';
        return ClassifiedIntent(IntentType.orderFood, {'restaurant': restaurant, 'app': app});

      case 'SHARE_CONTENT':
        final text = parts.length > 1 ? parts[1] : '';
        final app = parts.length > 2 ? parts[2] : '';
        return ClassifiedIntent(IntentType.shareContent, {'text': text, 'app': app});

      case 'OPEN_PROFILE':
        final platform = parts.length > 1 ? parts[1] : '';
        final username = parts.length > 2 ? parts[2] : '';
        if (platform.isEmpty || username.isEmpty) return null;
        return ClassifiedIntent(IntentType.openProfile, {'platform': platform, 'username': username});

      case 'NORMAL_CHAT':
        return ClassifiedIntent(IntentType.normalChat);

      default:
        debugPrint('LLM_CLASSIFIER: Unknown category "$category"');
        return null;
    }
  }
}
