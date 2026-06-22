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
import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:aura_mobile/presentation/widgets/context_window_indicator.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showCommandMenu = false;
  bool _showTopIndicators = true;
  // Proactive AI state
  ProactiveNudge? _activeNudge;
  bool _nudgeChecked = false;

  // Track message count to only scroll on new messages (not every rebuild)
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
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
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final double topSpacerHeight = isKeyboardOpen
        ? 70.0
        : (_activeNudge != null ? 240.0 : 150.0);

    // Filter out internal system messages
    final visibleMessages = chatState.messages.where((m) {
      return !(m['role'] == 'system' && m['content']!.startsWith('drafting_email_to:'));
    }).toList();

    // Only scroll to bottom when new messages actually arrive (not on every rebuild)
    if (visibleMessages.length != _lastMessageCount) {
      _lastMessageCount = visibleMessages.length;
      if (visibleMessages.isEmpty) {
        _showTopIndicators = true;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
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
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                    height: topSpacerHeight,
                                  ),
                                  const SizedBox(width: double.infinity, child: GreetingWidget()),
                                ],
                              ),
                            ),
                          ),
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            final offset = notification.metrics.pixels;
                            final show = offset <= 5.0;
                            if (show != _showTopIndicators) {
                              setState(() {
                                _showTopIndicators = show;
                              });
                            }
                            return false;
                          },
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.fromLTRB(
                              0,
                              _activeNudge != null ? 230.0 : 140.0,
                              0,
                              96,
                            ),
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
                ),

                // Floating indicators & Proactive Nudge Card
                Positioned(
                  top: MediaQuery.of(context).padding.top + kToolbarHeight + 4,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _showTopIndicators ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_showTopIndicators,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_activeNudge != null)
                            ProactiveNudgeCard(
                              nudge: _activeNudge!,
                              onAction: () => _handleNudgeAction(_activeNudge!),
                              onDismiss: () => setState(() => _activeNudge = null),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: const ContextWindowIndicator(),
                                ),
                                const SizedBox(width: 8),
                                const ConciseBadge(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
              padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 4.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ClayContainer(
                  borderRadius: 12,
                  depth: 1.0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5, 
                          color: ClayColors.goldAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Thinking...", 
                        style: GoogleFonts.outfit(
                          color: ClayColors.textMuted, 
                          fontSize: 11, 
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
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
    final isSystem = message['role'] == 'system';
    final isAutomation = isSystem && (message['content']?.startsWith('automation_triggered:') ?? false);

    if (isAutomation) {
      final contentStr = message['content']!.replaceFirst('automation_triggered:', '');
      final parts = contentStr.split(' - ');
      final ruleName = parts[0];
      final logs = parts.length > 1 ? parts.sublist(1).join(' - ') : '';
      final stepLogs = logs.split('\n');

      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
            child: ClayContainer(
              borderRadius: 18,
              depth: 4.5,
              baseColor: const Color(0xFFECE9E3), // Soft Clay Warm Grey
              highlightColor: const Color(0xFFFFFFFF),
              shadowColor: const Color(0xFFD6CDBB),
              padding: const EdgeInsets.all(16),
              border: Border.all(
                color: const Color(0xFFC8A96A).withOpacity(0.3),
                width: 1.2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFC8A96A),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ruleName,
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: ClayColors.textDark,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: const Color(0xFF34C759).withOpacity(0.12),
                        ),
                        child: Text(
                          'Executed',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF248A3D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(color: Color(0xFFDCD8CF), height: 1),
                  ),
                  ...stepLogs.map((log) {
                    if (log.trim().isEmpty) return const SizedBox.shrink();
                    final logParts = log.split(': ');
                    final stepType = logParts[0];
                    final stepResult = logParts.length > 1 ? logParts.sublist(1).join(': ') : '';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF34C759),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$stepType: ',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: ClayColors.textDark,
                                    ),
                                  ),
                                  TextSpan(
                                    text: stepResult,
                                    style: GoogleFonts.outfit(
                                      fontSize: 12.5,
                                      color: ClayColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
    return ClayContainer(
      borderRadius: 20,
      depth: 6.0,
      baseColor: ClayColors.warmGrey,
      highlightColor: ClayColors.highlight,
      shadowColor: ClayColors.shadow,
      border: Border.all(color: ClayColors.goldAccent.withOpacity(0.35), width: 1.2),
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.public_rounded, color: ClayColors.goldAccent),
              title: Text('Web Search', style: GoogleFonts.outfit(color: ClayColors.textDark, fontWeight: FontWeight.bold)),
              subtitle: Text('Search the internet for real-time info', style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 12)),
              onTap: onWebSearch,
            ),
          ],
        ),
      ),
    );
  }
}
