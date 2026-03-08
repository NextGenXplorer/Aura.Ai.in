// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:aura_mobile/domain/services/code_execution_service.dart';

final CodeExecutionService _executionService = CodeExecutionService();

// ── Language helpers ──────────────────────────────────────────────────────────
IconData _langIcon(String lang) {
  switch (lang) {
    case 'python': return Icons.auto_awesome;
    case 'javascript': case 'js': return Icons.javascript;
    case 'html': return Icons.language;
    case 'dart': return Icons.flash_on;
    case 'java': return Icons.coffee;
    case 'kotlin': return Icons.android;
    case 'cpp': case 'c': return Icons.memory;
    case 'bash': case 'sh': return Icons.terminal;
    case 'rust': return Icons.shield;
    case 'go': return Icons.speed;
    case 'swift': return Icons.apple;
    case 'typescript': case 'ts': return Icons.code;
    default: return Icons.code;
  }
}

Color _langColor(String lang) {
  switch (lang) {
    case 'python': return const Color(0xFF4B8BBE);
    case 'javascript': case 'js': return const Color(0xFFF7DF1E);
    case 'html': return const Color(0xFFE34C26);
    case 'dart': return const Color(0xFF54C5F8);
    case 'java': return const Color(0xFFF89820);
    case 'kotlin': return const Color(0xFF7F52FF);
    case 'cpp': case 'c': return const Color(0xFF659BD3);
    case 'bash': case 'sh': return const Color(0xFF89E051);
    case 'rust': return const Color(0xFFDEA584);
    case 'go': return const Color(0xFF00ADD8);
    case 'swift': return const Color(0xFFFA7343);
    case 'typescript': case 'ts': return const Color(0xFF3178C6);
    default: return const Color(0xFFc69c3a);
  }
}

// ── MarkdownElementBuilder ────────────────────────────────────────────────────
class CodeElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  CodeElementBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag != 'code') return null;

    String textContent = element.textContent;
    if (textContent.endsWith('\n')) {
      textContent = textContent.substring(0, textContent.length - 1);
    }

    String language = 'plaintext';
    final String? className = element.attributes['class'];
    if (className != null && className.startsWith('language-')) {
      language = className.substring(9).toLowerCase();
    }

    const nonExecutable = [
      'css', 'scss', 'sass', 'less', 'json', 'yaml', 'yml',
      'md', 'markdown', 'sql', 'plaintext', ''
    ];

    // Force full screen width — SizedBox breaks out of MarkdownBody's
    // internal layout constraints which would otherwise squish the widget
    final screenWidth = MediaQuery.of(context).size.width - 8;
    final widget = !nonExecutable.contains(language)
        ? _CodeBlockWithPreview(code: textContent, language: language)
        : _SimpleCodeBlock(code: textContent, language: language);

    return SizedBox(width: screenWidth, child: widget);
  }
}

// ── Simple Code Block (no tabs) ───────────────────────────────────────────────
class _SimpleCodeBlock extends StatefulWidget {
  final String code;
  final String language;
  const _SimpleCodeBlock({required this.code, required this.language});

  @override
  State<_SimpleCodeBlock> createState() => _SimpleCodeBlockState();
}

class _SimpleCodeBlockState extends State<_SimpleCodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final langColor = _langColor(widget.language);
    return _buildCard(
      langColor: langColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — same as email draft header
          _buildCardHeader(widget.language, langColor),
          // Divider
          Container(height: 1, color: langColor.withOpacity(0.18)),
          // Code body
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                widget.code,
                style: GoogleFonts.firaCode(
                    fontSize: 13, height: 1.6, color: const Color(0xFFCDD6F4)),
              ),
            ),
          ),
          // Action buttons at bottom — like email card
          _buildBottomActions(
            left: _ActionBtn(
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              label: _copied ? 'Copied!' : 'Copy Code',
              color: Colors.white70,
              outlined: true,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: widget.code));
                if (mounted) {
                  setState(() => _copied = true);
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _copied = false);
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Interactive Code Block (Code + Preview/Run tabs) ─────────────────────────
class _CodeBlockWithPreview extends StatefulWidget {
  final String code;
  final String language;
  const _CodeBlockWithPreview({required this.code, required this.language});

  @override
  State<_CodeBlockWithPreview> createState() => _CodeBlockWithPreviewState();
}

class _CodeBlockWithPreviewState extends State<_CodeBlockWithPreview> {
  int _tabIndex = 0; // 0 = Code, 1 = Preview/Run
  bool _isExecuting = false;
  String? _executionOutput;
  bool _hasError = false;
  bool _copied = false;

  Future<void> _runCode() async {
    setState(() { _isExecuting = true; _executionOutput = null; _hasError = false; });
    final output = await _executionService.executeCode(widget.code, widget.language);
    if (mounted) {
      final lower = output.toLowerCase();
      setState(() {
        _isExecuting = false;
        _hasError = lower.contains('error') || lower.contains('exception') || lower.contains('traceback');
        _executionOutput = output;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHtml = widget.language == 'html';
    final langColor = _langColor(widget.language);

    return _buildCard(
      langColor: langColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildCardHeader(widget.language, langColor),
          // Divider
          Container(height: 1, color: langColor.withOpacity(0.18)),
          // Body — code or preview
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            child: _tabIndex == 0
                ? _buildCodeView()
                : isHtml
                    ? _buildHtmlPreview()
                    : _buildRunView(langColor),
          ),
          // Divider before buttons
          Container(height: 1, color: langColor.withOpacity(0.12)),
          // Bottom action buttons — exactly like email card
          _buildBottomActions(
            left: _ActionBtn(
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              label: _copied ? 'Copied!' : 'Copy Code',
              color: Colors.white70,
              outlined: true,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: widget.code));
                if (mounted) {
                  setState(() => _copied = true);
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _copied = false);
                  });
                }
              },
            ),
            right: _ActionBtn(
              icon: _tabIndex == 0
                  ? (isHtml ? Icons.preview : Icons.play_arrow_rounded)
                  : Icons.data_object,
              label: _tabIndex == 0
                  ? (isHtml ? 'Preview' : (_isExecuting ? 'Running...' : 'Run Code'))
                  : 'View Code',
              color: Colors.black,
              accentColor: langColor,
              outlined: false,
              onTap: () {
                if (_tabIndex == 0) {
                  setState(() => _tabIndex = 1);
                  if (!isHtml && _executionOutput == null) _runCode();
                } else {
                  setState(() => _tabIndex = 0);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          widget.code,
          style: GoogleFonts.firaCode(
              fontSize: 13, height: 1.6, color: const Color(0xFFCDD6F4)),
        ),
      ),
    );
  }

  Widget _buildHtmlPreview() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      color: const Color(0xFF080810),
      padding: const EdgeInsets.all(14),
      child: HtmlWidget(
        widget.code,
        textStyle: const TextStyle(color: Colors.white),
      ),
    );
  }

  Widget _buildRunView(Color langColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          color: const Color(0xFF080810),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _executionOutput == null
                ? const Color(0x1AFFFFFF)
                : (_hasError
                    ? const Color(0x66FF0000)
                    : const Color(0x4D00FF00)),
          ),
        ),
        child: _isExecuting
            ? Row(children: [
                SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: langColor),
                ),
                const SizedBox(width: 10),
                Text('Executing...',
                    style: GoogleFonts.firaCode(
                        fontSize: 12, color: const Color(0x80FFFFFF))),
              ])
            : _executionOutput == null
                ? Row(children: [
                    const Icon(Icons.chevron_right,
                        color: Color(0x44FFFFFF), size: 16),
                    const SizedBox(width: 6),
                    Text('Click "Run Code" to execute',
                        style: GoogleFonts.firaCode(
                            fontSize: 12, color: const Color(0x44FFFFFF))),
                  ])
                : SelectableText(
                    _executionOutput!,
                    style: GoogleFonts.firaCode(
                      fontSize: 13, height: 1.65,
                      color: _hasError
                          ? const Color(0xFFFF7B7B)
                          : const Color(0xFF7CFC00),
                    ),
                  ),
      ),
    );
  }
}

// ── Shared card shell — mirrors email draft card exactly ──────────────────────
Widget _buildCard({required Color langColor, required Widget child}) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1a1a22), Color(0xFF141418)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: langColor.withOpacity(0.4), width: 1.2),
    ),
    child: child,
  );
}

// ── Card header — mirrors "Email Draft" header exactly ────────────────────────
Widget _buildCardHeader(String language, Color langColor) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: langColor.withOpacity(0.12),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    ),
    child: Row(
      children: [
        Icon(_langIcon(language), color: langColor, size: 18),
        const SizedBox(width: 8),
        Text(
          language == 'plaintext' ? 'Code' : language.toUpperCase(),
          style: GoogleFonts.outfit(
            color: langColor,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}

// ── Bottom action row — mirrors "Done Editing / Send Email" ───────────────────
class _ActionBtn {
  final IconData icon;
  final String label;
  final Color color;
  final Color? accentColor;
  final bool outlined;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon, required this.label, required this.color,
    required this.outlined, required this.onTap, this.accentColor,
  });
}

Widget _buildBottomActions({required _ActionBtn left, _ActionBtn? right}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    child: Row(
      children: [
        Expanded(
          child: _buildBtn(left),
        ),
        if (right != null) ...[
          const SizedBox(width: 10),
          Expanded(child: _buildBtn(right)),
        ],
      ],
    ),
  );
}

Widget _buildBtn(_ActionBtn btn) {
  if (btn.outlined) {
    return OutlinedButton.icon(
      icon: Icon(btn.icon, size: 16, color: btn.color),
      label: Text(btn.label,
          style: GoogleFonts.outfit(color: btn.color, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.white.withOpacity(0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      onPressed: btn.onTap,
    );
  } else {
    return ElevatedButton.icon(
      icon: Icon(btn.icon, size: 16, color: btn.color),
      label: Text(btn.label,
          style: GoogleFonts.outfit(
              color: btn.color, fontWeight: FontWeight.bold, fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: btn.accentColor ?? const Color(0xFFc69c3a),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      onPressed: btn.onTap,
    );
  }
}
