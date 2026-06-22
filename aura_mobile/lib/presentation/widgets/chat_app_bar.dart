import 'package:flutter/material.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:aura_mobile/presentation/widgets/export_bottom_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';
import 'package:aura_mobile/presentation/providers/persona_provider.dart';
import 'package:aura_mobile/presentation/pages/persona_selector_screen.dart';
import 'package:aura_mobile/presentation/widgets/context_window_indicator.dart';

/// Extracted AppBar widget for ChatScreen — avoids rebuilding the entire chat
/// when only the model state or persona changes.
class ChatAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback onNewChat;

  const ChatAppBar({super.key, required this.onNewChat});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(personaProvider).activePersona;

    return AppBar(
      title: const _ModelTitleChip(),
      centerTitle: true,
      backgroundColor: Colors.transparent, // Glassmorphic/transparent integration
      elevation: 0,
      leadingWidth: 56,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12.0, top: 8.0, bottom: 8.0),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Builder(
            builder: (context) {
              return IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.menu, color: ClayColors.textDark, size: 20),
                onPressed: () => Scaffold.of(context).openDrawer(),
              );
            },
          ),
        ),
      ),
      actions: [
        // Persona Selector Button (Circular)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          child: Container(
            width: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(persona.icon, color: persona.accentColor, size: 20),
              tooltip: "AURA Persona",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PersonaSelectorScreen()),
                );
              },
            ),
          ),
        ),
        // Consolidated Options Button (Circular)
        Padding(
          padding: const EdgeInsets.only(right: 12.0, left: 4.0, top: 8.0, bottom: 8.0),
          child: Container(
            width: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                cardColor: ClayColors.warmGrey,
              ),
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert_rounded, color: ClayColors.textDark, size: 20),
                tooltip: "More Options",
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: ClayColors.goldAccent.withOpacity(0.2), width: 1),
                ),
                onSelected: (value) {
                  if (value == 'new_chat') {
                    onNewChat();
                  } else if (value == 'export') {
                    showExportBottomSheet(context);
                  }
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem<String>(
                    value: 'new_chat',
                    child: Row(
                      children: [
                        const Icon(Icons.add_rounded, color: ClayColors.goldAccent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'New Chat',
                          style: GoogleFonts.outfit(
                            color: ClayColors.textDark,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'export',
                    child: Row(
                      children: [
                        const Icon(Icons.ios_share_rounded, color: ClayColors.textDark, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Export Chat',
                          style: GoogleFonts.outfit(
                            color: ClayColors.textDark,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows the active model name or "Loading..." with a dropdown caret.
class _ModelTitleChip extends ConsumerWidget {
  const _ModelTitleChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelState = ref.watch(modelSelectorProvider);
    final isLoading = ref.watch(chatProvider.select((s) => s.isModelLoading));

    final isAppInitializing = modelState.activeModelId == null || isLoading;

    if (isAppInitializing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          "Loading...",
          style: GoogleFonts.outfit(
            color: ClayColors.textMuted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              activeModel.name,
              style: GoogleFonts.outfit(
                color: ClayColors.textDark,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: ClayColors.textMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// A premium, gradient-outlined Concise mode toggle badge.
class ConciseBadge extends ConsumerWidget {
  const ConciseBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConcise = ref.watch(conciseModeProvider);

    return GestureDetector(
      onTap: () {
        ref.read(conciseModeProvider.notifier).toggle();
      },
      child: Container(
        padding: const EdgeInsets.all(1.5), // Border outline thickness
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: isConcise
                ? [
                    const Color(0xFF8FD3F4), // Light blue
                    const Color(0xFFFF9E80), // Orange/peach
                    const Color(0xFFF5576C), // Pink
                  ]
                : [
                    Colors.black.withOpacity(0.08),
                    Colors.black.withOpacity(0.08),
                  ],
          ),
          boxShadow: isConcise
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF9E80).withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 1,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isConcise)
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFF5CA9E5),
                      Color(0xFFE25F8E),
                    ],
                  ).createShader(bounds),
                  child: const Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(
                  Icons.star_outline_rounded,
                  size: 14,
                  color: ClayColors.textMuted,
                ),
              const SizedBox(width: 6),
              Text(
                'Concise',
                style: GoogleFonts.outfit(
                  color: isConcise ? ClayColors.goldAccent : ClayColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
