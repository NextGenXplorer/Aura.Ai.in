import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/pages/camera_scan_screen.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/domain/services/document_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

/// Extracted chat input bar — isolates text field rebuilds from the message list.
class ChatInputBar extends ConsumerStatefulWidget {
  final ValueChanged<String> onSend;
  final ValueChanged<bool> onCommandMenuChanged;

  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.onCommandMenuChanged,
  });

  @override
  ConsumerState<ChatInputBar> createState() => ChatInputBarState();
}

class ChatInputBarState extends ConsumerState<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  // A stable focus node so the keyboard target survives this widget's rebuilds
  // (isModelLoading / isListening / isThinking watches, voice listeners). Without
  // it the first tap can be dropped, forcing repeated taps to open the keyboard.
  final FocusNode _focusNode = FocusNode();
  bool _isWebSearchMode = false;

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      final messageToSend = _isWebSearchMode ? '[SEARCH] $text' : text;
      widget.onSend(messageToSend);
      _controller.clear();
      if (_isWebSearchMode) {
        setState(() => _isWebSearchMode = false);
      }
      // Dismiss the keyboard after sending.
      _focusNode.unfocus();
      widget.onCommandMenuChanged(false);
    }
  }

  void setWebSearchMode(bool value) {
    setState(() => _isWebSearchMode = value);
  }

  /// Shows the attachment menu — adapts based on whether a vision model is loaded.
  void _showAttachmentMenu(BuildContext context) {
    final llmService = ref.read(llmServiceProvider);
    final supportsVision = llmService.supportsVision;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF7F4EF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // If vision model is loaded, show image options prominently
            if (supportsVision) ...[
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: Color(0xFFB3862B),
                ),
                title: Text(
                  'Take Photo & Ask',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Take a photo and ask AI about it',
                  style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImageAndAsk(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: Color(0xFFB3862B),
                ),
                title: Text(
                  'Choose from Gallery',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Pick an image and ask AI about it',
                  style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImageAndAsk(ImageSource.gallery);
                },
              ),
              const Divider(),
            ],

            // Always show OCR/scan option
            ListTile(
              leading: Icon(
                Icons.document_scanner_rounded,
                color: supportsVision ? Colors.grey : const Color(0xFFB3862B),
              ),
              title: Text(
                'Scan Text (OCR)',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Extract text from images',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey),
              ),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CameraScanScreen()),
                );
              },
            ),

            // PDF/Document upload option
            ListTile(
              leading: const Icon(
                Icons.picture_as_pdf_rounded,
                color: Color(0xFFE53935),
              ),
              title: Text(
                'Upload PDF / Document',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Upload a PDF to ask questions about it',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndProcessDocument();
              },
            ),

            // If no vision model, show a hint
            if (!supportsVision)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB3862B).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFFB3862B),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Download Gemma 4 E2B to unlock "Ask about image" — the AI will understand photos!',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: const Color(0xFFB3862B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Pick an image from camera or gallery, then send it to the vision model
  /// with the user's question directly in the chat.
  Future<void> _pickImageAndAsk(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (picked == null) return; // User cancelled

      final imageFile = File(picked.path);
      final imageBytes = await imageFile.readAsBytes();

      // Show a dialog asking what they want to know about the image
      if (!mounted) return;
      final question = await _showImageQuestionDialog();
      if (question == null || question.trim().isEmpty) return;

      // Send to chat provider as a vision message
      ref
          .read(chatProvider.notifier)
          .sendImageMessage(question, Uint8List.fromList(imageBytes));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  /// Shows a dialog asking the user what they want to know about the picked image.
  Future<String?> _showImageQuestionDialog() async {
    final controller = TextEditingController(text: 'What is in this image?');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF7F4EF),
        title: Text(
          'Ask about this image',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.outfit(),
          decoration: InputDecoration(
            hintText: 'e.g., What is this? / Describe this / Read the text',
            hintStyle: GoogleFonts.outfit(color: Colors.grey, fontSize: 13),
            filled: true,
            fillColor: const Color(0xFFEFECE6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(
              'Ask',
              style: GoogleFonts.outfit(
                color: const Color(0xFFB3862B),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pick a PDF document, process it, and show confirmation in chat.
  Future<void> _pickAndProcessDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.single.path == null) return;

      if (!mounted) return;

      // Show processing indicator in chat
      final fileName = result.files.single.name;
      widget.onSend('📄 Processing document: $fileName');

      // Process the document
      final documentService = ref.read(documentServiceProvider);
      final file = File(result.files.single.path!);
      await documentService.processDocument(file);

      if (!mounted) return;

      // Confirm in chat — user can now ask questions about it
      widget.onSend(
        '✅ Document "$fileName" processed! You can now ask me questions about it. Try: "What does the document say about..."',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to process document: ${e.toString().length > 100 ? e.toString().substring(0, 100) : e}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isModelLoading = ref.watch(
      chatProvider.select((s) => s.isModelLoading),
    );
    final isListening = ref.watch(chatProvider.select((s) => s.isListening));
    final isThinking = ref.watch(chatProvider.select((s) => s.isThinking));

    // Update text field in real-time as user speaks
    ref.listen(chatProvider.select((s) => s.partialVoiceText), (prev, next) {
      if (next.isNotEmpty) {
        _controller.text = next;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    });

    // Clear text field when listening stops
    ref.listen(chatProvider.select((s) => s.isListening), (prev, next) {
      if (prev == true && next == false) {
        _controller.clear();
      }
    });

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      color: Colors.transparent, // Floating overlay
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92), // Glassmorphic background
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.black.withOpacity(0.04), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left: Plus button (attachment/scan/cancel-search)
            GestureDetector(
              onTap: () {
                if (_isWebSearchMode) {
                  setState(() => _isWebSearchMode = false);
                } else {
                  _showAttachmentMenu(context);
                }
              },
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 1.5),
                    ),
                  ],
                ),
                child: Icon(
                  _isWebSearchMode ? Icons.public_off : Icons.add,
                  color: _isWebSearchMode
                      ? ClayColors.goldAccent
                      : ClayColors.textDark,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Center: TextField
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: !isModelLoading,
                textInputAction: TextInputAction.send,
                keyboardType: TextInputType.text,
                style: GoogleFonts.outfit(
                  color: ClayColors.textDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: isModelLoading
                      ? 'Model loading...'
                      : (_isWebSearchMode
                            ? 'Search the web...'
                            : 'Ask Aura...'),
                  hintStyle: GoogleFonts.outfit(
                    color: ClayColors.textHint.withOpacity(0.65),
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                ),
                onChanged: (value) {
                  final shouldShow =
                      value.trim().startsWith('/') ||
                      value.trim().startsWith('@');
                  widget.onCommandMenuChanged(shouldShow);
                },
                onSubmitted: (_) => _sendMessage(),
              ),
            ),

            // Right: Microphone
            IconButton(
              icon: Icon(
                isListening ? Icons.mic_off : Icons.mic,
                color: isModelLoading
                    ? ClayColors.textHint.withOpacity(0.2)
                    : ClayColors.textDark,
              ),
              onPressed: isModelLoading
                  ? null
                  : () {
                      if (isListening) {
                        ref.read(chatProvider.notifier).stopVoiceConversation();
                      } else {
                        ref.read(chatProvider.notifier).startListening();
                      }
                    },
            ),
            const SizedBox(width: 4),

            // Send Button with orange/terracotta gradient
            GestureDetector(
              onTap: isModelLoading
                  ? null
                  : isThinking
                  ? () => ref.read(chatProvider.notifier).stopGeneration()
                  : _sendMessage,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isModelLoading
                        ? [const Color(0xFFE0DCD6), const Color(0xFFCBC7BE)]
                        : [
                            const Color(0xFFFF9E80), // Vibrant peach-orange
                            const Color(0xFFBC4B2E), // Terracotta accent
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: isModelLoading
                      ? []
                      : [
                          BoxShadow(
                            color: ClayColors.goldAccent.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Icon(
                  isThinking ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
