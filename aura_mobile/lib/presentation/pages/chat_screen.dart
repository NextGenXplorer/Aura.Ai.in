import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/providers/chat_view_providers.dart';
import 'package:aura_mobile/presentation/widgets/app_drawer.dart';
import 'package:aura_mobile/presentation/widgets/greeting_widget.dart';
import 'package:aura_mobile/presentation/widgets/chat_app_bar.dart';
import 'package:aura_mobile/presentation/widgets/chat_input_bar.dart';
import 'package:aura_mobile/presentation/widgets/chat_message_bubble.dart';
import 'package:aura_mobile/presentation/widgets/email_draft_card.dart';
import 'package:aura_mobile/presentation/widgets/proactive_nudge_card.dart';
import 'package:aura_mobile/core/services/proactive_engine.dart';
import 'package:aura_mobile/core/services/widget_route_service.dart';
import 'package:aura_mobile/presentation/providers/study_provider.dart';
import 'package:aura_mobile/presentation/pages/study_dashboard_screen.dart';
import 'package:aura_mobile/presentation/pages/camera_scan_screen.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:aura_mobile/presentation/widgets/context_window_indicator.dart';
import 'package:aura_mobile/features/interactive_agent/ui/interactive_session_overlay.dart';
import 'package:aura_mobile/features/interactive_agent/interactive_agent_providers.dart';
import 'package:aura_mobile/features/smart_summarizer/share_receiver_service.dart';
import 'package:aura_mobile/features/smart_summarizer/summarizer_sheet.dart';

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

  /// Whether the list should stay pinned to the bottom as new text arrives.
  bool _autoFollow = true;
  bool _scrollFollowScheduled = false;
  bool _userDragging = false;

  /// How far from the bottom the user may sit and still be auto-followed.
  static const double _autoFollowThreshold = 120.0;

  // Share receiver subscription
  StreamSubscription<SharedContent>? _shareSubscription;

  @override
  void initState() {
    super.initState();
    _checkProactiveNudge();
    _listenForSharedContent();
    // The Voice quick-action widget can only open the app; the microphone lives
    // here, so the chat shell handles the hand-off.
    WidgetRouteService.onVoiceRequested = _startVoiceFromWidget;
  }

  @override
  void dispose() {
    if (WidgetRouteService.onVoiceRequested == _startVoiceFromWidget) {
      WidgetRouteService.onVoiceRequested = null;
    }
    _scrollController.dispose();
    _shareSubscription?.cancel();
    super.dispose();
  }

  void _startVoiceFromWidget() {
    if (!mounted) return;
    ref.read(chatProvider.notifier).startListening();
  }

  /// Listen for content shared from other apps and show the summarizer sheet.
  void _listenForSharedContent() {
    // Check for pending content (app was cold-started via share)
    final pending = ShareReceiverService.pendingContent;
    if (pending != null && pending.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          SummarizerSheet.show(context, pending);
          ShareReceiverService.clearPending();
        }
      });
    }

    // Listen for new shares while app is open
    _shareSubscription = ShareReceiverService.incomingContent.listen((content) {
      if (mounted && content.isNotEmpty) {
        SummarizerSheet.show(context, content);
        ShareReceiverService.clearPending();
      }
    });
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
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StudyDashboardScreen()),
        );
        break;
      case NudgeAction.openScan:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CameraScanScreen()),
        );
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

  /// Keeps the newest text in view while a reply streams in, but only while the
  /// user is still parked at the bottom — scrolling up to re-read something
  /// must not be yanked back down.
  ///
  /// Uses `jumpTo` rather than `animateTo`: a fresh 300ms animation started on
  /// every update fights the previous one and reads as stutter.
  void _followStreamToBottom() {
    if (!_autoFollow || _userDragging || _scrollFollowScheduled) return;
    _scrollFollowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollFollowScheduled = false;
      if (!mounted || !_autoFollow || _userDragging) return;
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;
      if (position.pixels < position.maxScrollExtent) {
        position.jumpTo(position.maxScrollExtent);
      }
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    final metrics = notification.metrics;

    // Never jump the list out from under a finger that is on the screen.
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) _userDragging = true;
    } else if (notification is ScrollEndNotification) {
      _userDragging = false;
    }

    // Re-arm auto-follow once the user returns to (near) the bottom.
    final distanceToBottom = metrics.maxScrollExtent - metrics.pixels;
    _autoFollow = distanceToBottom <= _autoFollowThreshold;

    final show = metrics.pixels <= 5.0;
    if (show != _showTopIndicators) {
      setState(() => _showTopIndicators = show);
    }
    return false;
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    // When Interactive Mode is active, a message is a command for the agent,
    // not a chat turn. When off, behaviour is exactly as before (additive).
    final interactive = ref.read(interactiveModeControllerProvider);
    if (interactive.active) {
      ref.read(interactiveModeControllerProvider.notifier).submitCommand(text);
      return;
    }
    ref.read(chatProvider.notifier).sendMessage(text);
  }

  /// Asks for a query, then routes it through the normal chat pipeline as an
  /// explicit web-search request. The menu item previously did nothing.
  Future<void> _promptWebSearch() async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ClayColors.warmGrey,
        title: Text(
          'Web search',
          style: GoogleFonts.outfit(
            color: ClayColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
          decoration: const InputDecoration(hintText: 'What should I look up?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(color: ClayColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(
              'Search',
              style: GoogleFonts.outfit(
                color: ClayColors.goldAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();

    final trimmed = query?.trim() ?? '';
    if (trimmed.isEmpty) return;
    _sendMessage('search the web for $trimmed');
  }

  @override
  Widget build(BuildContext context) {
    // Watch only the row count, not the whole chat state. Streaming a reply
    // changes message *content*, not the count, so this build no longer runs
    // once per token — the individual bubble handles its own update.
    final messageCount = ref.watch(chatMessageCountProvider);

    // Follow the streaming text without rebuilding this screen: the listener
    // fires on content changes but only touches the scroll position.
    ref.listen<int>(
      chatProvider.select(
        (s) =>
            s.messages.isEmpty ? 0 : (s.messages.last['content']?.length ?? 0),
      ),
      (_, _) => _followStreamToBottom(),
    );

    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final double topSpacerHeight = isKeyboardOpen
        ? 70.0
        : (_activeNudge != null ? 240.0 : 150.0);

    // Only scroll to bottom when new messages actually arrive (not on every rebuild)
    if (messageCount != _lastMessageCount) {
      _lastMessageCount = messageCount;
      _autoFollow = true;
      if (messageCount == 0) {
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
            const SnackBar(
              content: Text("New chat started"),
              duration: Duration(seconds: 1),
            ),
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
                  child: messageCount == 0
                      ? Center(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                    height: topSpacerHeight,
                                  ),
                                  const SizedBox(
                                    width: double.infinity,
                                    child: GreetingWidget(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: _handleScrollNotification,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.fromLTRB(
                              0,
                              _activeNudge != null ? 230.0 : 140.0,
                              0,
                              96,
                            ),
                            itemCount: messageCount,
                            // Each row subscribes to its own message, so the
                            // streaming bubble is the only one that rebuilds.
                            // ListView.builder already wraps rows in repaint
                            // boundaries, which keeps the claymorphic shadows
                            // of the other bubbles from re-rasterising.
                            itemBuilder: (context, index) {
                              return _ChatMessageItem(
                                key: ValueKey(index),
                                index: index,
                                onOptionSelected: _sendMessage,
                              );
                            },
                          ),
                        ),
                ),

                // Top scrim: the app bar is transparent and the list scrolls
                // behind it, so message text used to run straight through the
                // floating buttons. This fades content out underneath them.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height:
                      MediaQuery.of(context).padding.top + kToolbarHeight + 12,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            ClayColors.obsidianBg,
                            ClayColors.obsidianBg,
                            ClayColors.obsidianBg.withOpacity(0.0),
                          ],
                          stops: const [0.0, 0.65, 1.0],
                        ),
                      ),
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
                              onDismiss: () =>
                                  setState(() => _activeNudge = null),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Row(
                              children: [
                                Expanded(child: const ContextWindowIndicator()),
                                const SizedBox(width: 8),
                                const ConciseBadge(),
                              ],
                            ),
                          ),
                          // Interactive Agent Mode session banner. Renders
                          // nothing when the mode is off (additive).
                          const InteractiveSessionOverlay(),
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
                        _promptWebSearch();
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Thinking indicator — owns its own subscription so toggling it does
          // not rebuild the list or the input bar.
          const _ThinkingIndicator(),

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

/// A single row of the chat list.
///
/// Subscribes to just its own [ChatMessageView], which is parsed once per state
/// change in [chatMessageViewProvider]. Riverpod suppresses the notification
/// when the view is unchanged, so streaming a reply rebuilds only the bubble
/// being written.
class _ChatMessageItem extends ConsumerWidget {
  final int index;
  final ValueChanged<String> onOptionSelected;

  const _ChatMessageItem({
    super.key,
    required this.index,
    required this.onOptionSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(chatMessageViewProvider(index));

    final isUser = view.isUser;
    final isAutomation =
        view.isSystem && view.rawContent.startsWith('automation_triggered:');

    if (isAutomation) {
      final contentStr = view.rawContent.replaceFirst(
        'automation_triggered:',
        '',
      );
      final parts = contentStr.split(' - ');
      final ruleName = parts[0];
      final logs = parts.length > 1 ? parts.sublist(1).join(' - ') : '';
      final stepLogs = logs.split('\n');

      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
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
                    final stepResult = logParts.length > 1
                        ? logParts.sublist(1).join(': ')
                        : '';

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

    if (isUser) {
      return UserMessageBubble(content: view.content);
    }

    return AssistantMessageBubble(
      content: view.content,
      options: [
        for (final option in view.options)
          {'label': option.label, 'value': option.value},
      ],
      onOptionSelected: onOptionSelected,
      // Text selection installs gesture recognisers and a selection overlay
      // that get rebuilt with the text. Keep it off until the answer settles.
      selectable: !view.isStreaming,
      emailDraftCard: view.isEmailDraft
          ? EmailDraftCard(
              address: view.draftAddress!,
              subject: view.emailSubject,
              body: view.emailBody,
            )
          : null,
    );
  }
}

/// "Thinking..." pill shown while a turn is in flight.
class _ThinkingIndicator extends ConsumerWidget {
  const _ThinkingIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThinking = ref.watch(chatProvider.select((s) => s.isThinking));
    if (!isThinking) return const SizedBox.shrink();

    return Padding(
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
              // The spinner animates every frame; the boundary stops that
              // repaint from reaching the pill's gradient and shadows.
              const RepaintBoundary(
                child: SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: ClayColors.goldAccent,
                  ),
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
      border: Border.all(
        color: ClayColors.goldAccent.withOpacity(0.35),
        width: 1.2,
      ),
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.public_rounded,
                color: ClayColors.goldAccent,
              ),
              title: Text(
                'Web Search',
                style: GoogleFonts.outfit(
                  color: ClayColors.textDark,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'Search the internet for real-time info',
                style: GoogleFonts.outfit(
                  color: ClayColors.textMuted,
                  fontSize: 12,
                ),
              ),
              onTap: onWebSearch,
            ),
          ],
        ),
      ),
    );
  }
}
