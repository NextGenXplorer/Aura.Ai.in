import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';
import 'package:aura_mobile/presentation/pages/model_selector_screen.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showCommandMenu = false;
  bool _isWebSearchMode = false;


  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);

    // Scroll to bottom when new messages arrive
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0c), // Obsidian
      appBar: AppBar(
        title: Consumer(
          builder: (context, ref, _) {
            final modelState = ref.watch(modelSelectorProvider);
            final activeModel = modelState.activeModelId != null
                ? modelState.availableModels.firstWhere(
                    (m) => m.id == modelState.activeModelId,
                    orElse: () => modelState.availableModels.first,
                  )
                : null;
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AURA Mobile',
                  style: TextStyle(color: Color(0xFFe6cf8e), fontSize: 18),
                ),
                if (activeModel != null)
                  Text(
                    activeModel.name,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
              ],
            );
          },
        ),
        backgroundColor: const Color(0xFF141418), // Obsidian Light
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology, color: Color(0xFFc69c3a)),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ModelSelectorScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                 // 1. Chat Content or Welcome Message
                 Positioned.fill(
                   child: chatState.messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white24),
                            const SizedBox(height: 16),
                            Text(
                              'Welcome to AURA\nI am ready to help.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), // Extra bottom padding for menu space
                        itemCount: chatState.messages.length,
                        itemBuilder: (context, index) {
                          final msg = chatState.messages[index];
                          final isUser = msg['role'] == 'user';
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isUser ? const Color(0xFF2a2a30) : const Color(0xFF1a1a20),
                                borderRadius: BorderRadius.circular(12).copyWith(
                                  bottomRight: isUser ? Radius.zero : null,
                                  bottomLeft: !isUser ? Radius.zero : null,
                                ),
                                border: Border.all(
                                  color: const Color(0xFFc69c3a).withValues(alpha: 0.2),
                                ),
                              ),
                              child: MarkdownBody(
                                data: msg['content'] ?? '',
                                styleSheet: MarkdownStyleSheet(
                                  p: const TextStyle(color: Colors.white70),
                                  strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  a: const TextStyle(color: Color(0xFFc69c3a), decoration: TextDecoration.underline),
                                  code: const TextStyle(color: Color(0xFFe6cf8e), backgroundColor: Color(0xFF2a2a30), fontFamily: 'monospace'),
                                ),
                                onTapLink: (text, href, title) async {
                                  if (href != null) {
                                    final Uri url = Uri.parse(href);
                                    if (await canLaunchUrl(url)) {
                                      await launchUrl(url, mode: LaunchMode.externalApplication);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Could not launch $href')),
                                      );
                                    }
                                  }
                                },
                                selectable: true,
                              ),
                            ),
                          );
                        },
                      ),
                 ),

                 // 2. Command Menu (Floating Popup)
                 if (_showCommandMenu)
                  Positioned(
                    bottom: 8,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a1a20), // Dark background matching theme
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFc69c3a), width: 1), // Gold border
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.public, color: Color(0xFFc69c3a)),
                              title: const Text('Web Search', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: const Text('Search the internet for real-time info', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              onTap: () {
                                print("CHAT_SCREEN: Web Search selected from Floating Menu");
                                setState(() {
                                  _isWebSearchMode = true;
                                  _showCommandMenu = false;
                                  _controller.clear();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (chatState.isThinking)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: Color(0xFFc69c3a),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF141418),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: _isWebSearchMode ? 'Search the web...' : 'Ask AURA...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                      prefixIcon: _isWebSearchMode 
                          ? IconButton(
                              icon: const Icon(Icons.public, color: Color(0xFFc69c3a)),
                              onPressed: () {
                                setState(() {
                                  _isWebSearchMode = false;
                                });
                              },
                              tooltip: 'Cancel Search Mode',
                            ) 
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0a0a0c),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    onChanged: (value) {
                       final shouldShow = value.trim().startsWith('/') || value.trim().startsWith('@');
                       if (_showCommandMenu != shouldShow) {
                          print("CHAT_SCREEN: Menu State Changed to $shouldShow");
                          setState(() {
                            _showCommandMenu = shouldShow;
                          });
                       }
                    },
                    onSubmitted: (value) {
                       if (value.trim().isNotEmpty) {
                        final messageToSend = _isWebSearchMode ? "[SEARCH] $value" : value;
                        ref.read(chatProvider.notifier).sendMessage(messageToSend);
                        _controller.clear();
                        setState(() {
                          _isWebSearchMode = false;
                           // Don't hide menu here, onChanged handles it but clearing text will hide it
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(chatState.isListening ? Icons.mic_off : Icons.mic, color: const Color(0xFFc69c3a)),
                  onPressed: () {
                    if (chatState.isListening) {
                      ref.read(chatProvider.notifier).stopListening();
                    } else {
                      ref.read(chatProvider.notifier).startListening();
                    }
                  },
                ),
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFe6cf8e), Color(0xFFc69c3a)],
                    ),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF0a0a0c)),
                    onPressed: () {
                      if (_controller.text.trim().isNotEmpty) {
                        final messageToSend = _isWebSearchMode ? "[SEARCH] ${_controller.text}" : _controller.text;
                        ref.read(chatProvider.notifier).sendMessage(messageToSend);
                        _controller.clear();
                        setState(() {
                          _isWebSearchMode = false;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
