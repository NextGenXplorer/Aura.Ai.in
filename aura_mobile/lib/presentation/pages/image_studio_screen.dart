import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/data/datasources/image_generation_service.dart';
import 'package:aura_mobile/presentation/pages/meme_maker_screen.dart';
import 'package:aura_mobile/presentation/pages/photo_restyle_screen.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

/// AI Image Studio — a dedicated, fully free (no API key) text-to-image page
/// powered by Pollinations.ai. Exposes the most useful free features: model
/// choice (FLUX / Turbo / Sana), aspect ratio, prompt enhancement, and a
/// reproducible seed, plus save/share of the generated image.
class ImageStudioScreen extends ConsumerStatefulWidget {
  const ImageStudioScreen({super.key});

  @override
  ConsumerState<ImageStudioScreen> createState() => _ImageStudioScreenState();
}

/// Aspect ratio presets with their pixel dimensions.
enum _Ratio { square, portrait, landscape, wide }

extension _RatioInfo on _Ratio {
  String get label => switch (this) {
        _Ratio.square => '1:1',
        _Ratio.portrait => '3:4',
        _Ratio.landscape => '4:3',
        _Ratio.wide => '16:9',
      };
  IconData get icon => switch (this) {
        _Ratio.square => Icons.crop_square,
        _Ratio.portrait => Icons.crop_portrait,
        _Ratio.landscape => Icons.crop_landscape,
        _Ratio.wide => Icons.crop_16_9,
      };
  ({int w, int h}) get size => switch (this) {
        _Ratio.square => (w: 1024, h: 1024),
        _Ratio.portrait => (w: 896, h: 1152),
        _Ratio.landscape => (w: 1152, h: 896),
        _Ratio.wide => (w: 1280, h: 720),
      };
}

class _ImageStudioScreenState extends ConsumerState<ImageStudioScreen> {
  final TextEditingController _promptController = TextEditingController();
  ImageModel _model = ImageModel.flux;
  _Ratio _ratio = _Ratio.square;
  bool _enhance = true;
  int _seed = Random().nextInt(1 << 31);

  String? _currentUrl;
  bool _isSaving = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _generate() {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _snack('Enter a prompt to generate an image');
      return;
    }
    FocusScope.of(context).unfocus();
    final svc = ref.read(imageGenerationServiceProvider);
    final size = _ratio.size;
    setState(() {
      _currentUrl = svc.buildImageUrl(
        prompt,
        width: size.w,
        height: size.h,
        model: _model,
        seed: _seed,
        enhance: _enhance,
      );
    });
  }

  void _shuffleSeedAndGenerate() {
    setState(() => _seed = Random().nextInt(1 << 31));
    _generate();
  }

  Future<void> _shareImage() async {
    final url = _currentUrl;
    if (url == null || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/aura_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Dio().download(url, path);
      final file = File(path);
      if (!await file.exists() || await file.length() < 1024) {
        throw Exception('Image not ready');
      }
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Created with AURA AI Image Studio',
      );
    } catch (e) {
      _snack('Could not share the image. Try again once it has loaded.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
        title: Text(
          'AI Image Studio',
          style: GoogleFonts.outfit(
            color: ClayColors.goldAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Photo Restyle',
            icon: const Icon(Icons.auto_fix_high, color: ClayColors.goldAccent),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PhotoRestyleScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Meme Maker',
            icon: const Icon(Icons.mood, color: ClayColors.goldAccent),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MemeMakerScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Image preview ──
          _previewArea(),
          const SizedBox(height: 20),

          // ── Prompt ──
          _label('Prompt'),
          const SizedBox(height: 8),
          ClayContainer(
            borderRadius: 14,
            isInset: true,
            depth: 4.0,
            baseColor: const Color(0xFFE5E2DA),
            highlightColor: const Color(0xFFF7F4EF),
            shadowColor: const Color(0xFFCBC7BE),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _promptController,
              maxLines: 3,
              minLines: 1,
              style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'A serene mountain lake at sunrise, cinematic, ultra-detailed',
                hintStyle: GoogleFonts.outfit(color: ClayColors.textHint.withOpacity(0.7), fontSize: 14),
              ),
              onSubmitted: (_) => _generate(),
            ),
          ),
          const SizedBox(height: 18),

          // ── Model ──
          _label('Model'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _choiceChip('FLUX', 'Best quality', _model == ImageModel.flux,
                  () => setState(() => _model = ImageModel.flux)),
              _choiceChip('Turbo', 'Fastest', _model == ImageModel.turbo,
                  () => setState(() => _model = ImageModel.turbo)),
              _choiceChip('Sana', 'Lightweight', _model == ImageModel.sana,
                  () => setState(() => _model = ImageModel.sana)),
            ],
          ),
          const SizedBox(height: 18),

          // ── Aspect ratio ──
          _label('Aspect ratio'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final r in _Ratio.values) ...[
                _ratioChip(r),
                if (r != _Ratio.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 18),

          // ── Options ──
          _toggleRow(
            'Enhance prompt',
            'Let the model expand your prompt for richer detail',
            _enhance,
            (v) => setState(() => _enhance = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Seed: $_seed',
                  style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 13),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _seed = Random().nextInt(1 << 31)),
                icon: const Icon(Icons.casino_outlined, color: ClayColors.goldAccent, size: 18),
                label: Text('Random',
                    style: GoogleFonts.outfit(color: ClayColors.goldAccent, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Generate ──
          SizedBox(
            width: double.infinity,
            child: ClayButton(
              onTap: _generate,
              borderRadius: 14,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Generate',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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

  Widget _previewArea() {
    return AspectRatio(
      aspectRatio: _ratio.size.w / _ratio.size.h,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ClayColors.shadow.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: _currentUrl == null
            ? _emptyPreview()
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    _currentUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return _loadingPreview();
                    },
                    errorBuilder: (context, error, stack) => _errorPreview(),
                  ),
                  // Action overlay
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Row(
                      children: [
                        _overlayBtn(Icons.refresh, 'New variation', _shuffleSeedAndGenerate),
                        const SizedBox(width: 8),
                        _overlayBtn(
                          _isSaving ? Icons.hourglass_top : Icons.ios_share,
                          'Share',
                          _shareImage,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _emptyPreview() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.image_outlined, color: ClayColors.textHint, size: 56),
          const SizedBox(height: 12),
          Text('Your generated image appears here',
              style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _loadingPreview() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: ClayColors.goldAccent, strokeWidth: 3),
          const SizedBox(height: 16),
          Text('Generating...',
              style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _errorPreview() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.orangeAccent, size: 40),
            const SizedBox(height: 12),
            Text('Could not generate. Check your connection and try again.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 13)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _generate,
              child: Text('Retry',
                  style: GoogleFonts.outfit(color: ClayColors.goldAccent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overlayBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: GoogleFonts.outfit(
            color: ClayColors.textDark, fontSize: 14, fontWeight: FontWeight.bold),
      );

  Widget _choiceChip(String title, String subtitle, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? ClayColors.goldHighlight
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? ClayColors.goldAccent : ClayColors.shadow.withOpacity(0.5),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.outfit(
                    color: selected ? ClayColors.goldAccent : ClayColors.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            Text(subtitle,
                style: GoogleFonts.outfit(
                    color: selected ? ClayColors.goldAccent.withOpacity(0.7) : ClayColors.textMuted,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _ratioChip(_Ratio r) {
    final selected = _ratio == r;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _ratio = r),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? ClayColors.goldHighlight
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? ClayColors.goldAccent : ClayColors.shadow.withOpacity(0.5),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(r.icon,
                  color: selected ? ClayColors.goldAccent : ClayColors.textMuted, size: 20),
              const SizedBox(height: 4),
              Text(r.label,
                  style: GoogleFonts.outfit(
                      color: selected ? ClayColors.goldAccent : ClayColors.textMuted,
                      fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return ClayContainer(
      borderRadius: 12,
      depth: 2.0,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.outfit(
                        color: ClayColors.textDark, fontSize: 14, fontWeight: FontWeight.w500)),
                Text(subtitle,
                    style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: ClayColors.goldAccent,
          ),
        ],
      ),
    );
  }
}
