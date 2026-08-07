import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:aura_mobile/features/smart_summarizer/share_receiver_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';

/// Bottom sheet that appears when content is shared TO AURA from another app.
/// Offers: Summarize, Translate, Reply, Explain, Copy summary.
class SummarizerSheet extends ConsumerStatefulWidget {
  final SharedContent content;
  const SummarizerSheet({super.key, required this.content});

  /// Show the summarizer bottom sheet
  static void show(BuildContext context, SharedContent content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F4EF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SummarizerSheet(content: content),
        ),
      ),
    );
  }

  @override
  ConsumerState<SummarizerSheet> createState() => _SummarizerSheetState();
}

class _SummarizerSheetState extends ConsumerState<SummarizerSheet> {
  String _result = '';
  bool _isProcessing = false;
  _SummaryAction _currentAction = _SummaryAction.summarize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Text(
            '📥 Shared Content',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF191816),
            ),
          ),
          const SizedBox(height: 8),

          // Preview of shared content
          Container(
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxHeight: 100),
            decoration: BoxDecoration(
              color: const Color(0xFFEFECE6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Text(
                widget.content.text.length > 300
                    ? '${widget.content.text.substring(0, 300)}...'
                    : widget.content.text,
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  color: const Color(0xFF4A4A4A),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Action buttons row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _actionChip('Summarize', Icons.auto_awesome, _SummaryAction.summarize),
                const SizedBox(width: 8),
                _actionChip('Explain', Icons.lightbulb_outline, _SummaryAction.explain),
                const SizedBox(width: 8),
                _actionChip('Key Points', Icons.list_alt, _SummaryAction.keyPoints),
                const SizedBox(width: 8),
                _actionChip('Translate', Icons.translate, _SummaryAction.translate),
                const SizedBox(width: 8),
                _actionChip('Reply', Icons.reply, _SummaryAction.reply),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Result area
          Expanded(
            child: _isProcessing
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFFB3862B)),
                        SizedBox(height: 12),
                        Text('AI is thinking...'),
                      ],
                    ),
                  )
                : _result.isEmpty
                    ? Center(
                        child: Text(
                          'Tap an action above to process this content',
                          style: GoogleFonts.outfit(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFB3862B).withOpacity(0.3),
                            ),
                          ),
                          child: SelectableText(
                            _result,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              height: 1.5,
                              color: const Color(0xFF191816),
                            ),
                          ),
                        ),
                      ),
          ),

          // Bottom action bar (copy, share)
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyResult,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB3862B),
                      side: const BorderSide(color: Color(0xFFB3862B)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _shareResult,
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB3862B),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionChip(String label, IconData icon, _SummaryAction action) {
    final isActive = _currentAction == action && _isProcessing;
    return ActionChip(
      avatar: Icon(icon, size: 16,
          color: isActive ? Colors.white : const Color(0xFFB3862B)),
      label: Text(label,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFF191816),
            fontSize: 12,
          )),
      backgroundColor: isActive ? const Color(0xFFB3862B) : const Color(0xFFEFECE6),
      onPressed: _isProcessing ? null : () => _runAction(action),
    );
  }

  Future<void> _runAction(_SummaryAction action) async {
    setState(() {
      _isProcessing = true;
      _currentAction = action;
      _result = '';
    });

    try {
      final llm = ref.read(llmServiceProvider);
      if (!llm.isModelLoaded) {
        setState(() {
          _result = '⚠️ No AI model loaded. Please load a model first from the sidebar.';
          _isProcessing = false;
        });
        return;
      }

      final prompt = _buildPrompt(action, widget.content.text);
      final buffer = StringBuffer();

      await for (final chunk in llm.chat(prompt, maxTokens: 512, temperature: 0.3)) {
        buffer.write(chunk);
        setState(() => _result = buffer.toString());
      }
    } catch (e) {
      setState(() => _result = '❌ Error: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  String _buildPrompt(_SummaryAction action, String text) {
    // Truncate to fit context window
    final truncated = text.length > 2000 ? text.substring(0, 2000) : text;

    switch (action) {
      case _SummaryAction.summarize:
        return 'Summarize the following text in 3-5 concise bullet points:\n\n$truncated';
      case _SummaryAction.explain:
        return 'Explain the following text in simple, easy-to-understand language:\n\n$truncated';
      case _SummaryAction.keyPoints:
        return 'Extract the key points from this text as a numbered list:\n\n$truncated';
      case _SummaryAction.translate:
        return 'Translate the following text to English (if already in English, translate to Hindi):\n\n$truncated';
      case _SummaryAction.reply:
        return 'Write a short, polite reply to the following message:\n\n$truncated';
    }
  }

  void _copyResult() {
    Clipboard.setData(ClipboardData(text: _result));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  void _shareResult() {
    SharePlus.instance.share(ShareParams(text: _result));
  }
}

enum _SummaryAction {
  summarize,
  explain,
  keyPoints,
  translate,
  reply,
}
