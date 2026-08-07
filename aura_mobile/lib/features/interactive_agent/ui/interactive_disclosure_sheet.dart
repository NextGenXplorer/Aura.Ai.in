/// Disclosure shown before Interactive Mode is enabled, and the mode toggle
/// tile with autonomy posture selection.
///
/// Feature: interactive-agent-mode (Task 11.1)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../presentation/widgets/clay_components.dart';
import '../interactive_agent_providers.dart';
import '../interactive_mode_controller.dart';
import '../models/session_state.dart';

/// The disclosure text, reusable so it can be re-read from settings (Req 2.5).
const String kInteractiveDisclosure =
    'Interactive Mode lets AURA carry out multi-step commands across your apps '
    '(for example: "open WhatsApp and message John").\n\n'
    'To do this AURA uses the Accessibility service to:\n'
    '• read what is on screen to know where it is, and\n'
    '• tap, type, and scroll on your behalf when there is no direct shortcut.\n\n'
    'AURA prefers instant app shortcuts and only drives the screen when needed. '
    'It shows each step before doing it, always asks before anything '
    'irreversible (sending, calling, paying, deleting), and you can stop it at '
    'any time.\n\n'
    'It never runs on its own — every command is started by you. Screen contents '
    'stay on your device unless you have selected an online model. You can turn '
    'this off any time in Android accessibility settings.';

/// Shows the disclosure. Returns true if the user accepted and should be sent to
/// accessibility settings (Req 2.1, 2.2).
Future<bool> showInteractiveDisclosure(BuildContext context) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _DisclosureSheet(),
  );
  return accepted ?? false;
}

class _DisclosureSheet extends StatelessWidget {
  const _DisclosureSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: ClayColors.obsidianBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
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
                const Icon(Icons.smart_toy_outlined,
                    color: ClayColors.goldAccent),
                const SizedBox(width: 10),
                Text(
                  'Enable Interactive Mode',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: ClayColors.textDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: Text(
                  kInteractiveDisclosure,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    height: 1.5,
                    color: ClayColors.textMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      'Not now',
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
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      'Continue',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A settings tile that toggles Interactive Mode and exposes the autonomy
/// posture. Drop into any settings list.
class InteractiveModeTile extends ConsumerWidget {
  const InteractiveModeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(interactiveModeControllerProvider);
    final controller = ref.read(interactiveModeControllerProvider.notifier);

    return Column(
      children: [
        SwitchListTile(
          value: state.active,
          activeThumbColor: ClayColors.goldAccent,
          title: Text(
            'Interactive Mode',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              color: ClayColors.textDark,
            ),
          ),
          subtitle: Text(
            state.active
                ? 'On — AURA can carry out multi-step commands'
                : 'Off — tap to enable multi-step app control',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: ClayColors.textMuted,
            ),
          ),
          onChanged: (want) => _onToggle(context, controller, want),
        ),
        if (state.active) _PostureSelector(state: state, controller: controller),
        if (state.active)
          SwitchListTile(
            value: state.spokenNarration,
            activeThumbColor: ClayColors.goldAccent,
            title: Text(
              'Speak each step',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                color: ClayColors.textDark,
              ),
            ),
            subtitle: Text(
              'AURA reads out what it is doing (confirmations still need a tap)',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: ClayColors.textMuted,
              ),
            ),
            onChanged: controller.setSpokenNarration,
          ),
      ],
    );
  }

  Future<void> _onToggle(
    BuildContext context,
    InteractiveModeController controller,
    bool want,
  ) async {
    if (!want) {
      await controller.exitSession();
      return;
    }
    final entered = await controller.enterSession();
    if (entered || !context.mounted) return;

    // Surface could not enable → accessibility service is off. Disclose, then
    // route to settings (Req 2.1, 2.2, 2.3).
    final accepted = await showInteractiveDisclosure(context);
    if (accepted && context.mounted) {
      await controller.openAccessibilitySettings();
    }
  }
}

class _PostureSelector extends StatelessWidget {
  final InteractiveSessionState state;
  final InteractiveModeController controller;

  const _PostureSelector({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Autonomy',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ClayColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          SegmentedButton<AutonomyPosture>(
            segments: const [
              ButtonSegment(
                value: AutonomyPosture.guided,
                label: Text('Guided'),
                icon: Icon(Icons.verified_user_outlined),
              ),
              ButtonSegment(
                value: AutonomyPosture.continuous,
                label: Text('Continuous'),
                icon: Icon(Icons.fast_forward),
              ),
            ],
            selected: {state.posture},
            onSelectionChanged: (sel) =>
                _onPosture(context, sel.first),
          ),
          if (state.posture == AutonomyPosture.continuous)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Continuous mode is not permitted under Google Play policy and '
                'is intended for sideloaded builds. Payments, purchases and '
                'security changes are still always confirmed.',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: ClayColors.orangeAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onPosture(BuildContext context, AutonomyPosture posture) {
    controller.setPosture(posture);
  }
}
