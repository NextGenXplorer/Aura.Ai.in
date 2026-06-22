import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/domain/entities/persona.dart';
import 'package:aura_mobile/presentation/providers/persona_provider.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

class PersonaSelectorScreen extends ConsumerWidget {
  const PersonaSelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personaState = ref.watch(personaProvider);

    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'AI Personas',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: ClayColors.goldAccent),
        ),
        iconTheme: const IconThemeData(color: ClayColors.textDark),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: ClayColors.textDark, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Choose a personality for AURA',
            style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Each persona changes how AURA responds — from casual friend to strict professor.',
            style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),

          ...personaState.allPersonas.map((persona) {
            final isActive = persona.id == personaState.activePersona.id;
            return _personaCard(context, ref, persona, isActive);
          }),
        ],
      ),
    );
  }

  Widget _personaCard(BuildContext context, WidgetRef ref, Persona persona, bool isActive) {
    final accent = persona.accentColor;
    final double depth = isActive ? 3.0 : 6.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: ClayButton(
        onTap: isActive
            ? null
            : () {
                ref.read(personaProvider.notifier).setPersona(persona.id);
                // Start a fresh chat so old conversation context doesn't bleed into new persona
                ref.read(chatProvider.notifier).clearChat();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Switched to ${persona.name} — new chat started',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    duration: const Duration(seconds: 2),
                    backgroundColor: accent.withOpacity(0.8),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                // Go back to chat screen
                Navigator.pop(context);
              },
        borderRadius: 24,
        depth: depth,
        baseColor: ClayColors.warmGrey,
        highlightColor: isActive ? accent.withOpacity(0.25) : ClayColors.highlight,
        shadowColor: isActive ? accent.withOpacity(0.12) : ClayColors.shadow,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon avatar
            ClayContainer(
              width: 48,
              height: 48,
              borderRadius: 14,
              isInset: true,
              depth: 4.0,
              baseColor: const Color(0xFFE5E2DA),
              highlightColor: const Color(0xFFF7F4EF),
              shadowColor: const Color(0xFFCBC7BE),
              child: Center(
                child: Icon(
                  persona.icon,
                  color: accent,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        persona.name,
                        style: GoogleFonts.outfit(
                          color: isActive ? accent : ClayColors.textDark,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: accent.withOpacity(0.3), width: 1),
                          ),
                          child: Text(
                            'ACTIVE',
                            style: GoogleFonts.outfit(
                              color: accent,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    persona.description,
                    style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  // Preview greeting
                  ClayContainer(
                    isInset: true,
                    borderRadius: 10,
                    depth: 2.0,
                    baseColor: const Color(0xFFE5E2DA),
                    highlightColor: const Color(0xFFF7F4EF),
                    shadowColor: const Color(0xFFCBC7BE),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      '"${persona.greeting}"',
                      style: GoogleFonts.outfit(
                        color: ClayColors.textMuted,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (isActive)
              Icon(Icons.check_circle_rounded, color: accent, size: 22)
            else
              Icon(Icons.circle_outlined, color: Colors.black.withOpacity(0.15), size: 22),
          ],
        ),
      ),
    );
  }
}
