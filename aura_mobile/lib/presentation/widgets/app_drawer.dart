import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/presentation/providers/user_provider.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/presentation/providers/chat_history_provider.dart';
import 'package:aura_mobile/core/services/voice_assistant_service.dart';
import 'package:aura_mobile/presentation/pages/model_selector_screen.dart';
import 'package:aura_mobile/presentation/pages/voice_assistant_settings_page.dart';
import 'package:intl/intl.dart';
import 'package:aura_mobile/core/providers/repository_providers.dart';
import 'package:aura_mobile/presentation/pages/study_dashboard_screen.dart';
import 'package:aura_mobile/presentation/pages/camera_scan_screen.dart';
import 'package:aura_mobile/presentation/pages/image_studio_screen.dart';
import 'package:aura_mobile/presentation/pages/persona_selector_screen.dart';
import 'package:aura_mobile/presentation/providers/persona_provider.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:aura_mobile/presentation/screens/automation_management_screen.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userProvider);

    return Drawer(
      backgroundColor: ClayColors.obsidianBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // ── Header: User + New Chat ──
              Row(
                children: [
                  ClayContainer(
                    width: 38,
                    height: 38,
                    borderRadius: 19,
                    depth: 4.0,
                    baseColor: ClayColors.goldAccent.withOpacity(0.12),
                    highlightColor: ClayColors.highlight,
                    shadowColor: ClayColors.shadow,
                    child: Center(
                      child: Text(
                        userState.value?.substring(0, 1).toUpperCase() ?? "U",
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: ClayColors.goldAccent,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      userState.value ?? "User",
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: ClayColors.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _MiniIconButton(
                    icon: Icons.add_rounded,
                    onTap: () {
                      ref.read(chatProvider.notifier).clearChat();
                      Navigator.pop(context);
                    },
                    tooltip: 'New Chat',
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Quick Actions Row ──
              Row(
                children: [
                  _QuickAction(
                    icon: Icons.school_outlined,
                    label: 'Study',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const StudyDashboardScreen()));
                    },
                  ),
                  const SizedBox(width: 12),
                  _QuickAction(
                    icon: Icons.document_scanner_outlined,
                    label: 'Scan',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScanScreen()));
                    },
                  ),
                  const SizedBox(width: 12),
                  _QuickAction(
                    icon: Icons.psychology_outlined,
                    label: 'Model',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ModelSelectorScreen()));
                    },
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── AI Image Studio (free, online, no key) ──
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ImageStudioScreen()));
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ClayColors.goldAccent.withOpacity(0.18),
                        ClayColors.goldAccent.withOpacity(0.06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ClayColors.goldAccent.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: ClayColors.goldAccent, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AI Image Studio',
                                style: GoogleFonts.outfit(
                                    color: ClayColors.textDark,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold)),
                            Text('Generate images — free, no account',
                                style: GoogleFonts.outfit(
                                    color: ClayColors.textMuted, fontSize: 11)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          color: ClayColors.goldAccent, size: 14),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // ── Chat History ──
              Text(
                'Recent',
                style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: ClayContainer(
                  borderRadius: 20,
                  isInset: true,
                  depth: 4.0,
                  baseColor: const Color(0xFFE5E2DA),
                  highlightColor: const Color(0xFFF7F4EF),
                  shadowColor: const Color(0xFFCBC7BE),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Consumer(
                    builder: (context, ref, child) {
                      final historyAsync = ref.watch(chatHistoryProvider);

                      return historyAsync.when(
                        data: (sessions) {
                          if (sessions.isEmpty) {
                            return Center(
                              child: Text(
                                "No chats yet",
                                style: GoogleFonts.outfit(color: ClayColors.textHint, fontSize: 13),
                              ),
                            );
                          }
                          return ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: sessions.length,
                            itemBuilder: (context, index) {
                              final session = sessions[index];
                              return _ChatHistoryTile(
                                title: session.title,
                                date: _formatDate(session.lastModified),
                                onTap: () {
                                  ref.read(chatProvider.notifier).loadSession(session);
                                  Navigator.pop(context);
                                },
                                onDelete: () async {
                                  final repo = ref.read(chatHistoryRepositoryProvider);
                                  await repo.deleteSession(session.id);
                                  ref.invalidate(chatHistoryProvider);
                                },
                              );
                            },
                          );
                        },
                        loading: () => const Center(
                          child: CircularProgressIndicator(color: ClayColors.goldAccent, strokeWidth: 2),
                        ),
                        error: (err, stack) => Center(
                          child: Text("Error loading history", style: GoogleFonts.outfit(color: ClayColors.redAccent, fontSize: 12)),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── Bottom Section ──
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: ClayContainer(
                  borderRadius: 24,
                  depth: 5.0,
                  baseColor: ClayColors.warmGrey,
                  highlightColor: ClayColors.highlight,
                  shadowColor: ClayColors.shadow,
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      // Voice Assistant
                      _DrawerTile(
                        icon: Icons.mic_none_rounded,
                        title: 'Voice Assistant',
                        trailing: StatefulBuilder(
                          builder: (context, setState) {
                            VoiceAssistantService.ensureSynced().then((_) {
                              if (context.mounted) setState(() {});
                            });
                            return SizedBox(
                              height: 28,
                              width: 44,
                              child: FittedBox(
                                child: Switch(
                                  value: VoiceAssistantService.isRunning,
                                  activeColor: ClayColors.goldAccent,
                                  activeTrackColor: ClayColors.goldAccent.withOpacity(0.3),
                                  inactiveThumbColor: ClayColors.textHint,
                                  inactiveTrackColor: Colors.black.withOpacity(0.06),
                                  onChanged: (value) async {
                                    if (value) {
                                      await VoiceAssistantService.startAssistant();
                                    } else {
                                      await VoiceAssistantService.stopAssistant();
                                    }
                                    setState(() {});
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Persona
                      Consumer(
                        builder: (context, ref, _) {
                          final persona = ref.watch(personaProvider).activePersona;
                          return _DrawerTile(
                            icon: persona.icon,
                            iconColor: persona.accentColor,
                            title: persona.name,
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonaSelectorScreen()));
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 4),

                      // Automation Rules
                      _DrawerTile(
                        icon: Icons.auto_awesome_outlined,
                        title: 'Automation Rules',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const AutomationManagementScreen()));
                        },
                      ),
                      const SizedBox(height: 4),

                      // Settings
                      _DrawerTile(
                        icon: Icons.settings_outlined,
                        title: 'Settings',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceAssistantSettingsPage()));
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return DateFormat('h:mm a').format(date);
    } else if (difference.inDays < 7) {
      return DateFormat('E').format(date);
    } else {
      return DateFormat('MMM d').format(date);
    }
  }
}

// ── Minimal Quick Action Button ──
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ClayButton(
        onTap: onTap,
        borderRadius: 16,
        depth: 5.0,
        baseColor: ClayColors.warmGrey,
        highlightColor: ClayColors.highlight,
        shadowColor: ClayColors.shadow,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: ClayColors.goldAccent, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chat History Tile ──
class _ChatHistoryTile extends StatelessWidget {
  final String title;
  final String date;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ChatHistoryTile({
    required this.title,
    required this.date,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6.0),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.black.withOpacity(0.015),
          width: 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        date,
                        style: GoogleFonts.outfit(color: ClayColors.textMuted.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.04),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 13, color: ClayColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bottom Drawer Tile ──
class _DrawerTile extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _DrawerTile({this.icon, this.iconColor, required this.title, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              if (icon != null)
                Icon(icon, color: iconColor ?? ClayColors.textMuted, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              if (trailing != null) trailing!
              else if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18, color: ClayColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Small icon button for header ──
class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _MiniIconButton({required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: ClayButton(
        onTap: onTap,
        borderRadius: 10,
        depth: 4.0,
        baseColor: ClayColors.warmGrey,
        highlightColor: ClayColors.highlight,
        shadowColor: ClayColors.shadow,
        padding: EdgeInsets.zero,
        width: 36,
        height: 36,
        child: Center(child: Icon(icon, color: ClayColors.textDark, size: 18)),
      ),
    );
  }
}
