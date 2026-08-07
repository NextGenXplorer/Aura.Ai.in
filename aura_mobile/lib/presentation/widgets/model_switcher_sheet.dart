import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/core/services/llm_selection_store.dart';
import 'package:aura_mobile/presentation/pages/online_provider_settings_screen.dart';
import 'package:aura_mobile/presentation/pages/model_selector_screen.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

/// Lets the user switch between downloaded on-device models and the configured
/// online provider model without leaving chat.
Future<void> showModelSwitcherSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: ClayColors.obsidianBg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _ModelSwitcherSheet(),
  );
}

class _ModelSwitcherSheet extends ConsumerStatefulWidget {
  const _ModelSwitcherSheet();

  @override
  ConsumerState<_ModelSwitcherSheet> createState() =>
      _ModelSwitcherSheetState();
}

class _ModelSwitcherSheetState extends ConsumerState<_ModelSwitcherSheet> {
  OnlineModelSelection? _savedOnline;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedOnline();
  }

  Future<void> _loadSavedOnline() async {
    final saved = await ref.read(llmRouterProvider).savedOnlineSelection();
    if (mounted) setState(() => _savedOnline = saved);
  }

  String _message(Object error) {
    if (error is AuraException) return error.userMessage;
    return error.toString().replaceFirst('Bad state: ', '');
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelState = ref.watch(modelSelectorProvider);
    final router = ref.watch(llmRouterProvider);
    final activeId = modelState.activeModelId;
    final isOnlineActive = router.isOnline;
    final downloaded = modelState.availableModels
        .where((model) => modelState.isDownloaded(model.id))
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ClayColors.textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Switch AI model',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isOnlineActive
                    ? 'Online model active. Prompts leave the device.'
                    : 'On-device model active. Prompts stay private.',
                style: GoogleFonts.outfit(
                  color: ClayColors.textMuted,
                  fontSize: 12,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: ClayColors.redAccent),
                ),
              ],
              const SizedBox(height: 16),
              _sectionLabel('On-device (offline)'),
              if (downloaded.isEmpty)
                _tile(
                  title: 'No downloaded models',
                  subtitle: 'Download one to chat fully offline.',
                  icon: Icons.download_rounded,
                  onTap: _busy
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ModelSelectorScreen(),
                            ),
                          );
                        },
                )
              else
                for (final model in downloaded)
                  _tile(
                    title: model.name,
                    subtitle: model.sizeFormatted,
                    icon: Icons.phone_android_rounded,
                    selected: !isOnlineActive && activeId == model.id,
                    onTap: _busy || (!isOnlineActive && activeId == model.id)
                        ? null
                        : () => _run(
                            () => ref
                                .read(modelSelectorProvider.notifier)
                                .selectModel(model.id),
                          ),
                  ),
              const SizedBox(height: 18),
              _sectionLabel('Online API models'),
              if (_savedOnline != null)
                _tile(
                  title: _savedOnline!.name,
                  subtitle: _savedOnline!.provider.displayName,
                  icon: Icons.cloud_outlined,
                  selected: isOnlineActive,
                  onTap: _busy || isOnlineActive
                      ? null
                      : () => _run(
                          () => ref
                              .read(modelSelectorProvider.notifier)
                              .activateSavedOnlineModel(),
                        ),
                ),
              _tile(
                title: _savedOnline == null
                    ? 'Add an API key'
                    : 'Choose another online model',
                subtitle: 'OpenRouter, Groq or NVIDIA NIM',
                icon: Icons.key_rounded,
                onTap: _busy
                    ? null
                    : () async {
                        Navigator.of(context).pop();
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const OnlineProviderSettingsScreen(),
                          ),
                        );
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: GoogleFonts.outfit(
        color: ClayColors.goldAccent,
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _tile({
    required String title,
    required String subtitle,
    required IconData icon,
    VoidCallback? onTap,
    bool selected = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: ClayColors.goldAccent),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: selected
            ? const Icon(Icons.check_circle, color: ClayColors.greenAccent)
            : const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
