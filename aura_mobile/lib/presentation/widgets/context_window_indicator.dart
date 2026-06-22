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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFECE6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Progress bar
          Expanded(
            flex: 3,
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
          const SizedBox(width: 10),

          // Token count label
          Text(
            '${state.estimatedTokens} / ${state.maxTokens} tokens',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          const SizedBox(width: 10),

          // Turn counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${state.currentTurns} / ${state.maxTurns} turns',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
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
