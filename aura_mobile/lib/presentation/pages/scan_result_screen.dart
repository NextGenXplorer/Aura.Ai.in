import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/core/services/ocr_service.dart';
import 'package:aura_mobile/presentation/providers/study_provider.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/pages/deck_view_screen.dart';

class ScanResultScreen extends ConsumerStatefulWidget {
  final OcrResult ocrResult;
  final ScanCategory category;
  final String imagePath;

  const ScanResultScreen({
    super.key,
    required this.ocrResult,
    required this.category,
    required this.imagePath,
  });

  @override
  ConsumerState<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends ConsumerState<ScanResultScreen> {
  late TextEditingController _textController;
  bool _isActionRunning = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.ocrResult.fullText);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0c),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0c),
        title: Text('Scan Result', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white54),
            tooltip: 'Copy text',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _textController.text));
              _showSnack('Text copied to clipboard');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Image Preview (safe) ──
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildImagePreview(),
          ),
          const SizedBox(height: 16),

          // ── Category Badge ──
          Row(
            children: [
              _categoryBadge(),
              const Spacer(),
              Text(
                '${widget.ocrResult.blockCount} blocks, ${widget.ocrResult.lineCount} lines',
                style: GoogleFonts.outfit(color: Colors.white30, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Smart Actions ──
          Text('Quick Actions', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _actionGrid(),
          const SizedBox(height: 20),

          // ── Extracted Text (Editable) ──
          Row(
            children: [
              Text('Extracted Text', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('Tap to edit', style: GoogleFonts.outfit(color: Colors.white30, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: TextField(
              controller: _textController,
              maxLines: null,
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14, height: 1.6),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  /// Safe image preview with error handling for missing/corrupt files
  Widget _buildImagePreview() {
    final file = File(widget.imagePath);

    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return Image.file(
            file,
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _imagePlaceholder(),
          );
        }
        return _imagePlaceholder();
      },
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.image_not_supported, color: Colors.white24, size: 40),
          const SizedBox(height: 8),
          Text('Image preview unavailable',
              style: GoogleFonts.outfit(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _categoryBadge() {
    final (String label, IconData icon, Color color) = switch (widget.category) {
      ScanCategory.handwrittenNotes => ('Handwritten Notes', Icons.edit_note, Colors.orangeAccent),
      ScanCategory.code => ('Code / Error', Icons.code, Colors.cyanAccent),
      ScanCategory.math => ('Math / Equation', Icons.calculate, Colors.purpleAccent),
      ScanCategory.printedText => ('Printed Text', Icons.article, Colors.blueAccent),
      ScanCategory.empty => ('No Text Found', Icons.warning, Colors.redAccent),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.outfit(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _actionGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _actionCard(
              icon: Icons.style_rounded,
              title: 'Create Flashcards',
              subtitle: 'Auto-generate study cards',
              color: const Color(0xFFc69c3a),
              onTap: _createFlashcards,
            )),
            const SizedBox(width: 8),
            Expanded(child: _actionCard(
              icon: Icons.chat_bubble_outline,
              title: 'Ask AURA',
              subtitle: 'Send to chat for analysis',
              color: Colors.blueAccent,
              onTap: _sendToChat,
            )),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _actionCard(
              icon: Icons.summarize,
              title: 'Summarize',
              subtitle: 'Get AI summary',
              color: Colors.greenAccent,
              onTap: _summarizeText,
            )),
            const SizedBox(width: 8),
            Expanded(child: _actionCard(
              icon: widget.category == ScanCategory.code ? Icons.bug_report : Icons.share,
              title: widget.category == ScanCategory.code ? 'Debug This' : 'Share Text',
              subtitle: widget.category == ScanCategory.code ? 'Explain error' : 'Share extracted text',
              color: widget.category == ScanCategory.code ? Colors.redAccent : Colors.purpleAccent,
              onTap: widget.category == ScanCategory.code ? _debugCode : _shareText,
            )),
          ],
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isActionRunning ? null : onTap,
      child: Opacity(
        opacity: _isActionRunning ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(title, style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: GoogleFonts.outfit(color: Colors.white30, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _createFlashcards() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnack('No text to create flashcards from');
      return;
    }

    if (_isActionRunning) return;
    setState(() => _isActionRunning = true);

    try {
      _showSnack('Creating flashcards...');

      final deck = await ref.read(studyProvider.notifier).createDeckFromText(
        text,
        name: 'Scanned Notes ${DateTime.now().day}/${DateTime.now().month}',
      );

      if (!mounted) return;

      if (deck != null) {
        _showSnack('Flashcards created! Opening deck...');
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => DeckViewScreen(deck: deck)),
        );
      } else {
        _showSnack('Failed to create flashcards. Try editing the text first.');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not create flashcards. Please try again.');
      debugPrint('Flashcard creation error: $e');
    } finally {
      if (mounted) setState(() => _isActionRunning = false);
    }
  }

  void _sendToChat() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnack('No text to send');
      return;
    }

    try {
      ref.read(chatProvider.notifier).sendMessage(
        'I scanned this text from an image. Please help me understand it:\n\n$text',
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      _showSnack('Could not send to chat. Please try again.');
      debugPrint('Send to chat error: $e');
    }
  }

  void _summarizeText() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnack('No text to summarize');
      return;
    }

    try {
      ref.read(chatProvider.notifier).sendMessage(
        'Summarize the following text in bullet points:\n\n$text',
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      _showSnack('Could not summarize. Please try again.');
      debugPrint('Summarize error: $e');
    }
  }

  void _debugCode() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnack('No code/error text to debug');
      return;
    }

    try {
      ref.read(chatProvider.notifier).sendMessage(
        'I captured this error/code from a screenshot. What does it mean and how do I fix it?\n\n$text',
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      _showSnack('Could not send to chat. Please try again.');
      debugPrint('Debug code error: $e');
    }
  }

  void _shareText() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnack('No text to share');
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('Text copied to clipboard! You can paste it anywhere.');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}
