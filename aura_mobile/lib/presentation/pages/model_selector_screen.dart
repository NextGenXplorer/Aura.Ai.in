import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/presentation/providers/model_catalog_grouping.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:google_fonts/google_fonts.dart';

/// Provides the device RAM in MB, fetched once and cached.
final _deviceRamProvider = FutureProvider<int>((ref) async {
  final deviceService = ref.watch(deviceServiceProvider);
  final info = await deviceService.analyzeDevice();
  return info.totalRamMB;
});

enum ModelFamilyTab { all, qwen, gemma }

final _modelTabProvider = StateProvider<ModelFamilyTab>((ref) => ModelFamilyTab.all);

class ModelSelectorScreen extends ConsumerWidget {
  const ModelSelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(modelSelectorProvider);
    final notifier = ref.read(modelSelectorProvider.notifier);
    final deviceRamAsync = ref.watch(_deviceRamProvider);
    final selectedTab = ref.watch(_modelTabProvider);

    // Device RAM: default to 0 if not yet determined (disables unsupported models).
    final int deviceRamMB = deviceRamAsync.when(
      data: (ram) => ram,
      loading: () => 0,
      error: (_, __) => 0,
    );

    // Filter available models based on selected family tab.
    final filteredModels = state.availableModels.where((model) {
      switch (selectedTab) {
        case ModelFamilyTab.all:
          return true;
        case ModelFamilyTab.qwen:
          return model.id.toLowerCase().contains('qwen');
        case ModelFamilyTab.gemma:
          return model.id.toLowerCase().contains('gemma');
      }
    }).toList();

    // Group the filtered models by engine.
    final groups = groupCatalogByEngine(filteredModels);

    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Model Manager',
          style: GoogleFonts.outfit(
            color: ClayColors.textDark,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: ClayColors.textDark, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: ClayColors.goldAccent),
            onPressed: () => notifier.refreshModels(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => notifier.refreshModels(),
        backgroundColor: ClayColors.warmGrey,
        color: ClayColors.goldAccent,
        child: CustomScrollView(
          slivers: [
            // Storage Summary
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ClayContainer(
                  borderRadius: 24,
                  depth: 6.0,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.storage_rounded,
                            color: ClayColors.goldAccent,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Storage Usage',
                            style: GoogleFonts.outfit(
                              color: ClayColors.textDark,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStorageStat(
                            'Downloaded',
                            '${state.downloadedModelIds.length}',
                            Icons.download_done_rounded,
                          ),
                          _buildStorageStat(
                            'Total Size',
                            _formatBytes(state.totalStorageUsed),
                            Icons.folder_open_rounded,
                          ),
                          _buildStorageStat(
                            'Available',
                            '${state.availableModels.length}',
                            Icons.grid_view_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Model Family Tab Selector
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: ClayContainer(
                  borderRadius: 18,
                  isInset: true,
                  depth: 4.0,
                  baseColor: const Color(0xFFE5E2DA),
                  highlightColor: const Color(0xFFF7F4EF),
                  shadowColor: const Color(0xFFCBC7BE),
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    children: [
                      _buildTabButton(ref, ModelFamilyTab.all, 'All Models', selectedTab),
                      _buildTabButton(ref, ModelFamilyTab.qwen, 'Qwen Models', selectedTab),
                      _buildTabButton(ref, ModelFamilyTab.gemma, 'Gemma Models', selectedTab),
                    ],
                  ),
                ),
              ),
            ),

            // Active Model Info
            if (state.activeModelId != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ClayContainer(
                    borderRadius: 20,
                    depth: 4.0,
                    baseColor: ClayColors.goldAccent.withOpacity(0.08),
                    highlightColor: ClayColors.highlight,
                    shadowColor: ClayColors.shadow,
                    border: Border.all(color: ClayColors.goldAccent.withOpacity(0.3), width: 1.0),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: ClayColors.goldAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Active: ${state.availableModels.firstWhere((m) => m.id == state.activeModelId).name}',
                            style: GoogleFonts.outfit(
                              color: ClayColors.goldAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Grouped model list — one section per engine
            for (final group in groups) ...[
              // Engine group heading
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 16, 12),
                  child: Text(
                    _engineHeading(group.engine),
                    style: GoogleFonts.outfit(
                      color: ClayColors.textMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              // Models within the group
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final model = group.models[index];
                      final supported = isModelSupported(model, deviceRamMB);
                      final badges = qualifyingBadges(model);

                      return _GroupedModelCard(
                        model: model,
                        isDownloaded: state.isDownloaded(model.id),
                        isActive: state.isActive(model.id),
                        isDownloading: state.isDownloading(model.id),
                        downloadProgress: state.getProgress(model.id),
                        error: state.getError(model.id),
                        supported: supported,
                        badges: badges,
                        deviceRamMB: deviceRamMB,
                        onDownload: () => notifier.downloadModel(model.id),
                        onDelete: () => _showDeleteConfirmation(
                          context,
                          model.name,
                          () => notifier.deleteModel(model.id),
                        ),
                        onSelect: supported
                            ? () => _handleModelSelection(
                                  context,
                                  ref,
                                  model,
                                  notifier,
                                )
                            : null,
                      );
                    },
                    childCount: group.models.length,
                  ),
                ),
              ),
            ],

            // Bottom Padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 24),
            ),
          ],
        ),
      ),
    );
  }

  /// Handles model selection through the EngineRouter, showing a load-failure
  /// SnackBar on error while retaining the previous active model (Req 6.7, 6.8).
  Future<void> _handleModelSelection(
    BuildContext context,
    WidgetRef ref,
    ModelInfo model,
    ModelSelectorNotifier notifier,
  ) async {
    try {
      final router = ref.read(engineRouterProvider);
      await router.loadModelInfo(model);
      // Commit selection into the provider state.
      notifier.selectModel(model.id);
    } catch (e) {
      // Load failed — show error, previous active model is retained (Req 6.8).
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load ${model.name}: ${_extractMessage(e)}',
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            backgroundColor: ClayColors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Extracts a user-presentable message from an exception.
  String _extractMessage(Object e) {
    if (e is Exception) {
      final str = e.toString();
      // Strip the "Exception: " prefix if present.
      if (str.startsWith('Exception: ')) return str.substring(11);
      return str;
    }
    return e.toString();
  }

  /// Returns the display heading for an engine group.
  String _engineHeading(AIEngine engine) {
    switch (engine) {
      case AIEngine.gguf:
        return 'GGUF Models (Customizable)';
      case AIEngine.litert:
        return 'LiteRT Models (On-device Optimized)';
    }
  }

  Widget _buildStorageStat(String label, String value, IconData icon) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ClayContainer(
          isInset: true,
          borderRadius: 16,
          depth: 4.0,
          baseColor: const Color(0xFFE5E2DA),
          highlightColor: const Color(0xFFF7F4EF),
          shadowColor: const Color(0xFFCBC7BE),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: ClayColors.goldAccent, size: 20),
              const SizedBox(height: 8),
              Text(
                value,
                style: GoogleFonts.outfit(
                  color: ClayColors.textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: ClayColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes == 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) {
      return '${mb.toStringAsFixed(0)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

  void _showDeleteConfirmation(
    BuildContext context,
    String modelName,
    VoidCallback onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (context) => ClayDialog(
        title: 'Delete Model?',
        content: Text(
          'Are you sure you want to delete "$modelName"? This will free up storage space.',
          style: GoogleFonts.outfit(
            color: ClayColors.textDark,
            fontSize: 14,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        actions: [
          ClayButton(
            onTap: () => Navigator.of(context).pop(),
            baseColor: ClayColors.warmGrey,
            highlightColor: ClayColors.highlight,
            shadowColor: ClayColors.shadow,
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(
                color: ClayColors.textMuted,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ClayButton(
            onTap: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            baseColor: ClayColors.redAccent,
            highlightColor: ClayColors.redHighlight,
            shadowColor: ClayColors.redShadow,
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(
              'Delete',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(
    WidgetRef ref,
    ModelFamilyTab tab,
    String label,
    ModelFamilyTab selectedTab,
  ) {
    final isActive = selectedTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(_modelTabProvider.notifier).state = tab,
        child: isActive
            ? ClayContainer(
                borderRadius: 12,
                depth: 4.0,
                baseColor: ClayColors.goldHighlight,
                highlightColor: Colors.white,
                shadowColor: ClayColors.goldShadow,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    color: ClayColors.goldAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            : Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    color: ClayColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
      ),
    );
  }
}

/// A model card that displays capability badges, download size, min RAM,
/// and a "not supported" overlay when the device does not have enough RAM.
class _GroupedModelCard extends StatelessWidget {
  final ModelInfo model;
  final bool isDownloaded;
  final bool isActive;
  final bool isDownloading;
  final double downloadProgress;
  final String? error;
  final bool supported;
  final Set<CapabilityBadge> badges;
  final int deviceRamMB;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;
  final VoidCallback? onSelect;

  const _GroupedModelCard({
    required this.model,
    required this.isDownloaded,
    required this.isActive,
    required this.isDownloading,
    required this.downloadProgress,
    required this.supported,
    required this.badges,
    required this.deviceRamMB,
    this.error,
    this.onDownload,
    this.onDelete,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = supported ? 1.0 : 0.5;
    final baseColor = isActive ? ClayColors.goldHighlight : ClayColors.warmGrey;
    final highlightColor = isActive ? const Color(0xFFFFFFFF) : ClayColors.highlight;
    final shadowColor = isActive ? ClayColors.goldShadow : ClayColors.shadow;
    final border = isActive
        ? Border.all(color: ClayColors.goldAccent, width: 2.0)
        : Border.all(color: Colors.black.withOpacity(0.04), width: 1.0);

    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: ClayContainer(
          borderRadius: 24,
          depth: isActive ? 10.0 : 6.0,
          baseColor: baseColor,
          highlightColor: highlightColor,
          shadowColor: shadowColor,
          border: border,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  const Icon(
                    Icons.psychology_outlined,
                    color: ClayColors.goldAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      model.name,
                      style: GoogleFonts.outfit(
                        color: ClayColors.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ClayColors.goldAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: ClayColors.goldAccent.withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'ACTIVE',
                        style: GoogleFonts.outfit(
                          color: ClayColors.goldAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // Capability Badges row
              if (badges.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final badge in badges) _buildBadge(badge),
                    ],
                  ),
                ),

              // Description
              Text(
                model.description,
                style: GoogleFonts.outfit(
                  color: ClayColors.textMuted,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),

              // Size & RAM info
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _buildSpec(Icons.storage_rounded, '${model.sizeMB.toStringAsFixed(0)} MB'),
                  _buildSpec(Icons.memory_rounded, '${model.minRamMB} MB RAM'),
                  _buildSpec(Icons.speed_rounded, model.speed),
                ],
              ),

              // Not supported indicator
              if (!supported) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: ClayColors.orangeAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ClayColors.orangeAccent.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: ClayColors.orangeAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Not supported \u2013 requires ${model.minRamMB} MB RAM',
                          style: GoogleFonts.outfit(
                            color: ClayColors.orangeAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Error Message
              if (error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: ClayColors.redAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ClayColors.redAccent.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: ClayColors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error!,
                          style: GoogleFonts.outfit(
                            color: ClayColors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Progress Bar
              if (isDownloading) ...[
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Downloading...',
                          style: GoogleFonts.outfit(
                            color: ClayColors.goldAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${(downloadProgress * 100).toStringAsFixed(0)}%',
                          style: GoogleFonts.outfit(
                            color: ClayColors.goldAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClayProgressBar(value: downloadProgress),
                  ],
                ),
              ],

              // Action Buttons
              if (!isDownloading) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (!isDownloaded)
                      Expanded(
                        child: ClayButton(
                          onTap: supported ? onDownload : null,
                          baseColor: ClayColors.goldHighlight,
                          highlightColor: Colors.white,
                          shadowColor: ClayColors.goldShadow,
                          borderRadius: 14,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.download_rounded, size: 18, color: ClayColors.goldAccent),
                              SizedBox(width: 8),
                              Text('Download', style: TextStyle(color: ClayColors.goldAccent)),
                            ],
                          ),
                        ),
                      ),
                    if (isDownloaded && !isActive) ...[
                      Expanded(
                        child: ClayButton(
                          onTap: supported ? onSelect : null,
                          baseColor: ClayColors.goldHighlight,
                          highlightColor: Colors.white,
                          shadowColor: ClayColors.goldShadow,
                          borderRadius: 14,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 18, color: ClayColors.goldAccent),
                              SizedBox(width: 8),
                              Text('Select', style: TextStyle(color: ClayColors.goldAccent)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ClayButton(
                        onTap: onDelete,
                        baseColor: ClayColors.warmGrey,
                        highlightColor: ClayColors.highlight,
                        shadowColor: ClayColors.shadow,
                        borderRadius: 14,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 18, color: ClayColors.redAccent),
                            SizedBox(width: 6),
                            Text('Delete', style: TextStyle(color: ClayColors.redAccent)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Renders a single capability badge chip with outlines instead of emojis.
  Widget _buildBadge(CapabilityBadge badge) {
    final IconData icon;
    final Color badgeColor;
    final String label;

    switch (badge) {
      case CapabilityBadge.toolCalling:
        icon = Icons.build_outlined;
        badgeColor = ClayColors.goldAccent;
        label = 'Tool Calling';
      case CapabilityBadge.vision:
        icon = Icons.visibility_outlined;
        badgeColor = ClayColors.blueAccent;
        label = 'Vision';
      case CapabilityBadge.fast:
        icon = Icons.speed_outlined;
        badgeColor = ClayColors.greenAccent;
        label = 'Fast';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: badgeColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: badgeColor, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: badgeColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpec(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: ClayColors.textHint, size: 14),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.outfit(
            color: ClayColors.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

