import 'package:flutter/material.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/pages/camera_scan_screen.dart';

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
  bool _isWebSearchMode = false;

  @override
  void dispose() {
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
    }
  }

  void setWebSearchMode(bool value) {
    setState(() => _isWebSearchMode = value);
  }

  @override
  Widget build(BuildContext context) {
    final isModelLoading = ref.watch(chatProvider.select((s) => s.isModelLoading));
    final isListening = ref.watch(chatProvider.select((s) => s.isListening));

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
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CameraScanScreen()),
                  );
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
                  color: _isWebSearchMode ? ClayColors.goldAccent : ClayColors.textDark,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            
            // Center: TextField
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !isModelLoading,
                style: GoogleFonts.outfit(
                  color: ClayColors.textDark, 
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: isModelLoading
                      ? 'Model loading...'
                      : (_isWebSearchMode ? 'Search the web...' : 'Ask Aura...'),
                  hintStyle: GoogleFonts.outfit(
                    color: ClayColors.textHint.withOpacity(0.65),
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                onChanged: (value) {
                  final shouldShow = value.trim().startsWith('/') || value.trim().startsWith('@');
                  widget.onCommandMenuChanged(shouldShow);
                },
                onSubmitted: (_) => _sendMessage(),
              ),
            ),

            // Right: Microphone
            IconButton(
              icon: Icon(
                isListening ? Icons.mic_off : Icons.mic,
                color: isModelLoading ? ClayColors.textHint.withOpacity(0.2) : ClayColors.textDark,
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
              onTap: isModelLoading ? null : _sendMessage,
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
                child: const Icon(
                  Icons.arrow_upward_rounded,
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
