void main() {
  String message = "Whatsapp hyy to Mithun";
  
  final cleaned = message
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
      .replaceAll(
        RegExp(r'^\s*(send|text|msg|message|write)\s+', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  print('Cleaned: "$cleaned"');

  String name = '';
  String body = '';

  final afterTo =
      cleaned.replaceFirst(RegExp(r'^to\s+', caseSensitive: false), '').trim();

  print('After to: "$afterTo"');

  final sepRe = RegExp(r'\s+(saying|:\s*|–\s*|-\s+)', caseSensitive: false);
  final sm = sepRe.firstMatch(afterTo);
  if (sm != null) {
    name = afterTo.substring(0, sm.start).trim();
    body = afterTo.substring(sm.end).trim();
  } else {
    final tokens = afterTo.split(RegExp(r'\s+'));
    if (tokens.isNotEmpty) {
      name = tokens.first;
      if (tokens.length > 1) body = tokens.sublist(1).join(' ');
    }
  }

  print('Extracted -> name: "$name", body: "$body"');
}
