import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/widgets/app_drawer.dart';
import 'package:aura_mobile/presentation/widgets/greeting_widget.dart';
import 'package:aura_mobile/presentation/widgets/chat_app_bar.dart';
import 'package:aura_mobile/presentation/widgets/chat_input_bar.dart';
import 'package:aura_mobile/presentation/widgets/chat_message_bubble.dart';
import 'package:aura_mobile/presentation/widgets/email_draft_card.dart';
import 'package:aura_mobile/presentation/widgets/proactive_nudge_card.dart';
import 'package:aura_mobile/core/services/proactive_engine.dart';
import 'package:aura_mobile/presentation/providers/study_provider.dart';
import 'package:aura_mobile/presentation/pages/study_dashboard_screen.dart';
import 'package:aura_mobile/presentation/pages/camera_scan_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showCommandMenu = false;
  static const MethodChannel _assistantChannel = MethodChannel('com.aura.ai/assistant_ai');

  // Proactive AI state
  ProactiveNudge? _activeNudge;
  bool _nudgeChecked = false;

  // Track message count to only scroll on new messages (not every rebuild)
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _assistantChannel.setMethodCallHandler((call) async {
      // Native voice-initiated email drafts are handled by the orchestrator
    });
    _checkProactiveNudge();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkProactiveNudge() async {
    if (_nudgeChecked) return;
    _nudgeChecked = true;
    try {
      int dueCards = 0;
      int upcomingExams = 0;
      int closestExamDays = 999;
      int totalDecks = 0;

      try {
        final studyState = ref.read(studyProvider);
        dueCards = studyState.reviewQueue.length;
        upcomingExams = studyState.upcomingExams.length;
        totalDecks = studyState.decks.length;
        if (studyState.upcomingExams.isNotEmpty) {
          closestExamDays = studyState.upcomingExams.first.daysRemaining;
        }
      } catch (_) {}

      final nudge = await ProactiveEngine.generateNudge(
        dueCards: dueCards,
        upcomingExams: upcomingExams,
        closestExamDays: closestExamDays,
        totalDecks: totalDecks,
      );

      if (nudge != null && mounted) {
        setState(() => _activeNudge = nudge);
      }
    } catch (e) {
      debugPrint('Proactive nudge check failed: $e');
    }
  }

  void _handleNudgeAction(ProactiveNudge nudge) {
    setState(() => _activeNudge = null);
    switch (nudge.action) {
      case NudgeAction.openStudy:
      case NudgeAction.startReview:
      case NudgeAction.startQuiz:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const StudyDashboardScreen()));
        break;
      case NudgeAction.openScan:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScanScreen()));
        break;
      case NudgeAction.openChat:
      case NudgeAction.dismiss:
        break;
    }
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

  void _sendMessage(String text) {
    if (text.trim().isNotEmpty) {
      ref.read(chatProvider.notifier).sendMessage(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);

    // Filter out internal system messages
    final visibleMessages = chatState.messages.where((m) {
      return !(m['role'] == 'system' && m['content']!.startsWith('drafting_email_to:'));
    }).toList();

    // Only scroll to bottom when new messages actually arrive (not on every rebuild)
    if (visibleMessages.length != _lastMessageCount) {
      _lastMessageCount = visibleMessages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0c),
      drawer: const AppDrawer(),
      extendBodyBehindAppBar: true,
      appBar: ChatAppBar(
        onNewChat: () {
          ref.read(chatProvider.notifier).clearChat();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("New chat started"), duration: Duration(seconds: 1)),
          );
        },
      ),
      body: Column(
        children: [
          // Proactive AI Nudge Card
          if (_activeNudge != null)
            ProactiveNudgeCard(
              nudge: _activeNudge!,
              onAction: () => _handleNudgeAction(_activeNudge!),
              onDismiss: () => setState(() => _activeNudge = null),
            ),

          Expanded(
            child: Stack(
              children: [
                // Chat Content or Welcome Message
                Positioned.fill(
                  child: visibleMessages.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 60),
                                  SizedBox(width: double.infinity, child: GreetingWidget()),
                                ],
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(0, 100, 0, 80),
                          itemCount: visibleMessages.length,
                          itemBuilder: (context, index) {
                            return _ChatMessageItem(
                              message: visibleMessages[index],
                              allMessages: chatState.messages,
                              onOptionSelected: _sendMessage,
                            );
                          },
                        ),
                ),

                // Command Menu (Floating Popup)
                if (_showCommandMenu)
                  Positioned(
                    bottom: 8,
                    left: 16,
                    right: 16,
                    child: _CommandMenu(
                      onWebSearch: () {
                        setState(() => _showCommandMenu = false);
                        // TODO: communicate web search mode to input bar
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Thinking indicator
          if (chatState.isThinking)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFc69c3a)),
                  ),
                  const SizedBox(width: 12),
                  Text("Thinking...", style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),

          // Input Area
          ChatInputBar(
            onSend: _sendMessage,
            onCommandMenuChanged: (show) {
              if (_showCommandMenu != show) {
                setState(() => _showCommandMenu = show);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Individual chat message item — extracted to avoid inline parsing in build.
/// Uses pre-computed data and delegates to extracted bubble widgets.
class _ChatMessageItem extends StatelessWidget {
  final Map<String, String> message;
  final List<Map<String, String>> allMessages;
  final ValueChanged<String> onOptionSelected;

  const _ChatMessageItem({
    required this.message,
    required this.allMessages,
    required this.onOptionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message['role'] == 'user';
    String displayContent = message['content'] ?? '';

    if (isUser) {
      return UserMessageBubble(content: displayContent);
    }

    // Parse email draft info
    String? draftAddress;
    String? parsedSubject;
    String? parsedBody;
    bool isEmailDraft = false;

    final rawIndex = allMessages.indexOf(message);
    if (rawIndex > 0) {
      for (int i = rawIndex - 1; i >= 0; i--) {
        final m = allMessages[i];
        if (m['role'] == 'system' && m['content']!.startsWith('drafting_email_to:')) {
          draftAddress = m['content']!.replaceFirst('drafting_email_to:', '');
          break;
        } else if (m['role'] == 'user') {
          break;
        }
      }
    }

    if (draftAddress != null && displayContent.contains("Subject:")) {
      final subjectMatch = RegExp(r"Subject:\s*(.+?)(?:\n|$)").firstMatch(displayContent);
      if (subjectMatch != null) parsedSubject = subjectMatch.group(1)?.trim();

      final afterSubject = displayContent.substring(subjectMatch?.end ?? 0).trim();
      parsedBody = afterSubject.replaceFirst(RegExp(r'^Body:\s*', caseSensitive: false), '').trim();

      if (parsedSubject != null || parsedBody.isNotEmpty) {
        isEmailDraft = true;
        displayContent = '';
      }
    }

    // Parse options
    List<Map<String, String>> options = [];
    final optionsRegex = RegExp(r'\[\[OPTIONS:(.*?)\]\]');
    final match = optionsRegex.firstMatch(displayContent);
    if (match != null) {
      displayContent = displayContent.substring(0, match.start).trim();
      final optionsStr = match.group(1) ?? "";
      options = optionsStr.split(',').map((e) {
        final parts = e.split('|');
        return {
          'label': parts[0].trim(),
          'value': parts.length > 1 ? parts[1].trim() : parts[0].trim(),
        };
      }).toList();
    }

    return AssistantMessageBubble(
      content: displayContent,
      options: options,
      onOptionSelected: onOptionSelected,
      emailDraftCard: isEmailDraft
          ? EmailDraftCard(
              address: draftAddress!,
              subject: parsedSubject,
              body: parsedBody,
            )
          : null,
    );
  }
}

/// Command menu popup — extracted to avoid inline widget trees.
class _CommandMenu extends StatelessWidget {
  final VoidCallback onWebSearch;

  const _CommandMenu({required this.onWebSearch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFc69c3a), width: 1),
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
              onTap: onWebSearch,
            ),
          ],
        ),
      ),
    );
  }
}
