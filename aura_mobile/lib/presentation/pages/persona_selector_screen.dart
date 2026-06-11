import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/domain/entities/persona.dart';
import 'package:aura_mobile/presentation/providers/persona_provider.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';

class PersonaSelectorScreen extends ConsumerWidget {
  const PersonaSelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personaState = ref.watch(personaProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0c),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0c),
        title: Text(
          'AI Personas',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFFc69c3a)),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose a personality for AURA',
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            'Each persona changes how AURA responds — from casual friend to strict professor.',
            style: GoogleFonts.outfit(color: Colors.white30, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 20),

          ...personaState.allPersonas.map((persona) {
            final isActive = persona.id == personaState.activePersona.id;
            return _personaCard(context, ref, persona, isActive);
          }),
        ],
      ),
    );
  }

  Widget _personaCard(BuildContext context, WidgetRef ref, Persona persona, bool isActive) {
    return GestureDetector(
      onTap: () {
        // Only act if switching to a different persona
        if (!isActive) {
          ref.read(personaProvider.notifier).setPersona(persona.id);
          // Start a fresh chat so old conversation context doesn't bleed into new persona
          ref.read(chatProvider.notifier).clearChat();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Switched to ${persona.name} — new chat started'),
              duration: const Duration(seconds: 2),
              backgroundColor: persona.accentColor.withValues(alpha: 0.8),
            ),
          );
          // Go back to chat screen
          Navigator.pop(context);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive
              ? persona.accentColor.withValues(alpha: 0.1)
              : const Color(0xFF1a1a20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? persona.accentColor : Colors.white10,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icon avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: persona.accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: persona.accentColor.withValues(alpha: 0.25)),
              ),
              child: Center(
                child: Icon(
                  persona.icon,
                  color: persona.accentColor,
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
                          color: isActive ? persona.accentColor : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: persona.accentColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'ACTIVE',
                            style: GoogleFonts.outfit(
                              color: persona.accentColor,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    persona.description,
                    style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  // Preview greeting
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '"${persona.greeting}"',
                      style: GoogleFonts.outfit(
                        color: Colors.white24,
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

            if (isActive)
              Icon(Icons.check_circle, color: persona.accentColor, size: 22)
            else
              const Icon(Icons.circle_outlined, color: Colors.white10, size: 22),
          ],
        ),
      ),
    );
  }
}
