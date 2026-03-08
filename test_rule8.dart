import 'dart:io';

void main() {
    String lo = "whatsapp to mithun";
    
    // Test Rule 8 directly
    bool waMatch = RegExp(
      r'\b(whatsapp|whats\s*app|send\s+on\s+whatsapp|message\s+on\s+whatsapp|'
      r'wa\s+message|text\s+on\s+whatsapp)\b',
      caseSensitive: false,
    ).hasMatch(lo);
    
    print("Rule 8 waMatch: $waMatch");
}
