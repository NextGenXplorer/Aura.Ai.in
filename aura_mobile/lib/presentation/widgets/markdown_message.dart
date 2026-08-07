import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:aura_mobile/presentation/widgets/code_element_builder.dart';
import 'package:aura_mobile/core/services/image_download_service.dart';

/// Markdown renderer for chat messages that can never overflow horizontally.
///
/// flutter_markdown lays tables out with flexible columns inside the bubble's
/// width. With three or more columns that squeezes each cell down to a couple
/// of characters (one letter per line) and still overflows on narrow phones,
/// because a table cell cannot be narrower than its widest unbreakable word.
///
/// So tables are pulled out of the markdown stream and rendered here with
/// intrinsic column widths inside a horizontal scroll view: columns get the
/// width their text actually needs, and the user swipes sideways for wide
/// tables. Everything else is handed to [MarkdownBody] unchanged.
class MarkdownMessage extends StatefulWidget {
  const MarkdownMessage({
    super.key,
    required this.data,
    this.onTapLink,
    this.useCodeBuilder = true,
    this.selectable = true,
  });

  final String data;
  final MarkdownTapLinkCallback? onTapLink;

  /// Whether fenced code blocks render as interactive code cards.
  final bool useCodeBuilder;

  final bool selectable;

  /// Widest a single table column may grow before its text wraps.
  static const double _maxColumnWidth = 260;

  static MarkdownStyleSheet? _cachedStyleSheet;

  /// Shared text styling so every bubble renders markdown identically.
  ///
  /// Cached because it is identical for every message and building it involves
  /// a `GoogleFonts.outfit()` lookup — cheap once, wasteful on every rebuild of
  /// every bubble.
  static MarkdownStyleSheet styleSheet(BuildContext context) {
    return _cachedStyleSheet ??= _buildStyleSheet();
  }

  static MarkdownStyleSheet _buildStyleSheet() {
    return MarkdownStyleSheet(
      p: TextStyle(
        color: ClayColors.textDark,
        fontSize: 15,
        height: 1.5,
        fontFamily: GoogleFonts.outfit().fontFamily,
      ),
      strong: const TextStyle(
        color: ClayColors.textDark,
        fontWeight: FontWeight.bold,
      ),
      a: const TextStyle(
        color: ClayColors.goldAccent,
        decoration: TextDecoration.underline,
      ),
      code: TextStyle(
        color: const Color(0xFF7A4A2B),
        backgroundColor: ClayColors.goldAccent.withOpacity(0.10),
        fontFamily: 'monospace',
        fontSize: 13.5,
      ),
      tableBorder: TableBorder.all(
        color: ClayColors.goldAccent.withOpacity(0.25),
        width: 1,
      ),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
    );
  }

  @override
  State<MarkdownMessage> createState() => _MarkdownMessageState();

  // ── Parsing ───────────────────────────────────────────────────────────────

  /// Matches a GitHub-flavoured table delimiter row, e.g. `|---|:--:|---:|`.
  static final RegExp _delimiterRow = RegExp(
    r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$',
  );

  /// Splits [data] into alternating prose and table segments.
  static List<MarkdownSegment> splitSegments(String data) {
    final lines = data.split('\n');
    final segments = <MarkdownSegment>[];
    final buffer = <String>[];
    var inFence = false;

    void flushProse() {
      if (buffer.isEmpty) return;
      segments.add(MarkdownSegment(buffer.join('\n'), isTable: false));
      buffer.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Never treat table-looking text inside a fenced code block as a table.
      if (line.trimLeft().startsWith('```')) {
        inFence = !inFence;
        buffer.add(line);
        continue;
      }
      if (inFence) {
        buffer.add(line);
        continue;
      }

      final isHeader = line.contains('|') && line.trim().isNotEmpty;
      final hasDelimiter =
          i + 1 < lines.length &&
          _delimiterRow.hasMatch(lines[i + 1]) &&
          lines[i + 1].contains('-');

      if (isHeader && hasDelimiter) {
        flushProse();
        final tableLines = <String>[line, lines[i + 1]];
        var j = i + 2;
        while (j < lines.length &&
            lines[j].contains('|') &&
            lines[j].trim().isNotEmpty) {
          tableLines.add(lines[j]);
          j++;
        }
        segments.add(MarkdownSegment(tableLines.join('\n'), isTable: true));
        i = j - 1;
        continue;
      }

      buffer.add(line);
    }

    flushProse();
    if (segments.isEmpty) {
      segments.add(MarkdownSegment(data, isTable: false));
    }
    return segments;
  }

  /// Parses a GFM table block into rows of cell text. The delimiter row is
  /// dropped; the first returned row is the header.
  static List<List<String>> parseTable(String table) {
    final rows = <List<String>>[];
    for (final line in table.split('\n')) {
      if (line.trim().isEmpty) continue;
      if (_delimiterRow.hasMatch(line) && line.contains('-')) continue;
      rows.add(_splitCells(line));
    }
    if (rows.isEmpty) return rows;

    // Pad short rows so Table gets a uniform child count.
    final columns = rows.fold<int>(
      0,
      (max, r) => r.length > max ? r.length : max,
    );
    for (final row in rows) {
      while (row.length < columns) {
        row.add('');
      }
    }
    return rows;
  }

  static List<String> _splitCells(String line) {
    final cells = <String>[];
    final current = StringBuffer();
    var escaped = false;

    for (final rune in line.runes) {
      final char = String.fromCharCode(rune);
      if (escaped) {
        // Keep an escaped pipe as literal text inside the cell.
        current.write(char == '|' ? '|' : '\\$char');
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '|') {
        cells.add(current.toString().trim());
        current.clear();
        continue;
      }
      current.write(char);
    }
    cells.add(current.toString().trim());

    // A leading/trailing pipe produces an empty edge cell; drop those only.
    if (cells.isNotEmpty && cells.first.isEmpty) cells.removeAt(0);
    if (cells.isNotEmpty && cells.last.isEmpty) cells.removeLast();
    return cells;
  }
}

class _MarkdownMessageState extends State<MarkdownMessage> {
  /// Segment splitting (and table parsing) walks the whole message text. During
  /// streaming the bubble is rebuilt repeatedly, so the result is computed only
  /// when the text actually changes rather than on every build.
  late List<MarkdownSegment> _segments;
  late List<List<List<String>>> _tableRows;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(MarkdownMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _parse();
  }

  void _parse() {
    _segments = MarkdownMessage.splitSegments(widget.data);
    _tableRows = [
      for (final segment in _segments)
        if (segment.isTable)
          MarkdownMessage.parseTable(segment.text)
        else
          const <List<String>>[],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sheet = MarkdownMessage.styleSheet(context);

    if (_segments.length == 1 && !_segments.first.isTable) {
      return _buildMarkdown(context, _segments.first.text, sheet);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _segments.length; i++)
          if (_segments[i].isTable)
            _ScrollableTable(
              rows: _tableRows[i],
              styleSheet: sheet,
              maxColumnWidth: MarkdownMessage._maxColumnWidth,
            )
          else
            _buildMarkdown(context, _segments[i].text, sheet),
      ],
    );
  }

  Widget _buildMarkdown(
    BuildContext context,
    String text,
    MarkdownStyleSheet sheet,
  ) {
    return MarkdownBody(
      data: text,
      styleSheet: sheet,
      builders: widget.useCodeBuilder
          ? {'code': CodeElementBuilder(context)}
          : const {},
      imageBuilder: (uri, title, alt) =>
          DownloadableChatImage(url: uri.toString(), alt: alt),
      onTapLink: widget.onTapLink,
      selectable: widget.selectable,
    );
  }
}

/// A prose or table chunk of a markdown message.
class MarkdownSegment {
  const MarkdownSegment(this.text, {required this.isTable});

  final String text;
  final bool isTable;
}

// ── Table rendering ─────────────────────────────────────────────────────────

class _ScrollableTable extends StatelessWidget {
  const _ScrollableTable({
    required this.rows,
    required this.styleSheet,
    required this.maxColumnWidth,
  });

  final List<List<String>> rows;
  final MarkdownStyleSheet styleSheet;
  final double maxColumnWidth;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final headerStyle = (styleSheet.p ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.bold,
      fontSize: 14,
    );
    final bodyStyle = (styleSheet.p ?? const TextStyle()).copyWith(
      fontSize: 14,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 6),
          child: Table(
            // Take the natural width of the content, capped at
            // [maxColumnWidth] (MinColumnWidth picks the smaller of the two).
            defaultColumnWidth: MinColumnWidth(
              const IntrinsicColumnWidth(),
              FixedColumnWidth(maxColumnWidth),
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: styleSheet.tableBorder,
            children: [
              for (var r = 0; r < rows.length; r++)
                TableRow(
                  decoration: r == 0
                      ? BoxDecoration(
                          color: ClayColors.goldAccent.withOpacity(0.08),
                        )
                      : null,
                  children: [
                    for (final cell in rows[r])
                      TableCell(
                        child: Padding(
                          padding:
                              styleSheet.tableCellsPadding ??
                              const EdgeInsets.all(8),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: maxColumnWidth,
                            ),
                            child: Text(
                              _breakLongWords(_stripInlineMarkdown(cell)),
                              style: r == 0 ? headerStyle : bodyStyle,
                              softWrap: true,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Table cells are plain text: rendering nested markdown widgets inside an
  /// intrinsic-width Table is what produced full-width code cards inside cells.
  /// Emphasis and code markers are stripped so the text stays readable.
  static String _stripInlineMarkdown(String cell) {
    var text = cell.replaceAll('<br>', ' ').replaceAll('<br/>', ' ');
    text = text.replaceAll('`', '');
    text = text.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_'),
      (m) => m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4) ?? '',
    );
    // [label](url) → label
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
      (m) => m.group(1) ?? '',
    );
    return text.trim();
  }

  /// Inserts zero-width break opportunities into very long unbroken tokens
  /// (URLs, identifiers). Without this a single long word cannot wrap and would
  /// overflow its capped column.
  static String _breakLongWords(String text) {
    const threshold = 24;
    const chunk = 16;
    return text.splitMapJoin(
      RegExp(r'\S+'),
      onMatch: (m) {
        final word = m[0]!;
        if (word.length <= threshold) return word;
        final buffer = StringBuffer();
        for (var i = 0; i < word.length; i += chunk) {
          if (i > 0) buffer.write('\u200B');
          buffer.write(
            word.substring(
              i,
              i + chunk > word.length ? word.length : i + chunk,
            ),
          );
        }
        return buffer.toString();
      },
    );
  }
}

/// A network image rendered inside a chat bubble with a floating "download"
/// button in the top-right corner. Used for AI-generated images so the user
/// can save them straight to the gallery.
class DownloadableChatImage extends StatefulWidget {
  const DownloadableChatImage({super.key, required this.url, this.alt});

  final String url;
  final String? alt;

  @override
  State<DownloadableChatImage> createState() => _DownloadableChatImageState();
}

class _DownloadableChatImageState extends State<DownloadableChatImage> {
  bool _saving = false;

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await ImageDownloadService.saveFromUrl(widget.url);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Saved to gallery (Pictures/AURA)' : 'Could not save image',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Image.network(
              widget.url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    color: ClayColors.obsidianBg,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ClayColors.goldAccent,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stack) => Container(
                height: 120,
                color: ClayColors.obsidianBg,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: ClayColors.textMuted,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withOpacity(0.45),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _saving ? null : _download,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
