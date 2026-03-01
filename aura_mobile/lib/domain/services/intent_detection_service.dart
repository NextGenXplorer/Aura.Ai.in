import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum IntentType {
  normalChat,
  webSearch,
  urlScrape,
  emailDraft,
  memoryStore,
  memoryRetrieve,
  openApp,
  closeApp,
  openSettings,
  openCamera,
  dialContact,
  sendSMS,
  torchControl,
  reminderSet
}

final intentDetectionServiceProvider = Provider((ref) => IntentDetectionService());

/// ─────────────────────────────────────────────────────────────────────────────
/// Rule-based Intent Detection Service
///
/// Priority order (highest → lowest):
///  0. Greeting / very-short message  → normalChat (fast-path, no LLM needed)
///  1. Torch / Flashlight
///  2. Memory Store
///  3. Memory Retrieve
///  4. Email Draft  (runs BEFORE app-control so @email.com isn't mis-routed)
///  5. Settings
///  6. Camera
///  7. Dial / Call
///  8. SMS  (skipped when @email.com present)
///  9. Close App
/// 10. Open App  (includes "play X in youtube" → webSearch)
/// 11. Web Search (explicit commands + context keywords)
/// 12. URL Scrape
/// 13. normalChat
/// ─────────────────────────────────────────────────────────────────────────────
class IntentDetectionService {

  // ── Shared helpers ────────────────────────────────────────────────────────

  /// True if [message] contains a valid e-mail address like user@domain.com
  static final _emailAddressRe = RegExp(
    r'\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b',
  );

  bool _hasEmailAddress(String text) => _emailAddressRe.hasMatch(text);

  // ── Main detection ────────────────────────────────────────────────────────

  Future<IntentType> detectIntent(
    String message, {
    List<Map<String, String>>? history,
    bool hasDocuments = false,
  }) async {
    debugPrint("INTENT_DETECTION: Analyzing message: '$message'");
    final msg = message.trim();
    final lo  = msg.toLowerCase();
    final words = lo.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    // ── 0️⃣  Greeting / trivial message fast-path ──────────────────────────
    // Very short messages (≤ 2 words) that don't contain a special trigger
    // keyword go straight to chat, preventing tiny typos from mis-routing.
    final greetingRe = RegExp(
      r'^(hi+|hey+|hello+|heyy+|hyy*|yo+|sup|howdy|greetings|namaste|'
      r'good\s*(morning|afternoon|evening|night)|whats\s*up|'
      r'how\s+are\s+you|how\s+r\s+u|hows\s+it\s+going|'
      r'hola|bonjour|salut|ciao)\s*[!?.]*$',
      caseSensitive: false,
    );
    if (greetingRe.hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Greeting → normalChat');
      return IntentType.normalChat;
    }
    // Any message ≤ 2 words with no special keyword → chat
    if (words.length <= 2 && !_hasEmailAddress(msg) && !lo.contains('http')) {
      final hasSpecial = RegExp(
        r'\b(torch|flashlight|camera|photo|selfie|call|dial|sms|text|'
        r'email|mail|search|open|launch|remember|recall)\b',
        caseSensitive: false,
      ).hasMatch(lo);
      if (!hasSpecial) {
        debugPrint('INTENT_DETECTION: Short message with no keywords → normalChat');
        return IntentType.normalChat;
      }
    }

    // ── 1️⃣  Torch / Flashlight ────────────────────────────────────────────
    // Keywords: torch, flashlight, flash light, LED light, pocket torch
    // Action verbs: on, off, enable, disable, toggle, turn on/off, activate
    final torchKwRe = RegExp(
      r'\b(torch|flashlight|flash\s*light|led\s*light|pocket\s*torch|'
      r'phone\s*light|mobile\s*torch|strobe)\b',
      caseSensitive: false,
    );
    if (torchKwRe.hasMatch(lo)) {
      final torchActionRe = RegExp(
        r'\b(on|off|enable|disable|toggle|turn|activate|deactivate|switch)\b',
        caseSensitive: false,
      );
      if (torchActionRe.hasMatch(lo) ||
          lo.startsWith('torch') ||
          lo.startsWith('flashlight') ||
          lo.startsWith('flash') ||
          lo.startsWith('led')) {
        debugPrint('INTENT_DETECTION: Torch keyword + action → torchControl');
        return IntentType.torchControl;
      }
    }
    // Natural phrasing: "turn the light on", "lights off", "light up phone"
    if (RegExp(
      r'(turn\s+(the\s+)?(flash|light|torch|phone\s+light)\s*(on|off)|'
      r'light\s+up\s+(my\s+)?(phone|screen)|lights?\s*(on|off)|'
      r'switch\s+(on|off)\s+(the\s+)?(torch|flash|light))',
      caseSensitive: false,
    ).hasMatch(lo)) {
      return IntentType.torchControl;
    }

    // ── 2️⃣  Reminder Set ─────────────────────────────────────────────────
    // Must trigger on explicit "remind me", "set a reminder", "notify me"
    // especially when coupled with a time expression (at 9pm, on March 25)
    if (RegExp(
      r'^(remind\s+(me|us)(\s+to)?|set\s+(a\s+)?reminder|'
      r'schedule\s+(a\s+)?reminder|notify\s+(me|us)(\s+on|\s+at|\s+about)?|'
      r'alert\s+me|remind\s+that)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Reminder command → reminderSet');
      return IntentType.reminderSet;
    }

    // ── 3️⃣  Memory Store ─────────────────────────────────────────────────
    // Trigger words must appear at the START of the message
    if (RegExp(
      r'^(remember|don\x27t\s+forget|dont\s+forget|keep\s+in\s+mind|memorize|'
      r'save\s+this|store\s+this|note\s+that|jot\s+(this\s+)?down|'
      r'write\s+this\s+down|add\s+to\s+memory|put\s+in\s+memory|'
      r'keep\s+track\s+of|keep\s+note)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Memory store → memoryStore');
      return IntentType.memoryStore;
    }

    // ── 3️⃣  Memory Retrieve ──────────────────────────────────────────────
    if (RegExp(
      r'^(recall|retrieve|fetch\s+from\s+memory|find\s+in\s+memory|'
      r'search\s+(my\s+)?memory|what\s+(was|did|is|do\s+you\s+know)|'
      r'when\s+(was|is)|where\s+(was|is|did)|bring\s+up\s+(memory|what)|'
      r'have\s+you\s+saved|what\s+did\s+you\s+remember)\b',
      caseSensitive: false,
    ).hasMatch(lo) ||
        lo.contains('do you remember') ||
        lo.contains('from my memory') ||
        lo.contains('in your memory') ||
        lo.contains('you stored')) {
      debugPrint('INTENT_DETECTION: Memory retrieve → memoryRetrieve');
      return IntentType.memoryRetrieve;
    }

    // ── 4️⃣  Email Draft ──────────────────────────────────────────────────
    // MUST run before app-control so "email john@gmail.com" isn't mis-routed.
    // Requires: @email.com address present + email action keyword.
    if (_hasEmailAddress(msg)) {
      final _emailKw = RegExp(
        r'\b(email|e-mail|e\s*mail|mail|gmail|yahoo\s*mail|outlook|'
        r'compose|draft|write|send|shoot|drop|ping|'
        r'forward|reply|respond|reach\s*out|contact|message|'
        r'notify|inform|update|let\s+know)\b',
        caseSensitive: false,
      );
      // "to john@..." pattern also counts
      final _toEmail = RegExp(
        r'\bto\s+[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b',
        caseSensitive: false,
      );
      if (_emailKw.hasMatch(lo) || _toEmail.hasMatch(lo)) {
        debugPrint('INTENT_DETECTION: Email address + keyword → emailDraft');
        return IntentType.emailDraft;
      }
      // Plain "X@Y.com" with no other intent keyword → treat as email
      debugPrint('INTENT_DETECTION: Bare email address → emailDraft');
      return IntentType.emailDraft;
    }

    // ── 5️⃣  Settings ─────────────────────────────────────────────────────
    // Must have a settings keyword AND an action word to avoid accidental match
    if (RegExp(
      r'\b(settings|configuration|preferences|config|control\s+panel)\b',
      caseSensitive: false,
    ).hasMatch(lo) &&
        RegExp(
          r'\b(open|show|go\s+to|take\s+me\s+to|manage|change|access|'
          r'bring\s+up|navigate\s+to|get\s+me\s+to)\b',
          caseSensitive: false,
        ).hasMatch(lo)) {
      return IntentType.openSettings;
    }
    // Specific connection settings
    if (RegExp(
      r'\b(wifi|wi-fi|wireless|bluetooth|bt|mobile\s+data|'
      r'airplane\s+mode|hotspot|nfc|location|gps|display|brightness|'
      r'volume|sound|notification|battery|storage|accessibility)\s+'
      r'(settings?|toggle|on|off|enable|disable)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      return IntentType.openSettings;
    }
    if (RegExp(
      r'(take\s+me\s+to\s+.*(settings?|wifi|bluetooth)|'
      r'bring\s+up\s+(wifi|bluetooth|settings?)|'
      r'open\s+(wifi|bluetooth|network|display|sound)\s+settings?)',
      caseSensitive: false,
    ).hasMatch(lo)) {
      return IntentType.openSettings;
    }

    // ── 6️⃣  Camera ───────────────────────────────────────────────────────
    // Must have BOTH a camera subject word AND a clear action verb.
    // "shoot" alone is excluded here — it's used in email/sms too.
    final _cameraSubject = RegExp(
      r'\b(camera|photo|picture|selfie|snapshot|portrait|video\s+(record|camera))\b',
      caseSensitive: false,
    );
    final _cameraAction = RegExp(
      r'\b(open|start|launch|take|capture|click|snap|record|turn\s+on)\b',
      caseSensitive: false,
    );
    if (_cameraSubject.hasMatch(lo) && _cameraAction.hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Camera subject + action → openCamera');
      return IntentType.openCamera;
    }
    // Explicit camera-only phrases: "snap a selfie", "take a pic", "capture a photo"
    if (RegExp(
      r'\b(snap|capture|click|take)\s+(a\s+)?(photo|picture|pic|selfie|snapshot|shot\b)',
      caseSensitive: false,
    ).hasMatch(lo)) {
      return IntentType.openCamera;
    }
    // "open camera", "launch camera"
    if (RegExp(
      r'^(open|launch|start|turn\s+on)\s+(the\s+)?camera\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      return IntentType.openCamera;
    }

    // ── 7️⃣  Dial / Call ──────────────────────────────────────────────────
    // Guard: only match when no @email.com present (already handled above)
    if (RegExp(
      r'^(call|dial|phone|ring\s*up|ring|buzz|make\s+a\s+call\s+to|'
      r'place\s+a\s+call\s+to|connect\s+me\s+to|get\s+me\s+on\s+the\s+phone\s+with|'
      r'speak\s+to|talk\s+to|i\s+want\s+to\s+talk\s+to)\s+\S',
      caseSensitive: false,
    ).hasMatch(lo)) {
      return IntentType.dialContact;
    }
    if (RegExp(
      r'(give\s+\S.+\s+a\s+(call|ring|buzz)|call\s+up\s+\S)',
      caseSensitive: false,
    ).hasMatch(lo)) {
      return IntentType.dialContact;
    }

    // ── 8️⃣  SMS / Text ───────────────────────────────────────────────────
    // Guard: SKIP if @email.com address present (handled as emailDraft above)
    // Also skip if message is about "sending an email" in general terms
    final _emailWordRe = RegExp(r'\b(email|e-mail|e\s*mail|gmail|mail)\b', caseSensitive: false);
    if (!_hasEmailAddress(msg) && !_emailWordRe.hasMatch(lo)) {
      // "text John", "sms 9876543210", "message Priya ...", "msg Rahul"
      if (RegExp(
        r'^(text|sms|message|msg)\s+\S',
        caseSensitive: false,
      ).hasMatch(lo)) {
        return IntentType.sendSMS;
      }
      // "send sms to X", "send text to X", "send a message to X"
      if (RegExp(
        r'^send\s+(a\s+)?(sms|text|message|msg)\s+(to\s+)?\S',
        caseSensitive: false,
      ).hasMatch(lo)) {
        return IntentType.sendSMS;
      }
      // "write a sms to X", "write a text to X"
      if (RegExp(
        r'^write\s+(a\s+)?(sms|text|message)\s+(to\s+)?\S',
        caseSensitive: false,
      ).hasMatch(lo)) {
        return IntentType.sendSMS;
      }
      // Natural: "drop a text/line/message to X", "ping X a text"
      if (RegExp(
        r'(drop\s+a\s+(text|line|message)\s+to\s+\S|'
        r'ping\s+\S.+\s+a\s+text|'
        r'shoot\s+a\s+(message|text)\s+to\s+\S)',
        caseSensitive: false,
      ).hasMatch(lo)) {
        return IntentType.sendSMS;
      }
    }

    // ── 9️⃣  Close App ────────────────────────────────────────────────────
    if (RegExp(
      r'^(close|kill|stop|exit|quit|shut\s+down|terminate)\s+\S',
      caseSensitive: false,
    ).hasMatch(lo)) {
      return IntentType.closeApp;
    }

    // ── 🔟  Open App / Play Media ─────────────────────────────────────────
    // "play X on/in youtube" → route to webSearch (YouTube search)
    if (RegExp(
      r'(play|search|look\s+for|find|show)\s+.+\s+(on|in|via|using|through)\s+youtube\b',
      caseSensitive: false,
    ).hasMatch(lo) ||
        RegExp(
          r'(youtube\s+(play|search|find|show|look\s+up))\s+',
          caseSensitive: false,
        ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: YouTube play → webSearch');
      return IntentType.webSearch;
    }
    // "play X on spotify/music" → openApp
    if (RegExp(
      r'(play|listen\s+to)\s+.+\s+(on|in)\s+(spotify|apple\s+music|youtube\s+music|gaana|jio\s*saavn|amazon\s+music)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      return IntentType.openApp;
    }
    // Standard: "open/launch/start/run/play/navigate to X"
    if (RegExp(
      r'^(open|launch|start|run|play|go\s+to|switch\s+to|fire\s+up|'
      r'pull\s+up|bring\s+up|load|navigate\s+to|jump\s+to|'
      r'get\s+me\s+to|take\s+me\s+to|redirect\s+to)\s+\S',
      caseSensitive: false,
    ).hasMatch(lo)) {
      // Sub-route: if target is a setting/camera word, prefer those intents
      if (RegExp(r'\b(settings?|configuration|preferences)\b', caseSensitive: false).hasMatch(lo)) {
        return IntentType.openSettings;
      }
      if (RegExp(r'\bcamera\b', caseSensitive: false).hasMatch(lo)) {
        return IntentType.openCamera;
      }
      // "open youtube and play/search X" → webSearch
      if (lo.contains('youtube') &&
          RegExp(r'(and\s+)?(play|search|find|search\s+for)\s+', caseSensitive: false).hasMatch(lo)) {
        return IntentType.webSearch;
      }
      return IntentType.openApp;
    }
    // "open up X", "flip to X"
    if (RegExp(
      r'^(open\s+up|flip\s+to|switch\s+over\s+to)\s+\S',
      caseSensitive: false,
    ).hasMatch(lo)) {
      return IntentType.openApp;
    }

    // ── 1️⃣1️⃣  Web Search ─────────────────────────────────────────────────
    // Explicit search commands
    if (RegExp(
      r'^(search\s+(for\s+)?|find\s+|lookup\s+|look\s+up\s+|google\s+|'
      r'browse\s+|research\s+|show\s+me\s+|get\s+me\s+info\s+on\s+|'
      r'find\s+me\s+|i\s+want\s+to\s+know\s+(about\s+)?|'
      r'tell\s+me\s+about\s+|explain\s+|define\s+|'
      r'who\s+(is|was|are)\s+|what\s+(is|was|are|were|happened)\s+|'
      r'when\s+(is|was|does|did)\s+|where\s+(is|can|do|did)\s+|'
      r'how\s+(to|do|can|does|much|many)\s+)',
      caseSensitive: false,
    ).hasMatch(lo) ||
        lo.startsWith('[search]')) {
      debugPrint('INTENT_DETECTION: Explicit search command → webSearch');
      return IntentType.webSearch;
    }
    // Context keywords that imply real-time info needs
    if (RegExp(
      r'\b(latest|news|todays?|current|trending|live\s+(score|update)|'
      r'weather|forecast|temperature|rain|humidity|'
      r'price\s+of|cost\s+of|rate\s+of|stock\s+price|'
      r'cricket\s+score|football\s+result|match\s+result|'
      r'box\s+office|movie\s+review|release\s+date|'
      r'when\s+does|is\s+\w+\s+open)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Context keyword → webSearch');
      return IntentType.webSearch;
    }

    // ── 1️⃣2️⃣  URL Scrape ─────────────────────────────────────────────────
    if (containsURL(msg)) {
      debugPrint('INTENT_DETECTION: URL detected → urlScrape');
      return IntentType.urlScrape;
    }

    // ── 1️⃣3️⃣  Default ───────────────────────────────────────────────────
    debugPrint('INTENT_DETECTION: No match → normalChat');
    return IntentType.normalChat;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helper: URL detection (skips words with @ to avoid mis-matching emails)
  // ──────────────────────────────────────────────────────────────────────────
  bool containsURL(String text) {
    final urlRe = RegExp(
      r'^((https?:\/\/)|(www\.)|([a-zA-Z0-9_\-]{2,256}\.[a-z]{2,6}))',
      caseSensitive: false,
    );
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.contains('@')) continue; // email address, skip
      if (urlRe.hasMatch(word)) return true;
    }
    return false;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Extraction Helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// First @email.com address in [message], or null.
  String? extractEmailAddress(String message) =>
      _emailAddressRe.firstMatch(message)?.group(0);

  /// Topic of the email intent (message minus address and filler words).
  String extractEmailTopic(String message, String emailAddress) {
    return message
        .replaceAll(emailAddress, '')
        .replaceAll(
          RegExp(
            r'\b(email|e-mail|e\s*mail|mail|gmail|yahoo\s*mail|outlook|'
            r'compose|draft|write|send|shoot|drop|ping|forward|reply|'
            r'respond|reach\s*out|contact|message|notify|inform|update|'
            r'let\s+know|to|about|for|regarding|re:|subject|an|a|the)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// Clean search query (strips command prefix).
  String extractSearchQuery(String message) {
    final prefixRe = RegExp(
      r'^(search\s+(for\s+)?|find\s+|lookup\s+|look\s+up\s+|google\s+|'
      r'browse\s+|research\s+|show\s+me\s+|find\s+me\s+|'
      r'tell\s+me\s+about\s+|explain\s+|define\s+|'
      r'who\s+(is|was|are)\s+|what\s+(is|was|are|were)\s+|'
      r'when\s+(is|was|does|did)\s+|where\s+(is|can|do)\s+|'
      r'how\s+(to|do|can|does)\s+|\[search\]\s*)',
      caseSensitive: false,
    );
    final m = prefixRe.firstMatch(message.trim());
    if (m != null) return message.trim().substring(m.end).trim();
    return message.trim();
  }

  /// Extracts the URL from a message.
  String extractUrl(String message) {
    final urlRe = RegExp(
      r'^((https?:\/\/)|(www\.)|([a-zA-Z0-9_\-]{2,256}\.[a-z]{2,6}))',
      caseSensitive: false,
    );
    for (final word in message.split(RegExp(r'\s+'))) {
      if (word.contains('@')) continue;
      final m = urlRe.firstMatch(word);
      if (m != null) return word;
    }
    return message;
  }

  /// Content to store in memory (strips the command prefix).
  String extractMemoryContent(String message) {
    final prefixRe = RegExp(
      r'^(remember\s*(that|to)?|don\x27t\s+forget\s*(to)?|dont\s+forget\s*(to)?|'
      r'keep\s+in\s+mind\s*(that)?|memorize\s*(that)?|'
      r'save\s+this|store\s+this|note\s+that|jot\s+(this\s+)?down|'
      r'write\s+this\s+down|add\s+to\s+memory|put\s+in\s+memory|'
      r'keep\s+track\s+of|keep\s+note)\s*',
      caseSensitive: false,
    );
    final cleaned = message.replaceFirst(prefixRe, '').trim();
    return cleaned.isEmpty ? message : cleaned;
  }

  /// App name (strips the open/launch/… prefix).
  String extractAppName(String message) {
    final prefixRe = RegExp(
      r'^(open|launch|start|run|play|go\s+to|switch\s+to|fire\s+up|'
      r'pull\s+up|bring\s+up|load|navigate\s+to|jump\s+to|'
      r'open\s+up|flip\s+to|get\s+me\s+to|take\s+me\s+to|'
      r'close|kill|stop|exit|quit|shut\s+down|terminate)\s+',
      caseSensitive: false,
    );
    final m = prefixRe.firstMatch(message.trim());
    return m != null ? message.trim().substring(m.end).trim() : message.trim();
  }

  /// Settings type from message.
  String extractSettingsType(String message) {
    final lo = message.toLowerCase();
    if (lo.contains('wifi') || lo.contains('wi-fi') || lo.contains('wireless')) return 'wifi';
    if (lo.contains('bluetooth') || lo.contains(' bt ')) return 'bluetooth';
    if (lo.contains('display') || lo.contains('brightness') || lo.contains('screen')) return 'display';
    if (lo.contains('sound') || lo.contains('volume') || lo.contains('ringer')) return 'sound';
    if (lo.contains('mobile data') || lo.contains('cellular')) return 'mobile_data';
    if (lo.contains('airplane') || lo.contains('flight mode')) return 'airplane';
    if (lo.contains('battery') || lo.contains('power')) return 'battery';
    if (lo.contains('location') || lo.contains('gps')) return 'location';
    if (lo.contains('notification')) return 'notification';
    if (lo.contains('hotspot') || lo.contains('tethering')) return 'hotspot';
    return 'general';
  }

  /// Contact name for dial intent.
  String extractContactName(String message) {
    // "give X a call/ring/buzz"
    final giveRe = RegExp(r'give\s+(.+?)\s+a\s+(call|ring|buzz)', caseSensitive: false);
    final gm = giveRe.firstMatch(message.trim());
    if (gm != null) return gm.group(1)?.trim() ?? message.trim();

    final prefixRe = RegExp(
      r'^(call|dial|phone|ring\s*up|ring|buzz|make\s+a\s+call\s+to|'
      r'place\s+a\s+call\s+to|connect\s+me\s+to|get\s+me\s+on\s+the\s+phone\s+with|'
      r'speak\s+to|talk\s+to|i\s+want\s+to\s+talk\s+to|call\s+up)\s+',
      caseSensitive: false,
    );
    final m = prefixRe.firstMatch(message.trim());
    return m != null ? message.trim().substring(m.end).trim() : message.trim();
  }

  /// SMS name + body from message.
  Map<String, String> extractSMSDetails(String message) {
    final clean = message.trim();
    final lo = clean.toLowerCase();
    String name = '';
    String body = '';

    // "Send [body] to [name]" / "Send message to [name] saying [body]"
    if (lo.contains(' to ')) {
      final toIdx = lo.indexOf(' to ');
      final prefixRe = RegExp(
        r'^(send\s+(a\s+)?(sms|text|message|msg)\s+|'
        r'write\s+(a\s+)?(sms|text|message)\s+|'
        r'text\s+|message\s+|msg\s+)',
        caseSensitive: false,
      );
      final pm = prefixRe.firstMatch(clean);
      if (pm != null) {
        final afterTo = clean.substring(toIdx + 4).trim();
        final potential = clean.substring(pm.end, toIdx).trim();
        final isPlaceholder = RegExp(r'^(a\s+)?(sms|text|message|msg)$', caseSensitive: false)
            .hasMatch(potential);
        if (isPlaceholder) {
          // "Send message to John saying Hello"
          final sepRe = RegExp(r'\s+(saying|:|–|-)\s+', caseSensitive: false);
          final sm = sepRe.firstMatch(afterTo);
          if (sm != null) {
            name = afterTo.substring(0, sm.start).trim();
            body = afterTo.substring(sm.end).trim();
          } else {
            name = afterTo;
          }
        } else {
          // "Send Hello to John"
          body = potential;
          name = afterTo;
        }
        return {'name': name, 'message': body};
      }
    }

    // "drop a text to X", "ping X a text", "shoot a message to X"
    final naturalRe = RegExp(
      r'(drop\s+a\s+(text|line|message)|shoot\s+a\s+(message|text))\s+to\s+(.+)',
      caseSensitive: false,
    );
    final nm = naturalRe.firstMatch(clean);
    if (nm != null) {
      final afterTo = nm.group(4)?.trim() ?? '';
      final sepRe = RegExp(r'\s+(saying|:)\s+', caseSensitive: false);
      final sm = sepRe.firstMatch(afterTo);
      if (sm != null) {
        name = afterTo.substring(0, sm.start).trim();
        body = afterTo.substring(sm.end).trim();
      } else {
        name = afterTo;
      }
      return {'name': name, 'message': body};
    }

    // "text John Hello", "msg Priya How are you"
    final cmdRe = RegExp(
      r'^(send\s+|write\s+|text\s+|message\s+|msg\s+|sms\s+)'
      r'(a\s+)?(sms\s+|text\s+|message\s+|msg\s+)?(to\s+)?',
      caseSensitive: false,
    );
    final cm = cmdRe.firstMatch(clean);
    if (cm != null) {
      final remaining = clean.substring(cm.end).trim();
      final tokens = remaining.split(RegExp(r'\s+'));
      if (tokens.isNotEmpty) {
        name = tokens.first;
        if (tokens.length > 1) {
          body = tokens.sublist(1).join(' ');
          final bodySepRe = RegExp(r'^(as|saying)\s+', caseSensitive: false);
          body = body.replaceFirst(bodySepRe, '');
        }
      }
    }
    return {'name': name, 'message': body};
  }
}
