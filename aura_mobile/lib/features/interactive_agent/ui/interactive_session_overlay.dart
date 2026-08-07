/// The session overlay: mode-active indicator, plan summary, per-step narration
/// with position, an always-reachable abort, and the confirmation gate sheet.
///
/// Watches only the narration / step-index / gate slices so a step change
/// repaints this compact widget, not the chat tree (Req 13.1). Decorated
/// containers stay inside a RepaintBoundary.
///
/// Feature: interactive-agent-mode (Tasks 11.2, 11.3)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../presentation/widgets/clay_components.dart';
import '../interactive_agent_providers.dart';
import '../interactive_mode_controller.dart';
import '../models/session_state.dart';

/// A slim banner shown while Interactive Mode is active. Renders nothing when
/// the mode is off, so it is safe to drop into the chat scaffold unconditionally.
class InteractiveSessionOverlay extends ConsumerWidget {
  const InteractiveSessionOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      interactiveModeControllerProvider.select((s) => s.active),
    );
    if (!active) return const SizedBox.shrink();

    // Present the gate sheet whenever a gate appears.
    ref.listen(
      interactiveModeControllerProvider.select((s) => s.gate),
      (prev, gate) {
        if (gate != null && prev == null) {
          _showGateSheet(context, ref, gate);
        }
      },
    );

    return const RepaintBoundary(child: _OverlayBody());
  }

  void _showGateSheet(BuildContext context, WidgetRef ref, PendingGate gate) {
    final controller = ref.read(interactiveModeControllerProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _GateSheet(gate: gate, controller: controller),
    ).then((_) {
      // If the sheet was dismissed without an explicit answer, treat as decline.
      final stillPending =
          ref.read(interactiveModeControllerProvider).gate != null;
      if (stillPending) controller.resolveGate(false);
    });
  }
}

class _OverlayBody extends ConsumerWidget {
  const _OverlayBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(
      interactiveModeControllerProvider.select((s) => s.phase),
    );
    final narration = ref.watch(
      interactiveModeControllerProvider.select((s) => s.narration),
    );
    final plan = ref.watch(
      interactiveModeControllerProvider.select((s) => s.plan),
    );
    final index = ref.watch(
      interactiveModeControllerProvider.select((s) => s.currentStepIndex),
    );
    final controller = ref.read(interactiveModeControllerProvider.notifier);

    final total = plan?.steps.length ?? 0;
    final running = phase == RunPhase.executing ||
        phase == RunPhase.planning ||
        phase == RunPhase.settling ||
        phase == RunPhase.recovering ||
        phase == RunPhase.awaitingPlanAck ||
        phase == RunPhase.gated;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ClayColors.goldHighlight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClayColors.goldAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.smart_toy_outlined,
              size: 18, color: ClayColors.goldAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title(phase, index, total),
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ClayColors.goldAccent,
                  ),
                ),
                if (narration != null)
                  Text(
                    narration,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: ClayColors.textDark,
                    ),
                  ),
              ],
            ),
          ),
          if (running)
            TextButton(
              onPressed: controller.abort,
              style: TextButton.styleFrom(
                foregroundColor: ClayColors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                'Stop',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            )
          else
            IconButton(
              onPressed: () => controller.exitSession(),
              icon: const Icon(Icons.close, size: 18),
              color: ClayColors.textMuted,
              tooltip: 'Exit Interactive Mode',
            ),
        ],
      ),
    );
  }

  String _title(RunPhase phase, int index, int total) {
    switch (phase) {
      case RunPhase.planning:
        return 'PLANNING';
      case RunPhase.awaitingPlanAck:
        return 'REVIEW PLAN';
      case RunPhase.gated:
        return 'NEEDS CONFIRMATION';
      case RunPhase.executing:
      case RunPhase.settling:
      case RunPhase.recovering:
        return total > 0 ? 'STEP ${index + 1} OF $total' : 'RUNNING';
      case RunPhase.paused:
        return 'PAUSED';
      case RunPhase.completed:
        return 'DONE';
      case RunPhase.failed:
        return 'STOPPED';
      case RunPhase.aborted:
        return 'STOPPED';
      case RunPhase.idle:
        return 'INTERACTIVE MODE ON';
    }
  }
}

class _GateSheet extends StatelessWidget {
  final PendingGate gate;
  final InteractiveModeController controller;

  const _GateSheet({required this.gate, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ClayColors.obsidianBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ClayColors.shadow,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                gate.isFirstUiActionGate
                    ? Icons.touch_app_outlined
                    : Icons.warning_amber_rounded,
                color: ClayColors.goldAccent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  gate.isFirstUiActionGate
                      ? 'Let AURA operate this app?'
                      : 'Confirm this action',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: ClayColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ClayColors.warmGrey,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              gate.effectSummary,
              style: GoogleFonts.outfit(
                fontSize: 14,
                height: 1.4,
                color: ClayColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    controller.resolveGate(false);
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.outfit(color: ClayColors.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ClayColors.goldAccent,
                  ),
                  onPressed: () {
                    controller.resolveGate(true);
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Confirm',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
