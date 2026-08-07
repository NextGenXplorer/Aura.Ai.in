import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/features/document_gen/document_generation_service.dart';

/// AI Writing Workspace — Draft → Edit → Refine → Export workflow.
/// Like Notion AI but fully offline using on-device LLM.
class WritingWorkspaceScreen extends ConsumerStatefulWidget {
  const WritingWorkspaceScreen({super.key});

  @override
  ConsumerState<WritingWorkspaceScreen> createState() => _WritingWorkspaceScreenState();
}

class _WritingWorkspaceScreenState extends ConsumerState<WritingWorkspaceScreen> {
  final _textController = TextEditingController();
  final _topicController = TextEditingController();
  bool _isGenerating = false;
  _WritingPhase _phase = _WritingPhase.topic;
  String _selectedTone = 'Professional';
  String _selectedFormat = 'Essay';

  final List<String> _tones = [
    'Professional', 'Casual', 'Academic', 'Creative', 'Persuasive', 'Friendly'
  ];
  final List<String> _formats = [
    'Essay', 'Email', 'Blog Post', 'Letter', 'Report', 'Story', 'Script', 'Notes'
  ];

  @override
  void dispose() {
    _textController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4EF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF191816)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'AI Writing Studio',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: const Color(0xFF191816),
          ),
        ),
        actions: [
          if (_phase == _WritingPhase.editing)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Color(0xFF191816)),
              onSelected: _handleMenuAction,
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'copy', child: Text('Copy All')),
                const PopupMenuItem(value: 'share', child: Text('Share')),
                const PopupMenuItem(value: 'export_pdf', child: Text('Export as PDF')),
                const PopupMenuItem(value: 'clear', child: Text('Start Over')),
              ],
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _phase == _WritingPhase.topic
            ? _buildTopicPhase()
            : _buildEditingPhase(),
      ),
    );
  }

  Widget _buildTopicPhase() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            '✍️ What would you like to write?',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          // Topic input
          TextField(
            controller: _topicController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'e.g., "A cover letter for a software engineer position" or "Explain quantum computing simply"',
              hintStyle: GoogleFonts.outfit(color: Colors.grey[400], fontSize: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFB3862B), width: 2),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            style: GoogleFonts.outfit(fontSize: 14),
          ),
          const SizedBox(height: 20),

          // Tone selector
          Text(
            'Tone',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tones.map((tone) => ChoiceChip(
              label: Text(tone, style: const TextStyle(fontSize: 12)),
              selected: _selectedTone == tone,
              selectedColor: const Color(0xFFB3862B).withOpacity(0.2),
              onSelected: (_) => setState(() => _selectedTone = tone),
            )).toList(),
          ),
          const SizedBox(height: 20),

          // Format selector
          Text(
            'Format',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _formats.map((format) => ChoiceChip(
              label: Text(format, style: const TextStyle(fontSize: 12)),
              selected: _selectedFormat == format,
              selectedColor: const Color(0xFFB3862B).withOpacity(0.2),
              onSelected: (_) => setState(() => _selectedFormat = format),
            )).toList(),
          ),
          const SizedBox(height: 24),

          // Generate button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _topicController.text.trim().isEmpty || _isGenerating
                  ? null
                  : _generateDraft,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _isGenerating ? 'Generating...' : 'Generate Draft',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB3862B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
          // Quick templates
          Text(
            'Quick Templates',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ..._quickTemplates.map((t) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Text(t['icon']!, style: const TextStyle(fontSize: 20)),
            title: Text(t['title']!, style: GoogleFonts.outfit(fontSize: 13)),
            onTap: () {
              _topicController.text = t['prompt']!;
              setState(() {});
            },
          )),
        ],
      ),
    );
  }

  Widget _buildEditingPhase() {
    return Column(
      children: [
        // AI assist toolbar
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFEFECE6),
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _toolbarButton('Improve', Icons.auto_fix_high, _improveText),
              _toolbarButton('Shorten', Icons.compress, _shortenText),
              _toolbarButton('Expand', Icons.expand, _expandText),
              _toolbarButton('Fix Grammar', Icons.spellcheck, _fixGrammar),
              _toolbarButton('Make Formal', Icons.business_center, _makeFormal),
              _toolbarButton('Make Casual', Icons.emoji_emotions, _makeCasual),
            ],
          ),
        ),

        // Text editor
        Expanded(
          child: Stack(
            children: [
              TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(16),
                  border: InputBorder.none,
                  hintText: 'Your text will appear here...',
                  hintStyle: GoogleFonts.outfit(color: Colors.grey[400]),
                ),
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  height: 1.6,
                  color: const Color(0xFF191816),
                ),
              ),
              if (_isGenerating)
                Container(
                  color: Colors.white.withOpacity(0.7),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFFB3862B)),
                        SizedBox(height: 12),
                        Text('AI is writing...'),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Word count bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFFEFECE6),
          child: Row(
            children: [
              Text(
                '${_textController.text.split(RegExp(r'\\s+')).where((w) => w.isNotEmpty).length} words',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[600]),
              ),
              const Spacer(),
              Text(
                'Tone: $_selectedTone • Format: $_selectedFormat',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolbarButton(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: ActionChip(
        avatar: Icon(icon, size: 14, color: const Color(0xFFB3862B)),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        onPressed: _isGenerating ? null : onTap,
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  Future<void> _generateDraft() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) return;

    setState(() => _isGenerating = true);

    try {
      final llm = ref.read(llmServiceProvider);
      if (!llm.isModelLoaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No AI model loaded. Please load a model first.')),
        );
        return;
      }

      final prompt = 'Write a $_selectedFormat about the following topic. '
          'Use a $_selectedTone tone. Be thorough and well-structured.\n\n'
          'Topic: $topic';

      final buffer = StringBuffer();
      await for (final chunk in llm.chat(prompt, maxTokens: 1024, temperature: 0.7)) {
        buffer.write(chunk);
        _textController.text = buffer.toString();
      }

      setState(() => _phase = _WritingPhase.editing);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _refineText(String instruction) async {
    final currentText = _textController.text.trim();
    if (currentText.isEmpty) return;

    setState(() => _isGenerating = true);

    try {
      final llm = ref.read(llmServiceProvider);
      final prompt = '$instruction:\n\n$currentText';

      final buffer = StringBuffer();
      await for (final chunk in llm.chat(prompt, maxTokens: 1024, temperature: 0.4)) {
        buffer.write(chunk);
        _textController.text = buffer.toString();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  void _improveText() => _refineText('Improve the following text. Make it clearer, more engaging, and better structured. Keep the same meaning');
  void _shortenText() => _refineText('Make the following text much shorter and more concise while keeping the key points');
  void _expandText() => _refineText('Expand the following text with more detail, examples, and explanations');
  void _fixGrammar() => _refineText('Fix all grammar, spelling, and punctuation errors in the following text. Return only the corrected text');
  void _makeFormal() => _refineText('Rewrite the following text in a formal, professional tone');
  void _makeCasual() => _refineText('Rewrite the following text in a casual, friendly, conversational tone');

  void _handleMenuAction(String action) {
    switch (action) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: _textController.text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied to clipboard')),
        );
        break;
      case 'share':
        SharePlus.instance.share(ShareParams(text: _textController.text));
        break;
      case 'export_pdf':
        _exportAsPdf();
        break;
      case 'clear':
        setState(() {
          _textController.clear();
          _topicController.clear();
          _phase = _WritingPhase.topic;
        });
        break;
    }
  }

  Future<void> _exportAsPdf() async {
    try {
      final llm = ref.read(llmServiceProvider);
      final docGen = DocumentGenerationService(llm);
      // Use the current text content directly
      final content = _textController.text;
      if (content.isEmpty) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exporting as PDF...')),
      );

      await for (final msg in docGen.generateAndExportPdf(
        topic: _topicController.text.isNotEmpty ? _topicController.text : 'Writing',
        style: 'document',
        preGeneratedContent: content,
      )) {
        // Show progress
        if (msg.contains('✅')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  static const List<Map<String, String>> _quickTemplates = [
    {'icon': '📧', 'title': 'Professional Email', 'prompt': 'A professional email requesting a meeting'},
    {'icon': '📝', 'title': 'Blog Post', 'prompt': 'A blog post about productivity tips for students'},
    {'icon': '💼', 'title': 'Cover Letter', 'prompt': 'A cover letter for a tech job application'},
    {'icon': '📋', 'title': 'Project Proposal', 'prompt': 'A project proposal for a mobile app idea'},
    {'icon': '🎓', 'title': 'Essay', 'prompt': 'An essay about the impact of AI on education'},
    {'icon': '📖', 'title': 'Short Story', 'prompt': 'A creative short story about a time traveler'},
  ];
}

enum _WritingPhase {
  topic,
  editing,
}
