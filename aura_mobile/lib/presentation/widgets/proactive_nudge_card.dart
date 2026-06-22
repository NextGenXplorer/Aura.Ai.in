import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/core/services/proactive_engine.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: color.withOpacity(0.18),
                    width: 1.5,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onAction,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          // Icon container (soft circular background matching type color)
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withOpacity(0.12),
                            ),
                            child: Center(
                              child: Icon(nudge.icon, color: color, size: 20),
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Content
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  nudge.title,
                                  style: GoogleFonts.outfit(
                                    color: ClayColors.textDark,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  nudge.message,
                                  style: GoogleFonts.outfit(
                                    color: ClayColors.textMuted,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Action hint or close button
                          if (nudge.action != NudgeAction.dismiss)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: color.withOpacity(0.25), width: 1.0),
                              ),
                              child: Text(
                                _actionLabel(nudge.action),
                                style: GoogleFonts.outfit(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.close, color: ClayColors.textHint, size: 18),
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
            ),
          ),
        ),
      ),
    );
  }

  Color _nudgeColor(NudgeType type) {
    switch (type) {
      case NudgeType.gentle:
        return const Color(0xFFC69C3A); // Curated Warm Gold
      case NudgeType.suggestion:
        return const Color(0xFF2E6B9E); // Steel/Warm Blue
      case NudgeType.important:
        return const Color(0xFFD85A38); // Burnt Orange
      case NudgeType.urgent:
        return const Color(0xFFB83A3A); // Crimson/Deep Red
      case NudgeType.celebration:
        return const Color(0xFF3B8A5A); // Sage/Forest Green
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
