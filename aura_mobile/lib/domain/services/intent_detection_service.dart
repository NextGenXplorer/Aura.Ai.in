import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/domain/services/llm_intent_classifier.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/data/datasources/function_gemma_service.dart';
import 'package:aura_mobile/core/services/utility_model_manager.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';

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
  reminderSet,
  navigation,
  weatherSearch,

  // ═══ NEW FEATURES (5 High-Value Additions) ═══
  // 1. Calendar & Events
  viewCalendar,
  createEvent,
  getNextEvent,

  // 2. Media Controls
  mediaControl,
  setBrightness,
  screenshot,

  // 3. Read Messages/Notifications
  readMessages,
  readNotifications,

  // 4. Quick Notes
  createNote,

  // 5. Calculator & Converter
  calculate,
  convert,

  // 6. Camera/OCR Scan
  scanImage,

  // 7. Study Buddy
  studyCreateFlashcards,
  studyQuizMe,
  studyReviewCards,
  studyShowStats,
  studyScheduleExam,
  studyOpenDashboard,

  // 8. Smart App Actions
  sendWhatsApp,
  searchOnApp,
  upiPayment,
  playOnSpotify,
  bookRide,
  orderFood,
  shareContent,
  openProfile,

  // 9. Document Generation
  generateDocument,
  generateCode,
  generateCsv,
  summarizeChat,

  // 10. Connectors
  getWeather,
  getWikipedia,
  getNews,
  youtubeSearch,
  translateText,
  generateQRCode,
  getSystemInfo,
  findNearby,
}

final intentDetectionServiceProvider = Provider((ref) {
  final llmService = ref.watch(llmServiceProvider);
  final functionGemma = ref.watch(functionGemmaServiceProvider);
  final utilityModelState = ref.watch(utilityModelManagerProvider);
  return IntentDetectionService(
    llmService: llmService,
    functionGemmaService: functionGemma,
    utilityModelState: utilityModelState,
  );
});

/// ─────────────────────────────────────────────────────────────────────────────
/// Hybrid Intent Detection Service (Rule-based + LLM Fallback)
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
/// 13. LLM Fallback (for ambiguous natural language)
/// 14. normalChat (default)
/// ─────────────────────────────────────────────────────────────────────────────
class IntentDetectionService {
  late final LLMIntentClassifier? _llmClassifier;
  FunctionGemmaService? _functionGemmaService;
  UtilityModelState? _utilityModelState;

  IntentDetectionService({
    LLMService? llmService,
    FunctionGemmaService? functionGemmaService,
    UtilityModelState? utilityModelState,
  }) {
    _llmClassifier = llmService != null ? LLMIntentClassifier(llmService) : null;
    _functionGemmaService = functionGemmaService;
    _utilityModelState = utilityModelState;
  }

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

    // ── Progressive Enhancement: FunctionGemma ──────────────────────────────
    // When FunctionGemma is downloaded and available, try model-based intent
    // classification FIRST. If it returns a valid function call, map it to an
    // IntentType and return immediately. If it returns null (timeout, error, or
    // no match), fall through silently to the existing regex engine below.
    // Guard: skip for trivially short messages (≤2 words) to avoid wasting
    // inference time on "hi", "hello", etc.
    if (words.length > 2 &&
        _utilityModelState != null &&
        _utilityModelState!.isFunctionGemmaAvailable &&
        _functionGemmaService != null) {
      try {
        final result = await _functionGemmaService!.classifyIntent(message);
        if (result != null) {
          final functionName = result['name'] as String?;
          if (functionName != null && functionToIntentMap.containsKey(functionName)) {
            final intentName = functionToIntentMap[functionName]!;
            final mapped = IntentType.values.cast<IntentType?>().firstWhere(
              (e) => e!.name == intentName,
              orElse: () => null,
            );
            if (mapped != null) {
              debugPrint('INTENT_DETECTION: FunctionGemma classified → $mapped');
              return mapped;
            }
          }
        }
      } catch (e) {
        debugPrint('INTENT_DETECTION: FunctionGemma failed, falling through to regex: $e');
      }
    }

    // ── 0️⃣  Greeting / trivial message fast-path ──────────────────────────
    // Very short messages (≤ 2 words) that don't contain a special trigger
    // keyword go straight to chat, preventing tiny typos from mis-routing.
    final greetingRe = RegExp(
      r'^(hi+|hey+|hello+|hai|haii*|heyy+|hyy*|yo+|sup|howdy|greetings|namaste|'
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

    // ── 3️⃣  Navigation ────────────────────────────────────────────────────
    // Must trigger on "navigate to", "directions to", "take me to" (for places, not apps)
    if (RegExp(
      r'^(navigate\s+to|directions\s+to|get\s+directions\s+to|'
      r'how\s+to\s+get\s+to|way\s+to|take\s+me\s+to)\s+\S',
      caseSensitive: false,
    ).hasMatch(lo)) {
      // Small heuristic: if it contains "settings" or "camera", those take priority
      if (!lo.contains('settings') && !lo.contains('camera')) {
        debugPrint('INTENT_DETECTION: Navigation command → navigation');
        return IntentType.navigation;
      }
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
    // IMPORTANT: Only trigger on EXPLICIT memory phrasing. Generic questions
    // like "what is oops" or "what is python" must NOT be caught here —
    // they should go to the LLM/web search to be answered.
    if (RegExp(
      r'^(recall|retrieve|fetch\s+from\s+memory|find\s+in\s+memory|'
      r'search\s+(my\s+)?memory|'
      r'what\s+did\s+i\s+(say|tell|save|store|ask|mention)|'
      r'what\s+do\s+you\s+(know|remember)\s+about\s+(me|my)|'
      r'what\s+did\s+you\s+(save|store|remember)|'
      r'have\s+you\s+saved|bring\s+up\s+(my\s+)?memor)',
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

    // ── 9️⃣  SMS / Text ───────────────────────────────────────────────────
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
      // Sub-route: if it starts with 'navigate to' or 'directions to', it's NAVIGATION
      if (RegExp(r'^(navigate|directions|get\s+directions|take\s+me|how\s+to\s+get)\s+to', caseSensitive: false).hasMatch(lo)) {
         return IntentType.navigation;
      }
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
    // ONLY explicit search commands go to web search. Knowledge questions like
    // "what is oops", "explain recursion", "who is Newton" are NOT caught here —
    // they go to normalChat so the LLM can answer them. The orchestrator then
    // redirects to web search ONLY for small models (which can't answer well).
    if (RegExp(
      r'^(search\s+(for\s+)?|google\s+|look\s+up\s+|lookup\s+|'
      r'browse\s+for\s+|search\s+the\s+web\s+for\s+|'
      r'find\s+(me\s+)?(the\s+)?(latest|current|news|price|cost))',
      caseSensitive: false,
    ).hasMatch(lo) ||
        lo.startsWith('[search]')) {
      debugPrint('INTENT_DETECTION: Explicit search command → webSearch');
      return IntentType.webSearch;
    }
    // Real-time info keywords — these genuinely need fresh web data.
    // "today" alone is NOT here (it matched "today's lunch" etc.) — it must
    // be paired with a real-time context word.
    // NOTE: weather/temperature/forecast are intentionally EXCLUDED here so
    // they reach the dedicated getWeather intent below, which uses the
    // Open-Meteo API (free, no key) instead of opening a browser search.
    if (RegExp(
      r'\b(latest\s+news|breaking\s+news|current\s+news|trending\s+now|'
      r'live\s+(score|update|match)|'
      r'price\s+of|cost\s+of|rate\s+of|stock\s+price|share\s+price|'
      r'cricket\s+score|football\s+result|match\s+result|'
      r'box\s+office|release\s+date\s+of|'
      r'todays?\s+(news|headlines|score|match|price|rate))\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Real-time keyword → webSearch');
      return IntentType.webSearch;
    }

    // ── 1️⃣2️⃣  URL Scrape ─────────────────────────────────────────────────
    if (containsURL(msg)) {
      debugPrint('INTENT_DETECTION: URL detected → urlScrape');
      return IntentType.urlScrape;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NEW FEATURES - Intent Detection for 5 High-Value Additions
    // ═══════════════════════════════════════════════════════════════════════

    // ── 📅 1. CALENDAR & EVENTS ─────────────────────────────────────────
    if (RegExp(
      r'\b(show|view|check|open|display)\b.*\b(calendar|schedule|agenda|appointments?|meetings?)\b|'
      r'\b(my\s+)?(calendar|schedule|agenda)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Calendar view → viewCalendar');
      return IntentType.viewCalendar;
    }

    if (RegExp(
      r'\b(next|upcoming|my\s+next)\b.*\b(event|meeting|appointment)\b|'
      r"what('?s| is)\s+(next|my\s+next|up\s+next|coming\s+up)",
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Next event query → getNextEvent');
      return IntentType.getNextEvent;
    }

    if (RegExp(
      r'^(schedule|create|add|make|set\s+up)\s+(an?\s+)?(event|meeting|appointment)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Create event → createEvent');
      return IntentType.createEvent;
    }

    // ── 🎵 2. MEDIA CONTROLS ────────────────────────────────────────────
    // Media control commands (but exclude YouTube/music search queries)
    if (RegExp(
      r'^\b(play|pause|resume|stop|next|skip|previous|back)\b(\s+(song|music|track|video|media))?$|'
      r'\b(pause|resume|skip|next|previous)\s+(the\s+)?(song|music|track|video|media)\b',
      caseSensitive: false,
    ).hasMatch(lo) &&
        !lo.contains('youtube') &&
        !RegExp(r'play\s+\S+\s+(on|in|music)', caseSensitive: false).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Media control → mediaControl');
      return IntentType.mediaControl;
    }

    if (RegExp(
      r'\b(brightness|screen\s+brightness|display\s+brightness)\b|'
      r'\b(increase|decrease|set|adjust|change)\b.*\b(brightness)\b|'
      r'\b(dim|brighten)\s+(the\s+)?(screen|display)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Brightness control → setBrightness');
      return IntentType.setBrightness;
    }

    if (RegExp(
      r'\b(take|capture|grab|get)\b.*\b(screenshot|screen\s+shot|screen\s+capture|screen\s+grab)\b|'
      r'^screenshot$',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Screenshot → screenshot');
      return IntentType.screenshot;
    }

    // ── 📱 3. READ MESSAGES/NOTIFICATIONS ───────────────────────────────
    if (RegExp(
      r'\b(read|check|show|display)\b.*\b(messages?|texts?|sms)\b|'
      r'^(my\s+)?(messages?|texts?)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Read messages → readMessages');
      return IntentType.readMessages;
    }

    if (RegExp(
      r'\b(read|check|show|display|what\s+are|list)\b.*\b(notifications?|alerts?)\b|'
      r'^notifications?$|^alerts?$',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Read notifications → readNotifications');
      return IntentType.readNotifications;
    }

    // ── 📝 4. QUICK NOTES ───────────────────────────────────────────────
    if (RegExp(
      r'^(note|create\s+note|make\s+note|add\s+note|write\s+note|'
      r'note\s+to\s+self|remember\s+this|jot\s+down|write\s+down)\s+',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Create note → createNote');
      return IntentType.createNote;
    }

    // ── 🧮 5. CALCULATOR & CONVERTER ────────────────────────────────────
    if (RegExp(
      r"\b(calculate|compute|what('?s| is))\b.*\b(\d+|percent|plus|minus|times|divide)|"
      r'^\d+\s*[+\-*/×÷]\s*\d+',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Calculation → calculate');
      return IntentType.calculate;
    }

    if (RegExp(
      r'\b(convert|change)\s+\d+(\.\d+)?\s+\w+\s+(to|into)\s+\w+\b|'
      r'\bhow\s+many\s+\w+\s+in\s+\d+(\.\d+)?\s+\w+\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Unit conversion → convert');
      return IntentType.convert;
    }

    // ═══════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════
    // SMART APP ACTIONS - Intent Detection
    // ═══════════════════════════════════════════════════════════════════════

    // WhatsApp message: requires imperative form to avoid catching questions
    // like "What's the message I sent on WhatsApp?" or "How do I send messages
    // on WhatsApp?". Must start with send/message/text/whatsapp + something.
    if (RegExp(
      r'^(send|message|text|whatsapp|whats\s*app|wa)\s+.*\b(whatsapp|whats\s*app|wa)\b|'
      r'^(whatsapp|whats\s*app|wa)\s+\w+',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: WhatsApp message -> sendWhatsApp');
      return IntentType.sendWhatsApp;
    }

    // Search on App: "search X on Amazon/Flipkart" / "find X on Swiggy"
    if (RegExp(
      r'\b(search|find|look\s+for|look\s+up|browse)\b.+\b(on|in)\s+(amazon|flipkart|myntra|swiggy|zomato|meesho|ajio)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Search on app -> searchOnApp');
      return IntentType.searchOnApp;
    }

    // UPI Payment: requires imperative form (pay/send-money) to avoid catching
    // info questions like "Tell me about UPI" or "What is GPay".
    if (RegExp(
      r'^(pay|send\s+money|make\s+(a\s+)?payment|upi\s+pay|gpay|phonpe|phone\s*pe|paytm)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: UPI payment -> upiPayment');
      return IntentType.upiPayment;
    }

    // Play on Spotify: "play X on spotify"
    if (RegExp(
      r'\b(play|listen\s+to)\b.+\b(on|in)\s+spotify\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Spotify play -> playOnSpotify');
      return IntentType.playOnSpotify;
    }

    // Book Ride: "book uber/ola/ride/cab to X"
    if (RegExp(
      r'\b(book|get|call)\s+(a\s+)?(uber|ola|ride|cab|taxi)\b|\b(uber|ola)\s+(to|ride)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Book ride -> bookRide');
      return IntentType.bookRide;
    }

    // Order Food: "order from swiggy/zomato" / "order food"
    if (RegExp(
      r'\b(order|get)\s+(food|something)?\s*(from|on|via)\s+(swiggy|zomato)\b|\border\s+food\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Order food -> orderFood');
      return IntentType.orderFood;
    }

    // Share Content: "share X to whatsapp/instagram" / "share to X"
    if (RegExp(
      r'\bshare\b.+\b(to|on|via)\s+(whatsapp|instagram|telegram|twitter|facebook|x)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Share content -> shareContent');
      return IntentType.shareContent;
    }

    // Open Profile: "open @username on instagram" / "check @X on twitter"
    if (RegExp(
      r'\b(open|check|visit|show|see|go\s+to)\s+@?\w+\s+(on|in)\s+(instagram|twitter|x|youtube|linkedin|facebook)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Open profile -> openProfile');
      return IntentType.openProfile;
    }

    // ═══════════════════════════════════════════════════════════════════════

    // ── Camera / OCR Scan ──────────────────────────────────────────────────
    if (RegExp(
      r'\b(scan|capture|ocr|extract\s+text|read\s+this|photograph|snap)\s+'
      r'(this|my|the|a|an)?\s*'
      r'(image|photo|picture|notes?|page|document|whiteboard|screenshot|screen|text|handwriting|book)\b',
      caseSensitive: false,
    ).hasMatch(lo) ||
    RegExp(
      r'\b(scan\s+(it|this|notes?|image|text)|open\s+scanner|camera\s+scan|'
      r'scan\s+from\s+camera|take\s+a\s+scan|read\s+from\s+(image|photo|camera))\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Scan image → scanImage');
      return IntentType.scanImage;
    }

    // ── Study Buddy ─────────────────────────────────────────────────────────
    if (RegExp(
      r'\b(create|make|generate|build)\s+(flashcards?|flash\s+cards?|study\s+cards?)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Create flashcards → studyCreateFlashcards');
      return IntentType.studyCreateFlashcards;
    }

    if (RegExp(
      r'\b(quiz\s+me|test\s+me|practice\s+quiz|start\s+quiz|begin\s+quiz|take\s+a\s+quiz)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Quiz → studyQuizMe');
      return IntentType.studyQuizMe;
    }

    if (RegExp(
      r'\b(review\s+(my\s+)?(flashcards?|cards?|flash\s+cards?)|study\s+review|spaced\s+repetition)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Review cards → studyReviewCards');
      return IntentType.studyReviewCards;
    }

    if (RegExp(
      r'\b(study\s+(stats?|statistics|progress|performance|analytics)|how\s+am\s+i\s+doing\s+in|my\s+study\s+progress)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Study stats → studyShowStats');
      return IntentType.studyShowStats;
    }

    if (RegExp(
      r'\b(i\s+have\s+(a|an)\s+exam|schedule\s+(an?\s+)?exam|exam\s+(on|in|at|is)|upcoming\s+exam|add\s+exam)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Exam schedule → studyScheduleExam');
      return IntentType.studyScheduleExam;
    }

    if (RegExp(
      r'\b(open\s+study\s*buddy|study\s+buddy|study\s+dashboard|my\s+decks?|show\s+(my\s+)?decks?)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Study dashboard → studyOpenDashboard');
      return IntentType.studyOpenDashboard;
    }

    // ── 📄 Document Generation / Export to PDF ──────────────────────────────
    // Catches many natural phrasings:
    //   "generate a pdf about X", "create a document about Y"
    //   "generate in pdf", "make it a pdf", "give me a pdf", "send as pdf"
    //   "export to pdf", "convert to pdf", "download as pdf", "save as pdf"
    //   "put this in a pdf", "in pdf format"
    if (RegExp(
      r'\b(generate|create|make|write|export|save|download|convert|give|send|put|export)\b'
      r'.*\b(pdf|document)\b|'
      r'\b(in|as|to)\s+(a\s+)?pdf\b|'
      r'\bpdf\s+(format|file|version)\b|'
      r'\b(write|create|generate|make)\s+(a\s+)?(report|essay|letter|resume|cv|document|notes)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Document generation → generateDocument');
      return IntentType.generateDocument;
    }

    // "write python/javascript/dart code for X and save"
    // "generate code for X", "create a script for Y"
    if (RegExp(
      r'\b(write|create|generate|make)\s+.*(code|script|program)\b.*\b(save|export|file|download)\b|'
      r'\b(generate|export)\s+(a\s+)?(python|javascript|dart|java|html|css|sql|code)\s+(file|script)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Code generation → generateCode');
      return IntentType.generateCode;
    }

    // "create a spreadsheet/csv about X", "generate csv data"
    if (RegExp(
      r'\b(create|generate|make|export)\s+(a\s+)?(csv|spreadsheet|excel|table\s+data)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: CSV generation → generateCsv');
      return IntentType.generateCsv;
    }

    // "summarize this chat/conversation and save/export"
    if (RegExp(
      r'\b(summarize|summary)\s+(this\s+)?(chat|conversation|discussion)\b.*\b(save|export|pdf|download)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Summarize chat → summarizeChat');
      return IntentType.summarizeChat;
    }

    // ── 🌤️ Weather ──────────────────────────────────────────────────────────
    if (RegExp(
      r'\b(weather|temperature|forecast|rain|sunny|cloudy|humid)\b.*\b(in|at|for|of)?\b',
      caseSensitive: false,
    ).hasMatch(lo) && !lo.contains('search')) {
      debugPrint('INTENT_DETECTION: Weather query → getWeather');
      return IntentType.getWeather;
    }

    // ── 📖 Wikipedia ────────────────────────────────────────────────────────
    if (RegExp(
      r'^(wiki|wikipedia)\s+|.*\b(wikipedia|wiki)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Wikipedia → getWikipedia');
      return IntentType.getWikipedia;
    }

    // ── 📰 News ─────────────────────────────────────────────────────────────
    if (RegExp(
      r'^(news|headlines|latest\s+news)\b|\b(news|headlines)\s+(about|on|for)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: News → getNews');
      return IntentType.getNews;
    }

    // ── 🎬 YouTube ──────────────────────────────────────────────────────────
    if (RegExp(
      r'\b(youtube|yt)\b.*\b(search|find|play|watch|show|look)\b|\b(search|find|play|watch)\b.*\b(youtube|yt)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: YouTube search → youtubeSearch');
      return IntentType.youtubeSearch;
    }

    // ── 🌐 Translation ──────────────────────────────────────────────────────
    if (RegExp(
      r'^translate\b|\btranslat(e|ion)\b.*\b(to|into|in)\s+\w+',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Translation → translateText');
      return IntentType.translateText;
    }

    // ── 📱 QR Code ──────────────────────────────────────────────────────────
    if (RegExp(
      r'\b(qr\s*code|generate\s+qr|create\s+qr|make\s+qr)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: QR Code → generateQRCode');
      return IntentType.generateQRCode;
    }

    // ── 📱 System Info ──────────────────────────────────────────────────────
    if (RegExp(
      r'\b(battery|storage|device\s+info|system\s+info|phone\s+info|ram|memory\s+usage)\b',
      caseSensitive: false,
    ).hasMatch(lo) && RegExp(r'\b(check|show|what|how\s+much|status)\b', caseSensitive: false).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: System info → getSystemInfo');
      return IntentType.getSystemInfo;
    }

    // ── 📍 Find Nearby ──────────────────────────────────────────────────────
    if (RegExp(
      r'\b(nearby|near\s+me|closest|nearest)\b.*\b(restaurant|hospital|atm|pharmacy|hotel|gas|petrol|cafe|gym|park|store|shop)\b|'
      r'\b(find|show|where)\b.*\b(restaurant|hospital|atm|pharmacy|hotel)\b.*\b(near|nearby|closest)\b',
      caseSensitive: false,
    ).hasMatch(lo)) {
      debugPrint('INTENT_DETECTION: Find nearby → findNearby');
      return IntentType.findNearby;
    }

    // ── 1️⃣3️⃣  LLM Fallback (for ambiguous natural language) ──────────────
    // Before giving up, check if this looks like it might be an action request
    // in natural language that the rule-based system missed
    if (_llmClassifier != null && isAmbiguous(msg, lo)) {
      debugPrint('INTENT_DETECTION: Ambiguous message, trying LLM classifier...');
      try {
        final classified = await _llmClassifier.classify(msg);
        if (classified != null && classified.type != IntentType.normalChat) {
          debugPrint('INTENT_DETECTION: LLM classified as ${classified.type}');
          return classified.type;
        }
      } catch (e) {
        debugPrint('INTENT_DETECTION: LLM classification failed: $e');
        // Continue to default
      }
    }

    // ── 1️⃣4️⃣  Default ───────────────────────────────────────────────────
    debugPrint('INTENT_DETECTION: No match → normalChat');
    return IntentType.normalChat;
  }

  /// Check if a message is ambiguous and might benefit from LLM classification
  ///
  /// Returns true if the message contains action keywords but doesn't match
  /// clear rule-based patterns (e.g., "can you call John" vs "call John").
  @visibleForTesting
  bool isAmbiguous(String message, String lo) {
    // If it starts with clear commands, it's NOT ambiguous
    if (RegExp(
      r'^(call|dial|text|sms|message|open|launch|start|search|find|'
      r'remind|navigate|email|take|snap|turn|toggle|close|kill|stop)\s+',
      caseSensitive: false,
    ).hasMatch(lo)) {
      return false; // Clear pattern, rules handled it
    }

    // Check for action words anywhere in the message
    final hasActionWords = RegExp(
      r'\b(call|dial|phone|ring|text|sms|message|msg|open|launch|start|'
      r'search|find|google|remind|set\s+alarm|navigate|directions|'
      r'email|mail|photo|picture|camera|selfie|flashlight|torch|'
      r'flash|settings|wifi|bluetooth)\b',
      caseSensitive: false,
    ).hasMatch(lo);

    if (!hasActionWords) {
      return false; // No action words, likely normal chat
    }

    // Contains conversational fluff + action words → ambiguous
    final hasConversationalFluff = RegExp(
      r'\b(can\s+you|could\s+you|would\s+you|will\s+you|please|pls|'
      r'i\s+want|i\s+need|i\s+would\s+like|i\s+wanna|let\s+me|'
      r'help\s+me|i\s+want\s+to|i\s+need\s+to|i\s+have\s+to|'
      r'kindly|requesting|may\s+i)\b',
      caseSensitive: false,
    ).hasMatch(lo);

    if (hasConversationalFluff && hasActionWords) {
      return true; // Needs LLM to understand intent
    }

    // Action word in the middle/end but not at start → might be ambiguous
    // Example: "John call kar" (Hinglish), "WhatsApp kholna hai" (Hindi + English)
    final words = lo.split(RegExp(r'\s+'));
    if (words.length >= 2 && hasActionWords) {
      // Check if action word is NOT in first position
      final firstWordIsAction = RegExp(
        r'^(call|dial|text|sms|open|launch|search|find|remind|navigate|email)',
        caseSensitive: false,
      ).hasMatch(words[0]);

      if (!firstWordIsAction) {
        return true; // Action word not at start → ambiguous
      }
    }

    return false; // Not ambiguous
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
    // Also handles "send hyy to pooja", "text hello there to rahul"
    final cmdRe = RegExp(
      r'^(send\s+|write\s+|text\s+|message\s+|msg\s+|sms\s+)'
      r'(a\s+)?(sms\s+|text\s+|message\s+|msg\s+)?(to\s+)?',
      caseSensitive: false,
    );
    final cm = cmdRe.firstMatch(clean);
    if (cm != null) {
      final remaining = clean.substring(cm.end).trim();
      final loRemaining = remaining.toLowerCase();

      // Check if remaining contains " to " — means "[body] to [name]"
      if (loRemaining.contains(' to ')) {
        final toIdx = loRemaining.indexOf(' to ');
        final potentialBody = remaining.substring(0, toIdx).trim();
        final potentialName = remaining.substring(toIdx + 4).trim();
        // Only treat as "[body] to [name]" if the name part looks like a name
        // (not a placeholder like "me", "1234567890" is still valid as a name)
        if (potentialName.isNotEmpty && potentialBody.isNotEmpty) {
          name = potentialName;
          body = potentialBody;
          final bodySepRe = RegExp(r'^(as|saying)\s+', caseSensitive: false);
          body = body.replaceFirst(bodySepRe, '');
          return {'name': name, 'message': body};
        }
      }

      // Fallback: first token = name, rest = body
      // e.g. "text Pooja how are you" (no "to" separator)
      //
      // But first check for an explicit message separator like "as" or "saying"
      // This handles spaced phone numbers: "text 90196 71670 as hai" → name=90196 71670, body=hai
      final bodySep = RegExp(r'\s+(as|saying)\s+', caseSensitive: false);
      final sepMatch = bodySep.firstMatch(remaining);
      if (sepMatch != null) {
        name = remaining.substring(0, sepMatch.start).trim();
        body = remaining.substring(sepMatch.end).trim();
      } else {
        final tokens = remaining.split(RegExp(r'\s+'));
        if (tokens.isNotEmpty) {
          name = tokens.first;
          if (tokens.length > 1) {
            body = tokens.sublist(1).join(' ');
          }
        }
      }
    }
    return {'name': name, 'message': body};
  }

  /// Navigation destination (strips navigate/directions prefix).
  String extractNavigationDestination(String message) {
    debugPrint('INTENT_DETECTION: Extracting destination from: $message');
    final prefixRe = RegExp(
      r'^(navigate\s+to|directions\s+to|get\s+directions\s+to|'
      r'how\s+to\s+get\s+to|way\s+to|take\s+me\s+to|get\s+me\s+to)\s+',
      caseSensitive: false,
    );
    final m = prefixRe.firstMatch(message.trim());
    return m != null ? message.trim().substring(m.end).trim() : message.trim();
  }
}
