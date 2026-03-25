import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/core/services/proactive_engine.dart';

/// A dismissible card that appears at the top of the chat screen
/// when the Proactive Engine has a nudge for the user.
class ProactiveNudgeCard extends StatelessWidget {
  final ProactiveNudge nudge;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  const ProactiveNudgeCard({
    super.key,
    required this.nudge,
    required this.onAction,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final color = _nudgeColor(nudge.type);

    return Dismissible(
      key: ValueKey('nudge_${nudge.title}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => onDismiss(),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.12),
              color.withValues(alpha: 0.04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(nudge.icon, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nudge.title,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          nudge.message,
                          style: GoogleFonts.outfit(
                            color: Colors.white54,
                            fontSize: 12,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Action hint
                  if (nudge.action != NudgeAction.dismiss)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _actionLabel(nudge.action),
                        style: GoogleFonts.outfit(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.white24, size: 18),
                      onPressed: onDismiss,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _nudgeColor(NudgeType type) {
    switch (type) {
      case NudgeType.gentle:
        return const Color(0xFFc69c3a);
      case NudgeType.suggestion:
        return Colors.blueAccent;
      case NudgeType.important:
        return Colors.orangeAccent;
      case NudgeType.urgent:
        return Colors.redAccent;
      case NudgeType.celebration:
        return Colors.greenAccent;
    }
  }

  String _actionLabel(NudgeAction action) {
    switch (action) {
      case NudgeAction.openChat:
        return 'Chat';
      case NudgeAction.openStudy:
        return 'Study';
      case NudgeAction.startReview:
        return 'Review';
      case NudgeAction.startQuiz:
        return 'Quiz';
      case NudgeAction.openScan:
        return 'Scan';
      case NudgeAction.dismiss:
        return '';
    }
  }
}
