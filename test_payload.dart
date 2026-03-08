import 'dart:io';

void main() {
  String text = "WhatsApp +91932152668 hyyy";
  var lo = text.toLowerCase().trim();
  
  // Rule 7: Dial
  var dialReg = RegExp(
      r'^(call|dial|phone|ring\s*up|ring|buzz|make\s+a\s+call\s+to|'
      r'place\s+a\s+call\s+to|connect\s+me\s+to|get\s+me\s+on\s+the\s+phone\s+with|'
      r'speak\s+to|talk\s+to|i\s+want\s+to\s+talk\s+to)\s+\S',
      caseSensitive: false,
    );
  if (dialReg.hasMatch(lo)) {
    print("Matched Dial Rule A");
  }

  // Rule 8: WhatsApp
  var waReg = RegExp(
      r'\b(whatsapp|whats\s*app|send\s+on\s+whatsapp|message\s+on\s+whatsapp|'
      r'wa\s+message|text\s+on\s+whatsapp)\b',
      caseSensitive: false,
    );
  if (waReg.hasMatch(lo)) {
    print("Matched WhatsApp Rule");
    
    // Test extract
    final cleaned = text
        .replaceAll(
          RegExp(
            r'\b(whatsapp|whats\s*app|on\s+whatsapp|via\s+whatsapp|'
            r'through\s+whatsapp|wa\s+message|text\s+on\s+whatsapp|'
            r'message\s+on\s+whatsapp|send\s+on\s+whatsapp|'
            r'send\s+a\s+message\s+on\s+whatsapp|send\s+message\s+on\s+whatsapp)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        // also strip leading action verbs left over (send, text, message)
        .replaceAll(
          RegExp(r'^\s*(send|text|msg|message|write)\s+', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    print('Cleaned: "$cleaned"');
    
    // Tokens
    final startsWithTo = RegExp(r'^to\s+(\S+)(?:\s+(.+))?$', caseSensitive: false);
    final matchToLoc1 = startsWithTo.firstMatch(cleaned);
    if (matchToLoc1 != null) {
      print("Match toLoc1");
    }
  }
}
