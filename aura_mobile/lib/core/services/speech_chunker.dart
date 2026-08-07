/// Converts a streaming model response into speakable chunks.
///
/// Voice replies used to depend on the model emitting `.`/`!`/`?` followed by
/// whitespace. Models frequently stream long clauses, lists, or trailing text
/// without that pattern, which left the assistant silent. This chunker flushes
/// on real sentence ends, on clause boundaries once a chunk gets long, and
/// always drains whatever remains at the end of the stream.
class SpeechChunker {
  SpeechChunker({this.softLimit = 140, this.hardLimit = 240});

  /// Length after which a clause boundary (comma, semicolon, dash) may flush.
  final int softLimit;

  /// Length after which the chunker flushes at the last space regardless.
  final int hardLimit;

  final StringBuffer _buffer = StringBuffer();

  static final RegExp _abbreviation = RegExp(
    r'(?:^|\s)(mr|mrs|ms|dr|prof|sr|jr|st|vs|etc|e\.g|i\.e|approx|no)\.$',
    caseSensitive: false,
  );

  void add(String text) => _buffer.write(text);

  /// Returns the next speakable chunk, or null when more input is needed.
  String? takeChunk() {
    final text = _buffer.toString();
    if (text.trim().isEmpty) return null;

    final sentenceEnd = _lastSentenceEnd(text);
    if (sentenceEnd >= 0) return _cut(text, sentenceEnd + 1);

    if (text.length >= hardLimit) {
      final space = text.lastIndexOf(' ');
      return _cut(text, space > 0 ? space + 1 : text.length);
    }

    if (text.length >= softLimit) {
      final clause = _lastClauseBreak(text);
      if (clause >= 0) return _cut(text, clause + 1);
    }

    return null;
  }

  /// Returns any buffered remainder, used when the stream completes.
  String? drain() {
    final remaining = _buffer.toString().trim();
    _buffer.clear();
    return remaining.isEmpty ? null : remaining;
  }

  String? _cut(String text, int end) {
    final chunk = text.substring(0, end).trim();
    _buffer.clear();
    _buffer.write(text.substring(end));
    return chunk.isEmpty ? null : chunk;
  }

  int _lastClauseBreak(String text) {
    for (var i = text.length - 1; i >= 0; i--) {
      final char = text[i];
      if (char == ',' || char == ';' || char == ':' || char == '—') return i;
    }
    return -1;
  }

  int _lastSentenceEnd(String text) {
    for (var i = text.length - 1; i >= 0; i--) {
      final char = text[i];
      if (char == '\n') return i;
      if (char != '.' && char != '!' && char != '?') continue;

      // Require a following separator so mid-token punctuation is not a break.
      if (i + 1 >= text.length) continue;
      final next = text[i + 1];
      if (next != ' ' && next != '\n' && next != '\r' && next != '"') continue;

      // Skip decimals like 3.5 and common abbreviations like "Dr.".
      if (char == '.' && i > 0) {
        final prev = text[i - 1];
        final isDigitPair =
            _isDigit(prev) && i + 1 < text.length && _isDigit(next);
        if (isDigitPair) continue;
        if (_abbreviation.hasMatch(text.substring(0, i + 1))) continue;
      }
      return i;
    }
    return -1;
  }

  bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}
