import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/data/datasources/image_generation_service.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

/// AI Meme Maker — generate a background image from a prompt, let the free AI
/// write a funny two-line caption, overlay classic meme text, and share the
/// composed meme. Fully free via Pollinations (image + text), no API key.
class MemeMakerScreen extends ConsumerStatefulWidget {
  const MemeMakerScreen({super.key});

  @override
  ConsumerState<MemeMakerScreen> createState() => _MemeMakerScreenState();
}

class _MemeMakerScreenState extends ConsumerState<MemeMakerScreen> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _topController = TextEditingController();
  final TextEditingController _bottomController = TextEditingController();
  final GlobalKey _memeKey = GlobalKey();

  String? _imageUrl;
  int _seed = Random().nextInt(1 << 31);
  bool _isWritingCaption = false;
  bool _isSharing = false;

  @override
  void dispose() {
    _promptController.dispose();
    _topController.dispose();
    _bottomController.dispose();
    super.dispose();
  }

  void _generateBackground() {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _snack('Describe the meme background image first');
      return;
    }
    FocusScope.of(context).unfocus();
    final svc = ref.read(imageGenerationServiceProvider);
    setState(() {
      _seed = Random().nextInt(1 << 31);
      _imageUrl = svc.buildImageUrl(
        prompt,
        width: 1024,
        height: 1024,
        model: ImageModel.flux,
        seed: _seed,
      );
    });
  }

  Future<void> _suggestCaption() async {
    final topic = _promptController.text.trim().isNotEmpty
        ? _promptController.text.trim()
        : (_topController.text.trim().isNotEmpty
            ? _topController.text.trim()
            : '');
    if (topic.isEmpty) {
      _snack('Type a topic or background prompt to get caption ideas');
      return;
    }
    setState(() => _isWritingCaption = true);
    try {
      final svc = ref.read(imageGenerationServiceProvider);
      final caption = await svc.generateMemeCaption(topic);
      if (!mounted) return;
      if (caption.top.isEmpty && caption.bottom.isEmpty) {
        _snack('Could not get a caption. Check your connection and retry.');
      } else {
        setState(() {
          _topController.text = caption.top;
          _bottomController.text = caption.bottom;
        });
      }
    } finally {
      if (mounted) setState(() => _isWritingCaption = false);
    }
  }

  Future<void> _shareMeme() async {
    if (_isSharing) return;
    if (_imageUrl == null) {
      _snack('Generate a background image first');
      return;
    }
    setState(() => _isSharing = true);
    try {
      // Capture the composed meme (image + text) to a PNG.
      final boundary = _memeKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Not ready');
      // Wait a frame if still painting.
      if (boundary.debugNeedsPaint) {
        await Future.delayed(const Duration(milliseconds: 120));
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Encode failed');
      final bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/aura_meme_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(bytes);

      await Share.shareXFiles([XFile(path)], text: 'Made with AURA Meme Maker');
    } catch (e) {
      _snack('Could not share the meme. Make sure the image has loaded.');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: ClayColors.obsidianBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: ClayColors.textDark),
        title: Text('AI Meme Maker',
            style: GoogleFonts.outfit(
                color: ClayColors.goldAccent, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // ── Meme preview (captured for sharing) ──
          RepaintBoundary(
            key: _memeKey,
            child: AspectRatio(
              aspectRatio: 1,
              child: ClayContainer(
                borderRadius: 24,
                depth: 5.0,
                baseColor: ClayColors.warmGrey,
                highlightColor: ClayColors.highlight,
                shadowColor: ClayColors.shadow,
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF232220),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_imageUrl == null)
                          _emptyPreview()
                        else
                          Image.network(
                            _imageUrl!,
                            fit: BoxFit.cover,
                            loadingBuilder: (c, child, p) =>
                                p == null ? child : _loadingPreview(),
                            errorBuilder: (c, e, s) => _errorPreview(),
                          ),
                        // Top text
                        Positioned(
                          top: 14,
                          left: 12,
                          right: 12,
                          child: _memeText(_topController.text),
                        ),
                        // Bottom text
                        Positioned(
                          bottom: 14,
                          left: 12,
                          right: 12,
                          child: _memeText(_bottomController.text),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_imageUrl != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _generateBackground,
                icon: const Icon(Icons.refresh, color: ClayColors.goldAccent, size: 18),
                label: Text('New background',
                    style: GoogleFonts.outfit(color: ClayColors.goldAccent, fontSize: 13)),
              ),
            ),
          const SizedBox(height: 18),

          // ── Background prompt ──
          _label('Background image'),
          const SizedBox(height: 10),
          _inputField(_promptController,
              'e.g. a grumpy cat sitting at an office desk', maxLines: 2),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ClayButton(
              onTap: _generateBackground,
              borderRadius: 14,
              depth: 5.0,
              baseColor: ClayColors.warmGrey,
              highlightColor: ClayColors.highlight,
              shadowColor: ClayColors.shadow,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.image_outlined, size: 18, color: ClayColors.goldAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Generate Background',
                    style: GoogleFonts.outfit(
                      color: ClayColors.textDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Caption ──
          Row(
            children: [
              Expanded(child: _label('Caption')),
              TextButton.icon(
                onPressed: _isWritingCaption ? null : _suggestCaption,
                icon: _isWritingCaption
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: ClayColors.goldAccent))
                    : const Icon(Icons.auto_awesome, color: ClayColors.goldAccent, size: 18),
                label: Text(_isWritingCaption ? 'Writing...' : 'AI caption',
                    style: GoogleFonts.outfit(color: ClayColors.goldAccent, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _inputField(_topController, 'TOP TEXT', onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          _inputField(_bottomController, 'BOTTOM TEXT', onChanged: (_) => setState(() {})),
          const SizedBox(height: 24),

          // ── Share ──
          SizedBox(
            width: double.infinity,
            child: ClayButton(
              onTap: _isSharing ? null : _shareMeme,
              borderRadius: 14,
              depth: 5.0,
              baseColor: ClayColors.goldAccent,
              highlightColor: ClayColors.goldHighlight,
              shadowColor: ClayColors.goldShadow,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_isSharing ? Icons.hourglass_top : Icons.share_rounded, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _isSharing ? 'Preparing...' : 'Share Meme',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Classic meme text: bold white with a heavy black outline.
  Widget _memeText(String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: GoogleFonts.oswald().fontFamily,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        height: 1.05,
        letterSpacing: 1.0,
        shadows: const [
          Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 2),
          Shadow(color: Colors.black, offset: Offset(-2, 2), blurRadius: 2),
          Shadow(color: Colors.black, offset: Offset(2, -2), blurRadius: 2),
          Shadow(color: Colors.black, offset: Offset(-2, -2), blurRadius: 2),
        ],
      ),
    );
  }

  Widget _emptyPreview() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_photo_alternate_outlined, color: Colors.white24, size: 52),
            const SizedBox(height: 10),
            Text('Generate a background to start',
                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13)),
          ],
        ),
      );

  Widget _loadingPreview() => const Center(
        child: CircularProgressIndicator(color: ClayColors.goldAccent, strokeWidth: 3),
      );

  Widget _errorPreview() => Center(
        child: Text('Could not load image',
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13)),
      );

  Widget _label(String text) => Text(
        text,
        style: GoogleFonts.outfit(
          color: ClayColors.textDark,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );

  Widget _inputField(TextEditingController c, String hint,
      {int maxLines = 1, ValueChanged<String>? onChanged}) {
    return ClayContainer(
      borderRadius: 14,
      isInset: true,
      depth: 4.0,
      baseColor: const Color(0xFFE5E2DA),
      highlightColor: const Color(0xFFF7F4EF),
      shadowColor: const Color(0xFFCBC7BE),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        onChanged: onChanged,
        style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: GoogleFonts.outfit(color: ClayColors.textHint.withOpacity(0.65), fontSize: 13),
        ),
      ),
    );
  }
}
