/// Settings screen hosting the Interactive Mode toggle, autonomy posture, and
/// a re-readable disclosure (Req 2.4, 2.5).
///
/// Feature: interactive-agent-mode (Task 11.1)
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../presentation/widgets/clay_components.dart';
import 'interactive_disclosure_sheet.dart';

class InteractiveModeScreen extends StatelessWidget {
  const InteractiveModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: ClayColors.obsidianBg,
        elevation: 0,
        title: Text(
          'Interactive Mode',
          style: GoogleFonts.outfit(
            color: ClayColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: ClayColors.textDark),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Let AURA carry out multi-step commands across your apps, one '
              'confirmed step at a time.',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: ClayColors.textMuted,
              ),
            ),
          ),
          const InteractiveModeTile(),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline, color: ClayColors.textMuted),
            title: Text(
              'What Interactive Mode can do',
              style: GoogleFonts.outfit(color: ClayColors.textDark),
            ),
            subtitle: Text(
              'Read the full disclosure',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: ClayColors.textMuted,
              ),
            ),
            onTap: () => showInteractiveDisclosure(context),
          ),
        ],
      ),
    );
  }
}
