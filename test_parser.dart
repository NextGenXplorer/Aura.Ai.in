void main() {
  final inputs = [
    "whatsapp to mithun",
    "whatsapp mithun",
    "whatsapp to mithun hi",
    "can you whatsapp to mithun"
  ];

  for (final rawText in inputs) {
    print('Testing "$rawText"');
    String text = rawText.toLowerCase().trim();
    final fillers = [
      "can you ", "could you ", "please ", "for me", "hey aura ", "aura ",
      "just ", "quickly ", "i want to ", "i need to ", "i'd like to ",
      "i would like to ", "go ahead and ", "would you ", "will you ",
      "kindly ", "hey ", "yo ", "help me "
    ];
    for (final filler in fillers) {
      text = text.replaceAll(filler, "");
    }
    text = text.trim();

    final whatsappRegex = RegExp(r'\b(whatsapp|whats\s*app)\b', caseSensitive: false);
    if (whatsappRegex.hasMatch(text)) {
      var remaining = text
          .replaceAll(whatsappRegex, "")
          .replaceAll(RegExp(r'^\s*(send|text|message|msg|write)?\s*(to\s+)?', caseSensitive: false), "")
          .trim();
      if (remaining.isNotEmpty) {
        final tokens = remaining.split(RegExp(r'\s+'));
        final contactName = tokens[0].trim();
        final message = tokens.length > 1 ? tokens.sublist(1).join(' ').trim() : "";
        if (contactName.isNotEmpty && contactName != "me" && contactName != "to") {
          print("  -> ParsedCommand.SendWhatsApp('$contactName', '$message')");
          continue;
        }
      }
    }

    final callRegex = RegExp(r'^(call|phone|ring\s*up|buzz)\s+(.+)$', caseSensitive: false);
    final callMatch = callRegex.firstMatch(text);
    if (callMatch != null) {
        final contactName = callMatch.group(2)!.trim();
        print("  -> ParsedCommand.CallContact('$contactName')");
        continue;
    }

    print("  -> Unknown");
  }
}
