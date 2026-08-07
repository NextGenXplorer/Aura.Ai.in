import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/domain/entities/online_model.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class OnlineProviderSettingsScreen extends ConsumerStatefulWidget {
  const OnlineProviderSettingsScreen({super.key});

  @override
  ConsumerState<OnlineProviderSettingsScreen> createState() =>
      _OnlineProviderSettingsScreenState();
}

class _OnlineProviderSettingsScreenState
    extends ConsumerState<OnlineProviderSettingsScreen> {
  final _keyController = TextEditingController();
  OnlineProvider _provider = OnlineProvider.openRouter;
  List<OnlineModel> _models = const [];
  bool _loading = false;
  bool _keySaved = false;
  bool _freeOnly = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshKeyStatus();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  String _message(Object error) {
    if (error is AuraException) return error.userMessage;
    return error.toString().replaceFirst('Bad state: ', '');
  }

  Future<void> _refreshKeyStatus() async {
    final saved = await ref.read(llmRouterProvider).hasApiKey(_provider);
    if (mounted) setState(() => _keySaved = saved);
  }

  Future<void> _saveAndLoad() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final router = ref.read(llmRouterProvider);
      final entered = _keyController.text.trim();
      late final List<OnlineModel> models;
      if (entered.isNotEmpty) {
        models = await router.validateAndSaveApiKey(_provider, entered);
      } else {
        if (!await router.hasApiKey(_provider)) {
          throw StateError('Enter a ${_provider.displayName} API key.');
        }
        models = await router.listModels(_provider);
      }
      if (!mounted) return;
      _keyController.clear();
      setState(() {
        _models = models;
        _keySaved = true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteKey() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(llmRouterProvider).deleteApiKey(_provider);
      if (!mounted) return;
      setState(() {
        _keySaved = false;
        _models = const [];
      });
      await ref.read(modelSelectorProvider.notifier).refreshModels();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectModel(OnlineModel model) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(modelSelectorProvider.notifier).activateOnlineModel(model);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${model.name} is now Aura’s active model.')),
      );
      setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeProvider(OnlineProvider provider) {
    setState(() {
      _provider = provider;
      _models = const [];
      _error = null;
      _keySaved = false;
      _freeOnly = provider == OnlineProvider.openRouter;
      _keyController.clear();
    });
    _refreshKeyStatus();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(llmRouterProvider);
    final visibleModels = _models
        .where((model) => !_freeOnly || model.isExplicitlyFree)
        .take(60)
        .toList();

    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Online AI Providers', style: GoogleFonts.outfit()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _privacyNotice(),
          const SizedBox(height: 16),
          SegmentedButton<OnlineProvider>(
            segments: [
              for (final provider in OnlineProvider.values)
                ButtonSegment(
                  value: provider,
                  label: Text(provider.displayName),
                ),
            ],
            selected: {_provider},
            onSelectionChanged: (selection) => _changeProvider(selection.first),
          ),
          const SizedBox(height: 16),
          _providerCard(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: ClayColors.redAccent)),
          ],
          if (_models.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_provider.displayName} models',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_provider == OnlineProvider.openRouter)
                  FilterChip(
                    label: const Text('Free only'),
                    selected: _freeOnly,
                    onSelected: (value) => setState(() => _freeOnly = value),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Sorted by context size, capabilities and general-chat suitability. Verify current limits with the provider.',
              style: GoogleFonts.outfit(
                color: ClayColors.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < visibleModels.length; index++)
              _modelCard(
                visibleModels[index],
                recommended: index == 0,
                active: router.activeOnlineModel?.id == visibleModels[index].id,
              ),
          ],
        ],
      ),
    );
  }

  Widget _privacyNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ClayColors.goldAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ClayColors.goldAccent.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        'Offline remains the privacy-first default. When you select an online model, Aura sends the current prompt and the context assembled by its existing workflow to that provider. Keys are stored in the device keystore and are never bundled with Aura.',
        style: GoogleFonts.outfit(
          color: ClayColors.textMuted,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _providerCard() {
    return ClayContainer(
      borderRadius: 20,
      depth: 4,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _provider.availabilityNote,
                  style: GoogleFonts.outfit(
                    color: ClayColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(_provider.keyUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Get key'),
              ),
            ],
          ),
          TextField(
            controller: _keyController,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: _keySaved
                  ? 'API key saved — enter only to replace'
                  : '${_provider.displayName} API key',
              prefixIcon: const Icon(Icons.key_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading ? null : _saveAndLoad,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(
                    _keySaved ? 'Refresh models' : 'Save & load models',
                  ),
                ),
              ),
              if (_keySaved) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Delete saved key',
                  onPressed: _loading ? null : _deleteKey,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _modelCard(
    OnlineModel model, {
    required bool recommended,
    required bool active,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Row(
          children: [
            Expanded(
              child: Text(
                model.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ),
            if (recommended)
              const Chip(label: Text('Recommended'))
            else if (model.isExplicitlyFree)
              const Chip(label: Text('Free')),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${model.id}\n${model.contextLabel}'
            '${model.supportsVision ? ' • Vision' : ''}'
            '${model.supportsToolCalling ? ' • Aura tools' : ''}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: active
            ? const Icon(Icons.check_circle, color: ClayColors.greenAccent)
            : FilledButton(
                onPressed: _loading ? null : () => _selectModel(model),
                child: const Text('Use'),
              ),
      ),
    );
  }
}
