import 'package:flutter/material.dart';
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
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  bool _isWebSearchMode = false;

  @override
  void initState() {
    super.initState();
    // Listen for voice partial text updates
    // (moved out of build to avoid re-registering every frame)
  }

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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF0a0a0c),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1a1a20),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  if (_isWebSearchMode)
                    IconButton(
                      icon: const Icon(Icons.public_off, color: Color(0xFFc69c3a), size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _isWebSearchMode = false),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.document_scanner_rounded, color: Color(0xFFc69c3a), size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Scan Image',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CameraScanScreen()),
                        );
                      },
                    ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !isModelLoading,
                      style: GoogleFonts.outfit(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: isModelLoading
                            ? 'Model loading...'
                            : (_isWebSearchMode ? 'Search the web...' : 'Ask Aura...'),
                        hintStyle: GoogleFonts.outfit(color: Colors.white30),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                      onChanged: (value) {
                        final shouldShow = value.trim().startsWith('/') || value.trim().startsWith('@');
                        widget.onCommandMenuChanged(shouldShow);
                      },
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isListening ? Icons.mic_off : Icons.mic,
                      color: isModelLoading ? Colors.white10 : Colors.white54,
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
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: isModelLoading ? null : _sendMessage,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isModelLoading
                      ? [const Color(0xFF2a2a30), const Color(0xFF1a1a20)]
                      : [const Color(0xFFe6cf8e), const Color(0xFFc69c3a)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(
                Icons.arrow_upward,
                color: isModelLoading ? Colors.white10 : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Allows parent to activate web search mode from command menu
  void setWebSearchMode(bool value) {
    setState(() => _isWebSearchMode = value);
  }
}
