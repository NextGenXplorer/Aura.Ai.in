import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:read_pdf_text/read_pdf_text.dart';
import 'package:aura_mobile/core/services/ocr_service.dart';
import 'package:aura_mobile/presentation/pages/scan_result_screen.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

class CameraScanScreen extends ConsumerStatefulWidget {
  const CameraScanScreen({super.key});

  @override
  ConsumerState<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends ConsumerState<CameraScanScreen> {
  final ImagePicker _picker = ImagePicker();
  final OcrService _ocrService = OcrService();
  bool _isProcessing = false;
  String _processingStatus = 'Analyzing image...';

  Future<void> _scanImage(ImageSource source) async {
    // 1. Handle camera permission before opening
    if (source == ImageSource.camera) {
      final status = await Permission.camera.status;
      if (status.isDenied) {
        final result = await Permission.camera.request();
        if (!result.isGranted) {
          if (!mounted) return;
          _showSnackBar('Camera permission is required to take photos.');
          return;
        }
      } else if (status.isPermanentlyDenied) {
        if (!mounted) return;
        _showPermissionDialog();
        return;
      }
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (image == null) return; // User cancelled
      if (!mounted) return;

      setState(() {
        _isProcessing = true;
        _processingStatus = 'Analyzing image...';
      });

      // 2. Validate the file exists and isn't too large
      final file = File(image.path);
      if (!await file.exists()) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        _showSnackBar('Image file not found. Please try again.');
        return;
      }

      final fileSize = await file.length();
      if (fileSize > 15 * 1024 * 1024) {
        // >15MB — too large for ML Kit on low-end devices
        if (!mounted) return;
        setState(() => _isProcessing = false);
        _showSnackBar('Image is too large. Please use a smaller image or lower quality.');
        return;
      }

      if (!mounted) return;
      setState(() => _processingStatus = 'Extracting text with OCR...');

      final result = await _ocrService.extractText(file);

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (result.isEmpty) {
        _showSnackBar('No text detected in the image. Try a clearer photo.');
        return;
      }

      final category = _ocrService.categorize(result);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScanResultScreen(
            ocrResult: result,
            category: category,
            imagePath: image.path,
          ),
        ),
      );
    } on PlatformException catch (e) {
      // image_picker / permission errors
      if (!mounted) return;
      setState(() => _isProcessing = false);
      if (e.code == 'camera_access_denied') {
        _showSnackBar('Camera access denied. Please grant permission in Settings.');
      } else if (e.code == 'photo_access_denied') {
        _showSnackBar('Gallery access denied. Please grant permission in Settings.');
      } else {
        _showSnackBar('Could not access the image. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnackBar('Failed to process image. Try a different photo.');
      debugPrint('Scanner error: $e');
    }
  }

  Future<void> _pickAndScanPdf() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.isEmpty) return;
      final String? filePath = result.files.single.path;
      if (filePath == null) return;

      setState(() {
        _isProcessing = true;
        _processingStatus = 'Extracting PDF text...';
      });

      final String extractedText = await ReadPdfText.getPDFtext(filePath);

      setState(() => _isProcessing = false);

      if (extractedText.trim().isEmpty) {
        _showSnackBar('No readable text found in the PDF.');
        return;
      }

      final ocrResult = OcrResult(
        fullText: extractedText,
        blocks: [],
        imageWidth: 0,
        imageHeight: 0,
      );

      final category = _ocrService.categorize(ocrResult);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScanResultScreen(
            ocrResult: ocrResult,
            category: category,
            imagePath: filePath,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnackBar('Failed to parse PDF file. Please try another file.');
      debugPrint('PDF scan error: $e');
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ClayColors.warmGrey,
        title: Text('Camera Permission Required',
            style: GoogleFonts.outfit(color: ClayColors.textDark, fontWeight: FontWeight.bold)),
        content: Text(
          'Camera permission was permanently denied. Please enable it in your device settings.',
          style: GoogleFonts.outfit(color: ClayColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: ClayColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: Text('Open Settings',
                style: GoogleFonts.outfit(color: ClayColors.goldAccent)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: ClayColors.obsidianBg,
        title: Text(
          'Scan & Capture',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: ClayColors.goldAccent,
          ),
        ),
        iconTheme: const IconThemeData(color: ClayColors.textDark),
      ),
      body: _isProcessing
          ? _processingView()
          : SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                  const Spacer(),

                  // Hero icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: ClayColors.goldAccent.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ClayColors.goldAccent.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.document_scanner_rounded,
                      color: ClayColors.goldAccent,
                      size: 56,
                    ),
                  ),
                  const SizedBox(height: 32),

                  Text(
                    'Smart Document Scanner',
                    style: GoogleFonts.outfit(
                      color: ClayColors.textDark,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Capture notes, textbooks, whiteboards, or screenshots.\nAURA will extract text and auto-create flashcards.',
                    style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 14, height: 1.5),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(),

                  // Scan options
                  _scanOption(
                    icon: Icons.camera_alt_rounded,
                    title: 'Take Photo',
                    subtitle: 'Capture notes, whiteboard, or textbook',
                    color: const Color(0xFFc69c3a),
                    onTap: () => _scanImage(ImageSource.camera),
                  ),
                  const SizedBox(height: 12),
                  _scanOption(
                    icon: Icons.photo_library_rounded,
                    title: 'Pick from Gallery',
                    subtitle: 'Select screenshot, saved photo, or document',
                    color: Colors.blueAccent,
                    onTap: () => _scanImage(ImageSource.gallery),
                  ),
                  const SizedBox(height: 12),
                  _scanOption(
                    icon: Icons.picture_as_pdf_rounded,
                    title: 'Import PDF Document',
                    subtitle: 'Extract text from textbooks or PDF files',
                    color: Colors.redAccent,
                    onTap: _pickAndScanPdf,
                  ),

                  const SizedBox(height: 40),

                  // What it can do
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E2DA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFCBC7BE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('What AURA can scan:', style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 12)),
                        const SizedBox(height: 8),
                        _capabilityRow(Icons.edit_note, 'Handwritten notes'),
                        _capabilityRow(Icons.menu_book, 'Printed textbooks & PDFs'),
                        _capabilityRow(Icons.code, 'Code & error screenshots'),
                        _capabilityRow(Icons.calculate, 'Math equations'),
                        _capabilityRow(Icons.dashboard, 'Whiteboards & slides'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _processingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              color: ClayColors.goldAccent,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _processingStatus,
            style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a moment...',
            style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _scanOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isProcessing ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.outfit(color: ClayColors.textDark, fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color.withValues(alpha: 0.5), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _capabilityRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, color: ClayColors.goldAccent, size: 16),
          const SizedBox(width: 8),
          Text(text, style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}
