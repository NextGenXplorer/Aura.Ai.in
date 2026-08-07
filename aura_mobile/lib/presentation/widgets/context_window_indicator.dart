import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/presentation/providers/context_window_provider.dart';

/// A compact horizontal bar that displays context window token usage
/// and conversation turn count. Sits below the app bar in the chat UI.
class ContextWindowIndicator extends ConsumerWidget {
  const ContextWindowIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(contextWindowProvider);

    final color = _colorForState(state.colorState);
    final ratio = state.maxTokens > 0
        ? (state.estimatedTokens / state.maxTokens).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFECE6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Progress bar
          Expanded(
            flex: 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: color.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Token count label. Flexible + ellipsis so a large context window
          // (e.g. 1M-token models) can never overflow the row.
          Flexible(
            child: Text(
              '${_formatCount(state.estimatedTokens)} / '
              '${_formatCount(state.maxTokens)} tokens',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Turn counter
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${state.currentTurns} / ${state.maxTurns} turns',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Abbreviates large counts so the label stays compact: 54 -> "54",
  /// 12_400 -> "12.4K", 1_000_000 -> "1M".
  static String _formatCount(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) {
      final thousands = value / 1000;
      return thousands >= 100
          ? '${thousands.round()}K'
          : '${thousands.toStringAsFixed(1)}K';
    }
    final millions = value / 1000000;
    return millions == millions.roundToDouble()
        ? '${millions.round()}M'
        : '${millions.toStringAsFixed(1)}M';
  }

  /// Maps the [ContextWindowColorState] to the appropriate display color.
  Color _colorForState(ContextWindowColorState colorState) {
    switch (colorState) {
      case ContextWindowColorState.normal:
        return const Color(0xFFB3862B); // App primary gold
      case ContextWindowColorState.warning:
        return Colors.amber;
      case ContextWindowColorState.critical:
        return Colors.red;
    }
  }
}
