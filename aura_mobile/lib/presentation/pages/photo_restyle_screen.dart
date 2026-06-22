import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/data/datasources/image_generation_service.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

/// Photo Restyle — turn a real photo into AI art in a chosen style.
///
/// Fully free, no key, no upload: the on-device vision model (e.g. Gemma 4)
/// describes the picked photo, then that description + the chosen art style is
/// sent to Pollinations to generate a fresh styled image. When no vision model
/// is loaded, the user can type a description manually.
class PhotoRestyleScreen extends ConsumerStatefulWidget {
  const PhotoRestyleScreen({super.key});

  @override
  ConsumerState<PhotoRestyleScreen> createState() => _PhotoRestyleScreenState();
}

class _ArtStyle {
  final String label;
  final String promptSuffix;
  const _ArtStyle(this.label, this.promptSuffix);
}

const List<_ArtStyle> _styles = [
  _ArtStyle('Anime', 'anime style, vibrant, studio ghibli inspired, detailed'),
  _ArtStyle('Cyberpunk', 'cyberpunk style, neon lights, futuristic, cinematic'),
  _ArtStyle('Oil Painting', 'classical oil painting, textured brush strokes, fine art'),
  _ArtStyle('3D / Pixar', '3D render, Pixar style, soft lighting, cute, high detail'),
  _ArtStyle('Watercolor', 'watercolor painting, soft pastel colors, artistic'),
  _ArtStyle('Cartoon', 'cartoon style, bold outlines, flat colors, playful'),
  _ArtStyle('Pixel Art', '16-bit pixel art, retro game style'),
  _ArtStyle('Sketch', 'detailed pencil sketch, black and white, hand-drawn'),
];

class _PhotoRestyleScreenState extends ConsumerState<PhotoRestyleScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _descController = TextEditingController();

  File? _sourceFile;
  int _styleIndex = 0;
  String? _resultUrl;
  bool _isDescribing = false;
  bool _isSharing = false;

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? img = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (img == null) return;
      setState(() {
        _sourceFile = File(img.path);
        _resultUrl = null;
        _descController.clear();
      });
      // Auto-describe with the vision model if one is loaded.
      final llm = ref.read(llmServiceProvider);
      if (llm.supportsVision) {
        await _describePhoto();
      } else {
        _snack('No vision model loaded — type what\'s in the photo, then Restyle.');
      }
    } catch (e) {
      _snack('Could not pick the image. Try again.');
    }
  }

  Future<void> _describePhoto() async {
    final file = _sourceFile;
    if (file == null) return;
    final llm = ref.read(llmServiceProvider);
    if (!llm.supportsVision) {
      _snack('Load a vision model (e.g. Gemma 4) to auto-describe photos.');
      return;
    }
    setState(() => _isDescribing = true);
    try {
      final bytes = await file.readAsBytes();
      final buffer = StringBuffer();
      await for (final chunk in llm.chat(
        'Describe this image in one vivid, detailed sentence for an artist to recreate it. '
        'Focus on the main subject, setting, colors, and mood. Reply with only the description.',
        imageBytes: bytes,
        temperature: 0.4,
        maxTokens: 200,
      )) {
        buffer.write(chunk);
      }
      final desc = buffer.toString().trim();
      if (mounted && desc.isNotEmpty) {
        setState(() => _descController.text = desc);
      } else if (mounted) {
        _snack('Could not describe the photo. Type a description instead.');
      }
    } catch (e) {
      _snack('Vision failed. Type a description instead.');
    } finally {
      if (mounted) setState(() => _isDescribing = false);
    }
  }

  void _restyle() {
    final desc = _descController.text.trim();
    if (desc.isEmpty) {
      _snack('Describe the photo (or let the vision model do it) first.');
      return;
    }
    FocusScope.of(context).unfocus();
    final svc = ref.read(imageGenerationServiceProvider);
    final style = _styles[_styleIndex];
    setState(() {
      _resultUrl = svc.buildImageUrl(
        '$desc, ${style.promptSuffix}',
        width: 1024,
        height: 1024,
        model: ImageModel.flux,
      );
    });
  }

  Future<void> _shareResult() async {
    final url = _resultUrl;
    if (url == null || _isSharing) return;
    setState(() => _isSharing = true);
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/aura_restyle_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Dio().download(url, path);
      await Share.shareXFiles([XFile(path)], text: 'Restyled with AURA');
    } catch (e) {
      _snack('Could not share. Wait for the image to load and retry.');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
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
        title: Text('Photo Restyle',
            style: GoogleFonts.outfit(
                color: ClayColors.goldAccent, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // ── Source + result side by side ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _sourceCard()),
              const SizedBox(width: 16),
              Expanded(child: _resultCard()),
            ],
          ),
          const SizedBox(height: 28),

          // ── Description (auto from vision, editable) ──
          Row(
            children: [
              Expanded(
                child: Text('What\'s in the photo',
                    style: GoogleFonts.outfit(
                        color: ClayColors.textDark, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              if (_sourceFile != null)
                TextButton.icon(
                  onPressed: _isDescribing ? null : _describePhoto,
                  icon: _isDescribing
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: ClayColors.goldAccent))
                      : const Icon(Icons.visibility, color: ClayColors.goldAccent, size: 18),
                  label: Text(_isDescribing ? 'Looking...' : 'AI describe',
                      style: GoogleFonts.outfit(color: ClayColors.goldAccent, fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClayContainer(
            borderRadius: 16,
            isInset: true,
            depth: 4.0,
            baseColor: const Color(0xFFE5E2DA),
            highlightColor: const Color(0xFFF7F4EF),
            shadowColor: const Color(0xFFCBC7BE),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _descController,
              maxLines: 3,
              minLines: 1,
              style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'A description of the photo (auto-filled by the vision model)',
                hintStyle: GoogleFonts.outfit(color: ClayColors.textHint.withOpacity(0.65), fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // ── Style ──
          Text('Art style',
              style: GoogleFonts.outfit(
                  color: ClayColors.textDark, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _styles.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : 8,
                    right: index == _styles.length - 1 ? 0 : 0,
                  ),
                  child: _styleChip(_styles[index].label, index == _styleIndex,
                      () => setState(() => _styleIndex = index)),
                );
              },
            ),
          ),
          const SizedBox(height: 36),

          // ── Restyle ──
          SizedBox(
            width: double.infinity,
            child: ClayButton(
              onTap: _restyle,
              borderRadius: 14,
              depth: 5.0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              baseColor: ClayColors.goldAccent,
              highlightColor: ClayColors.goldHighlight,
              shadowColor: ClayColors.goldShadow,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_fix_high, size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Restyle',
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

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: ClayColors.obsidianBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pull bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ClayColors.textHint.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Choose Image Source',
                style: GoogleFonts.outfit(
                  color: ClayColors.textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ClayButton(
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.camera);
                      },
                      borderRadius: 16,
                      depth: 5.0,
                      baseColor: ClayColors.warmGrey,
                      highlightColor: ClayColors.highlight,
                      shadowColor: ClayColors.shadow,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_camera, color: ClayColors.goldAccent, size: 28),
                          const SizedBox(height: 8),
                          Text(
                            'Camera',
                            style: GoogleFonts.outfit(
                              color: ClayColors.textDark,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ClayButton(
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.gallery);
                      },
                      borderRadius: 16,
                      depth: 5.0,
                      baseColor: ClayColors.warmGrey,
                      highlightColor: ClayColors.highlight,
                      shadowColor: ClayColors.shadow,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_library, color: ClayColors.goldAccent, size: 28),
                          const SizedBox(height: 8),
                          Text(
                            'Gallery',
                            style: GoogleFonts.outfit(
                              color: ClayColors.textDark,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sourceCard() {
    return GestureDetector(
      onTap: _showImageSourceSheet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Original',
              style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 1,
            child: ClayContainer(
              borderRadius: 22,
              depth: 4.0,
              baseColor: ClayColors.warmGrey,
              highlightColor: ClayColors.highlight,
              shadowColor: ClayColors.shadow,
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: _sourceFile == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_photo_alternate_outlined, color: ClayColors.goldAccent, size: 36),
                            const SizedBox(height: 8),
                            Text(
                              'Add Photo',
                              style: GoogleFonts.outfit(
                                color: ClayColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(_sourceFile!, fit: BoxFit.cover),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit, color: Colors.white, size: 14),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Restyled',
                  style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            if (_resultUrl != null)
              GestureDetector(
                onTap: _shareResult,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Icon(_isSharing ? Icons.hourglass_top : Icons.ios_share,
                      color: ClayColors.goldAccent, size: 16),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: ClayContainer(
            borderRadius: 22,
            depth: 4.0,
            baseColor: ClayColors.warmGrey,
            highlightColor: ClayColors.highlight,
            shadowColor: ClayColors.shadow,
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: _resultUrl == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.auto_fix_high, color: ClayColors.textHint, size: 36),
                          const SizedBox(height: 8),
                          Text(
                            'Ready',
                            style: GoogleFonts.outfit(
                              color: ClayColors.textHint,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Image.network(
                      _resultUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (c, child, p) => p == null
                          ? child
                          : const Center(
                              child: CircularProgressIndicator(
                                  color: ClayColors.goldAccent, strokeWidth: 2.5)),
                      errorBuilder: (c, e, s) => const Center(
                          child: Icon(Icons.broken_image, color: ClayColors.textHint, size: 36)),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _styleChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? ClayColors.goldHighlight
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? ClayColors.goldAccent : Colors.black.withOpacity(0.08),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: ClayColors.goldAccent.withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Text(label,
            style: GoogleFonts.outfit(
                color: selected ? ClayColors.goldAccent : ClayColors.textMuted,
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600)),
      ),
    );
  }
}
