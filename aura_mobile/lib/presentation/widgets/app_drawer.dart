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
import 'package:aura_mobile/presentation/pages/persona_selector_screen.dart';
import 'package:aura_mobile/presentation/providers/persona_provider.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userProvider);

    return Drawer(
      backgroundColor: const Color(0xFF0f0f13),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // ── Header: User + New Chat ──
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFc69c3a),
                    child: Text(
                      userState.value?.substring(0, 1).toUpperCase() ?? "U",
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      userState.value ?? "User",
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _MiniIconButton(
                    icon: Icons.add,
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
                    icon: Icons.school_rounded,
                    label: 'Study',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const StudyDashboardScreen()));
                    },
                  ),
                  const SizedBox(width: 10),
                  _QuickAction(
                    icon: Icons.document_scanner_rounded,
                    label: 'Scan',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScanScreen()));
                    },
                  ),
                  const SizedBox(width: 10),
                  _QuickAction(
                    icon: Icons.psychology_rounded,
                    label: 'Model',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ModelSelectorScreen()));
                    },
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── Chat History ──
              Text(
                'Recent',
                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: Consumer(
                  builder: (context, ref, child) {
                    final historyAsync = ref.watch(chatHistoryProvider);

                    return historyAsync.when(
                      data: (sessions) {
                        if (sessions.isEmpty) {
                          return Center(
                            child: Text(
                              "No chats yet",
                              style: GoogleFonts.outfit(color: Colors.white24, fontSize: 13),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: sessions.length,
                          separatorBuilder: (context2, index2) => const SizedBox(height: 2),
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
                        child: CircularProgressIndicator(color: Color(0xFFc69c3a), strokeWidth: 2),
                      ),
                      error: (err, stack) => Center(
                        child: Text("Error loading history", style: GoogleFonts.outfit(color: Colors.red, fontSize: 12)),
                      ),
                    );
                  },
                ),
              ),

              // ── Bottom Section ──
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white10)),
                ),
                child: Column(
                  children: [
                    // Voice Assistant
                    _DrawerTile(
                      icon: Icons.mic_rounded,
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
                                activeThumbColor: const Color(0xFFc69c3a),
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

                    // Settings
                    _DrawerTile(
                      icon: Icons.settings_rounded,
                      title: 'Settings',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceAssistantSettingsPage()));
                      },
                    ),
                  ],
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
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFFc69c3a), size: 20),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.outfit(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date,
                    style: GoogleFonts.outfit(color: Colors.white24, fontSize: 10),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: Colors.white24),
              ),
            ),
          ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            if (icon != null)
              Icon(icon, color: iconColor ?? Colors.white54, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            if (trailing != null) trailing!
            else if (onTap != null) const Icon(Icons.chevron_right, size: 16, color: Colors.white24),
          ],
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
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white10),
          ),
          child: Icon(icon, color: Colors.white60, size: 16),
        ),
      ),
    );
  }
}
