import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';
import 'package:aura_mobile/presentation/providers/persona_provider.dart';
import 'package:aura_mobile/presentation/pages/persona_selector_screen.dart';

/// Extracted AppBar widget for ChatScreen — avoids rebuilding the entire chat
/// when only the model state or persona changes.
class ChatAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback onNewChat;

  const ChatAppBar({super.key, required this.onNewChat});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      title: const _ModelTitleChip(),
      centerTitle: true,
      backgroundColor: const Color(0xFF0a0a0c).withOpacity(0.85),
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: const Color(0xFF1a1a20),
          child: Builder(
            builder: (context) {
              return IconButton(
                icon: const Icon(Icons.menu, color: Colors.white70, size: 20),
                onPressed: () => Scaffold.of(context).openDrawer(),
              );
            },
          ),
        ),
      ),
      // Replaced expensive BackdropFilter with a simple gradient container
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0a0a0c),
              Color(0xDD0a0a0c),
            ],
          ),
        ),
      ),
      actions: [
        const _PersonaChip(),
        Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: CircleAvatar(
            backgroundColor: const Color(0xFF1a1a20),
            child: IconButton(
              icon: const Icon(Icons.add, color: Colors.white70, size: 20),
              tooltip: "New Chat",
              onPressed: onNewChat,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows the active model name or "Loading..." — isolated rebuild scope.
class _ModelTitleChip extends ConsumerWidget {
  const _ModelTitleChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelState = ref.watch(modelSelectorProvider);
    final isLoading = ref.watch(chatProvider.select((s) => s.isModelLoading));

    final isAppInitializing = modelState.activeModelId == null || isLoading;

    if (isAppInitializing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Text(
          "Loading...",
          style: GoogleFonts.outfit(
            color: Colors.white54,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final activeModel = modelState.availableModels.firstWhere(
      (m) => m.id == modelState.activeModelId,
      orElse: () => modelState.availableModels.first,
    );

    return GestureDetector(
      onTap: () => Scaffold.of(context).openDrawer(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Text(
          activeModel.name,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Persona selector chip — isolated so persona changes don't rebuild the whole bar.
class _PersonaChip extends ConsumerWidget {
  const _PersonaChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(personaProvider).activePersona;
    return Padding(
      padding: const EdgeInsets.only(right: 4.0),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PersonaSelectorScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: persona.accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: persona.accentColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(persona.icon, color: persona.accentColor, size: 14),
              const SizedBox(width: 4),
              Text(
                persona.name,
                style: GoogleFonts.outfit(
                  color: persona.accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
