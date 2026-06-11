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
    return _CodeCard(
      language: widget.language,
      langColor: langColor,
      actions: [
        _CopyButton(
          copied: _copied,
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
      ],
      child: _CodeBody(code: widget.code),
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
  int _tabIndex = 0;
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

    return _CodeCard(
      language: widget.language,
      langColor: langColor,
      actions: [
        _CopyButton(
          copied: _copied,
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
        const SizedBox(width: 8),
        _RunButton(
          isRunning: _isExecuting,
          isShowingResult: _tabIndex == 1,
          isHtml: isHtml,
          langColor: langColor,
          onTap: () {
            if (_tabIndex == 0) {
              setState(() => _tabIndex = 1);
              if (!isHtml && _executionOutput == null) _runCode();
            } else {
              setState(() => _tabIndex = 0);
            }
          },
        ),
      ],
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _tabIndex == 0
            ? _CodeBody(key: const ValueKey('code'), code: widget.code)
            : isHtml
                ? _HtmlPreview(key: const ValueKey('html'), code: widget.code)
                : _RunOutput(
                    key: const ValueKey('run'),
                    isExecuting: _isExecuting,
                    output: _executionOutput,
                    hasError: _hasError,
                    langColor: langColor,
                  ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PREMIUM UI COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════════

/// The outer card container — premium dark glass effect
class _CodeCard extends StatelessWidget {
  final String language;
  final Color langColor;
  final List<Widget> actions;
  final Widget child;

  const _CodeCard({
    required this.language,
    required this.langColor,
    required this.actions,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0d0d14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: langColor.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _CardHeader(language: language, langColor: langColor, actions: actions),
            // Code content
            child,
          ],
        ),
      ),
    );
  }
}

/// Sleek header bar with language label and action buttons
class _CardHeader extends StatelessWidget {
  final String language;
  final Color langColor;
  final List<Widget> actions;

  const _CardHeader({
    required this.language,
    required this.langColor,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          // Language indicator dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: langColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: langColor.withOpacity(0.5), blurRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            language == 'plaintext' ? 'Code' : language.toUpperCase(),
            style: GoogleFonts.outfit(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// Code text body with horizontal scroll
class _CodeBody extends StatelessWidget {
  final String code;

  const _CodeBody({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          code,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 12.5,
            height: 1.7,
            color: const Color(0xFFE4E4E8),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// HTML live preview
class _HtmlPreview extends StatelessWidget {
  final String code;

  const _HtmlPreview({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(14),
      child: HtmlWidget(
        code,
        textStyle: const TextStyle(color: Colors.white),
      ),
    );
  }
}

/// Code execution output panel
class _RunOutput extends StatelessWidget {
  final bool isExecuting;
  final String? output;
  final bool hasError;
  final Color langColor;

  const _RunOutput({
    super.key,
    required this.isExecuting,
    required this.output,
    required this.hasError,
    required this.langColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(
          color: const Color(0xFF080810),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: output == null
                ? Colors.white.withOpacity(0.06)
                : (hasError ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.2)),
          ),
        ),
        child: isExecuting
            ? Row(children: [
                SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: langColor),
                ),
                const SizedBox(width: 10),
                Text('Running...',
                    style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white38)),
              ])
            : output == null
                ? Row(children: [
                    Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 16),
                    const SizedBox(width: 6),
                    Text('Tap Run to execute',
                        style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white24)),
                  ])
                : SelectableText(
                    output!,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12.5,
                      height: 1.6,
                      color: hasError ? const Color(0xFFFF7B7B) : const Color(0xFF7CFC00),
                    ),
                  ),
      ),
    );
  }
}

// ── Action Buttons ────────────────────────────────────────────────────────────

/// Minimal copy button
class _CopyButton extends StatelessWidget {
  final bool copied;
  final VoidCallback onTap;

  const _CopyButton({required this.copied, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: copied ? Colors.green.withOpacity(0.15) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: copied ? Colors.green.withOpacity(0.3) : Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              copied ? Icons.check_rounded : Icons.content_copy_rounded,
              size: 13,
              color: copied ? Colors.green : Colors.white54,
            ),
            const SizedBox(width: 4),
            Text(
              copied ? 'Copied' : 'Copy',
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: copied ? Colors.green : Colors.white54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Run / Preview button
class _RunButton extends StatelessWidget {
  final bool isRunning;
  final bool isShowingResult;
  final bool isHtml;
  final Color langColor;
  final VoidCallback onTap;

  const _RunButton({
    required this.isRunning,
    required this.isShowingResult,
    required this.isHtml,
    required this.langColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = isShowingResult ? 'Code' : (isHtml ? 'Preview' : (isRunning ? 'Running' : 'Run'));
    final icon = isShowingResult
        ? Icons.code_rounded
        : (isHtml ? Icons.visibility_rounded : Icons.play_arrow_rounded);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: langColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: langColor.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: langColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: langColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
