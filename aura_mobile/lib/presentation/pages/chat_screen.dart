import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';
import 'package:aura_mobile/presentation/widgets/app_drawer.dart';
import 'package:aura_mobile/presentation/widgets/greeting_widget.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:aura_mobile/presentation/widgets/code_element_builder.dart';

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
  static const MethodChannel _assistantChannel = MethodChannel('com.aura.ai/assistant_ai');
  // Tracks which email draft is in edit mode: key = message index, value = TextEditingController
  final Map<int, TextEditingController> _emailEditControllers = {};

  @override
  void initState() {
    super.initState();
    _assistantChannel.setMethodCallHandler((call) async {
      // Native voice-initiated email drafts are now handled by the orchestrator
      // via the emailDraft intent — no Flutter-side pending state required.
    });
  }


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
    final isModelLoading = chatState.isModelLoading;

    // Filter out internal system messages like 'drafting_email_to:...'
    final visibleMessages = chatState.messages.where((m) {
       return !(m['role'] == 'system' && m['content']!.startsWith('drafting_email_to:'));
    }).toList();

    // Scroll to bottom when new messages arrive
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // 1. Update text field in real-time as user speaks
    ref.listen(chatProvider.select((s) => s.partialVoiceText), (prev, next) {
      if (next.isNotEmpty) {
        _controller.text = next;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    });

    // 2. Clear text field explicitly when listening stops
    ref.listen(chatProvider.select((s) => s.isListening), (prev, next) {
      if (prev == true && next == false) {
        _controller.clear();
      }
    });
    final modelState = ref.watch(modelSelectorProvider);
    // final isModelLoading = chatState.isModelLoading || modelState.activeModelId == null; // Redundant, already defined above

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0c), // Obsidian - Keep opaque for normal app use
      drawer: const AppDrawer(), // Sidebar Implementation
      extendBodyBehindAppBar: true, // Transparent AppBar effect
      appBar: AppBar(
        title: Consumer(
          builder: (context, ref, child) {
            final modelState = ref.watch(modelSelectorProvider);
            final chatState = ref.watch(chatProvider);
            
            // Unified loading/readiness state
            final isAppInitializing = modelState.activeModelId == null || chatState.isModelLoading;

            if (isAppInitializing) {
                 return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1a1a20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      "Loading...",
                      style: GoogleFonts.outfit(
                        color: Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                 );
            }

            final activeModel = modelState.availableModels.firstWhere(
              (m) => m.id == modelState.activeModelId,
              orElse: () => modelState.availableModels.first,
            );
            
            return GestureDetector(
              onTap: () {
                 Scaffold.of(context).openDrawer(); 
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1a1a20),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  activeModel.name,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0a0a0c).withOpacity(0.7), // Semi-transparent Obsidian
        elevation: 0,
        leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
                backgroundColor: const Color(0xFF1a1a20),
                child: Builder(
                  builder: (context) {
                    return IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white70, size: 20),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                    );
                  }
                ),
            ),
        ),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        actions: [
            Padding(
                padding: const EdgeInsets.only(right: 8.0),
                 child: CircleAvatar(
                    backgroundColor: const Color(0xFF1a1a20),
                    child: IconButton(
                        icon: const Icon(Icons.add, color: Colors.white70, size: 20),
                        tooltip: "New Chat",
                        onPressed: () {
                          ref.read(chatProvider.notifier).clearChat();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("New chat started"), duration: Duration(seconds: 1)),
                          );
                        },
                    ),
                ),
            ),
             Padding(
                padding: const EdgeInsets.only(right: 16.0),
                 child: CircleAvatar(
                    backgroundColor: const Color(0xFF1a1a20),
                    child: IconButton(
                        icon: const Icon(Icons.more_horiz, color: Colors.white70, size: 20),
                         tooltip: "Options",
                        onPressed: () {
                           ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Settings coming soon!"), duration: Duration(seconds: 1)),
                          );
                        },
                    ),
                ),
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
                   child: visibleMessages.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 60), // Offset for transparent AppBar
                              SizedBox(width: double.infinity, child: GreetingWidget()), // Dynamic Greeting
                            ],
                          ),
                        ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(0, 100, 0, 80), // No horizontal padding - items add their own
                        itemCount: visibleMessages.length,
                        itemBuilder: (context, index) {
                          final message = visibleMessages[index];
                          final isUser = message['role'] == 'user';
                          
                          // Parse options if present (mostly for old legacy code paths)
                          List<Map<String, String>> options = [];
                          String displayContent = message['content'] ?? '';
                          
                          // Parse email draft
                          String? draftAddress;
                          String? parsedSubject;
                          String? parsedBody;
                          bool isEmailDraft = false;
                          
                          if (!isUser) {
                             // Find the last known drafted address before this message in the raw list
                             final rawIndex = chatState.messages.indexOf(message);
                             if (rawIndex > 0) {
                                 for (int i = rawIndex - 1; i >= 0; i--) {
                                    final m = chatState.messages[i];
                                    if (m['role'] == 'system' && m['content']!.startsWith('drafting_email_to:')) {
                                        draftAddress = m['content']!.replaceFirst('drafting_email_to:', '');
                                        break;
                                    } else if (m['role'] == 'user') {
                                        // Stop searching if we hit another user message
                                        break;
                                    }
                                 }
                             }

                             if (draftAddress != null && displayContent.contains("Subject:")) {
                                 // Parse Subject: line
                                 final subjectMatch = RegExp(r"Subject:\s*(.+?)(?:\n|$)").firstMatch(displayContent);
                                 if (subjectMatch != null) parsedSubject = subjectMatch.group(1)?.trim();

                                 // Parse body: everything after the Subject line
                                 // Handles both "Body: ..." format and the new "\n\n[body]" format
                                 final afterSubject = displayContent.substring(
                                   (subjectMatch?.end ?? 0),
                                 ).trim();
                                 // Remove "Body:" prefix if present (legacy format)
                                 parsedBody = afterSubject.replaceFirst(RegExp(r'^Body:\s*', caseSensitive: false), '').trim();

                                 if (parsedSubject != null || parsedBody!.isNotEmpty) {
                                     isEmailDraft = true;
                                     // Blank out the main bubble content — the card shows everything
                                     displayContent = '';
                                 }
                             }
                           }
                          
                          final optionsRegex = RegExp(r'\[\[OPTIONS:(.*?)\]\]');
                          final match = optionsRegex.firstMatch(displayContent);
                          if (match != null) {
                            displayContent = displayContent.substring(0, match.start).trim();
                            final optionsStr = match.group(1) ?? "";
                            options = optionsStr.split(',').map((e) {
                              final parts = e.split('|');
                              return {
                                'label': parts[0].trim(),
                                'value': parts.length > 1 ? parts[1].trim() : parts[0].trim()
                              };
                            }).toList();
                          }

                           // USER MESSAGE: right-aligned constrained pill
                           if (isUser) return Align(
                             alignment: Alignment.centerRight,
                             child: Container(
                               margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                               constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                               decoration: BoxDecoration(
                                 color: const Color(0xFF2a2a30),
                                 borderRadius: BorderRadius.circular(20).copyWith(bottomRight: Radius.zero),
                                 border: Border.all(color: const Color(0xFFc69c3a).withOpacity(0.3)),
                               ),
                               child: MarkdownBody(
                                 data: displayContent,
                                 styleSheet: MarkdownStyleSheet(
                                   p: TextStyle(color: Colors.white, fontSize: 16, height: 1.5, fontFamily: GoogleFonts.outfit().fontFamily),
                                   strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                   a: const TextStyle(color: Color(0xFFc69c3a), decoration: TextDecoration.underline),
                                   code: const TextStyle(color: Color(0xFFe6cf8e), backgroundColor: Color(0xFF1a1a20), fontFamily: 'monospace', fontSize: 14),
                                 ),
                                 selectable: true,
                               ),
                             ),
                           );

                           // AI MESSAGE: full-width like email draft card
                           return Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               Padding(
                                 padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                 child: MarkdownBody(
                                   data: displayContent,
                                   builders: {'code': CodeElementBuilder(context)},
                                   styleSheet: MarkdownStyleSheet(
                                     p: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16, height: 1.5, fontFamily: GoogleFonts.outfit().fontFamily),
                                     strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                     a: const TextStyle(color: Color(0xFFc69c3a), decoration: TextDecoration.underline),
                                     code: const TextStyle(color: Color(0xFFe6cf8e), backgroundColor: Color(0xFF1a1a20), fontFamily: 'monospace', fontSize: 14),
                                   ),
                                   onTapLink: (text, href, title) async {
                                     if (href != null) {
                                       final Uri url = Uri.parse(href);
                                       if (await canLaunchUrl(url)) {
                                         await launchUrl(url, mode: LaunchMode.externalApplication);
                                       } else {
                                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not launch $href')));
                                       }
                                     }
                                   },
                                   selectable: true,
                                 ),
                               ),
                               if (options.isNotEmpty)
                                 Padding(
                                   padding: const EdgeInsets.only(left: 4, bottom: 8),
                                   child: Wrap(
                                     spacing: 8, runSpacing: 8,
                                     children: options.map((opt) {
                                       return ActionChip(
                                         label: Text(opt['label']!, style: GoogleFonts.outfit(color: Colors.white)),
                                         backgroundColor: const Color(0xFF2a2a30),
                                         side: const BorderSide(color: Color(0xFFc69c3a)),
                                         onPressed: () { _sendMessage(opt['value']!); },
                                       );
                                     }).toList(),
                                   ),
                                 ),
                               if (isEmailDraft) _buildEmailDraftCard(
                                 msgIndex: index,
                                 address: draftAddress!,
                                 subject: parsedSubject,
                                 body: parsedBody,
                               ),
                             ],
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
                        color: const Color(0xFF1a1a20), // Dark background
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFc69c3a), width: 1), // Gold border
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 10,
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
                              title: Text('Web Search', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text('Search the internet for real-time info', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
                              onTap: () {
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Row(
                children: [
                   const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFc69c3a))),
                   const SizedBox(width: 12),
                   Text("Thinking...", style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          
          // Input Area
          Container(
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
                              onPressed: () {
                                setState(() {
                                  _isWebSearchMode = false;
                                });
                              },
                          )
                        else
                          const Icon(Icons.add, color: Colors.white54),
                        
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
                               if (_showCommandMenu != shouldShow) {
                                  setState(() {
                                    _showCommandMenu = shouldShow;
                                  });
                               }
                            },
                            onSubmitted: (value) => _sendMessage(value),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            chatState.isListening ? Icons.mic_off : Icons.mic, 
                            color: chatState.isModelLoading ? Colors.white10 : Colors.white54
                          ),
                          onPressed: isModelLoading ? null : () {
                            if (chatState.isListening) {
                              ref.read(chatProvider.notifier).stopListening();
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
                  onTap: isModelLoading ? null : () => _sendMessage(_controller.text),
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
                      color: isModelLoading ? Colors.white10 : Colors.black
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the email draft card with Edit + Send buttons.
  Widget _buildEmailDraftCard({
    required int msgIndex,
    required String address,
    String? subject,
    String? body,
  }) {
    return StatefulBuilder(
      builder: (context, setCardState) {
        final isEditing = _emailEditControllers.containsKey(msgIndex);
        final editController = _emailEditControllers[msgIndex];

        return Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1a1a22), Color(0xFF141418)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFc69c3a).withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFc69c3a).withOpacity(0.12),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.email_outlined, color: Color(0xFFc69c3a), size: 18),
                    const SizedBox(width: 8),
                    Text('Email Draft', style: GoogleFonts.outfit(
                      color: const Color(0xFFc69c3a),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    )),
                  ],
                ),
              ),
              // Fields
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _emailField(label: 'To', value: address),
                    const SizedBox(height: 8),
                    _emailField(label: 'Subject', value: subject ?? ''),
                    const SizedBox(height: 8),
                    Text('Body', style: GoogleFonts.outfit(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    )),
                    const SizedBox(height: 4),
                    isEditing
                      ? TextField(
                          controller: editController,
                          maxLines: null,
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, height: 1.6),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF2a2a35),
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFc69c3a), width: 1),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFc69c3a), width: 1.5),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                            ),
                          ),
                        )
                      : Text(
                          body ?? '',
                          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14, height: 1.6),
                        ),
                  ],
                ),
              ),
              // Action Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    // Edit / Done Editing button
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(
                          isEditing ? Icons.check_circle_outline : Icons.edit_outlined,
                          size: 16,
                          color: Colors.white70,
                        ),
                        label: Text(
                          isEditing ? 'Done Editing' : 'Edit Email',
                          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.white.withOpacity(0.2)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          setCardState(() {
                            if (isEditing) {
                              _emailEditControllers.remove(msgIndex);
                            } else {
                              _emailEditControllers[msgIndex] =
                                  TextEditingController(text: body ?? '');
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Send Email button
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.send, size: 16, color: Colors.black),
                        label: Text(
                          'Send Email',
                          style: GoogleFonts.outfit(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFc69c3a),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () async {
                          final finalBody = (isEditing
                                  ? (editController?.text ?? body ?? '')
                                  : body ?? '')
                              .replaceAll('[Your Name]', 'Aura User');
                          try {
                            const channel = MethodChannel('com.aura.ai/app_control');
                            await channel.invokeMethod('launchEmailApp', {
                              'address': address,
                              'subject': subject ?? '',
                              'body': finalBody,
                            });
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Could not launch email client: $e')),
                              );
                            }
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
      },
    );
  }

  Widget _emailField({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.outfit(
          color: Colors.white38,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        )),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.outfit(color: Colors.white, fontSize: 14)),
      ],
    );
  }

  void _sendMessage(String text) {
    if (text.trim().isNotEmpty) {
      // All email intent detection is handled by the orchestrator's emailDraft intent.
      // No email hacks needed here — just pass the message through normally.
      final messageToSend = _isWebSearchMode ? '[SEARCH] $text' : text;
      ref.read(chatProvider.notifier).sendMessage(messageToSend);
      _controller.clear();
      setState(() {
        _isWebSearchMode = false;
      });
    }
  }

  String? _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

}
