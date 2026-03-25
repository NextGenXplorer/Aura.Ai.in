import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/presentation/providers/user_provider.dart';
import 'package:aura_mobile/presentation/providers/persona_provider.dart';

class GreetingWidget extends ConsumerWidget {
  const GreetingWidget({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  String _getEmoji() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '🌙';
    if (hour < 18) return '☀️';
    return '🌙';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userProvider);

    return userState.when(
      data: (name) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(
                  text: "${_getGreeting()}, ",
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                  ),
                ),
                TextSpan(
                  text: "$name! ",
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                 TextSpan(
                  text: _getEmoji(),
                  style: const TextStyle(fontSize: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Consumer(
            builder: (context, ref, _) {
              final persona = ref.watch(personaProvider).activePersona;
              return Text(
                persona.greeting,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                  color: persona.accentColor.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
              );
            },
          ),
        ],
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
