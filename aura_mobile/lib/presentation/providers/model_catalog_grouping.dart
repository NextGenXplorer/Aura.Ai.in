import '../../domain/entities/ai_engine.dart';
import '../../domain/entities/model_info.dart';

/// Pure helpers backing the Model_Selector UI.
///
/// These functions contain no UI or framework dependencies so the grouping,
/// badge-derivation, and device-support rules can be unit/property tested in
/// isolation (design properties 16, 17, and the support half of property 25).

/// A capability indicator surfaced on a model entry in the Model_Selector.
///
/// Each value corresponds to exactly one qualifying capability of a
/// [ModelInfo]; see [qualifyingBadges].
enum CapabilityBadge {
  /// The model supports native function/tool calling.
  toolCalling,

  /// The model supports vision (image) inputs.
  vision,

  /// The model's inference speed is the highest-speed value.
  fast,
}

/// A single engine group rendered by the Model_Selector: the engine the group
/// is labeled by, and the catalog models that belong to it.
class EngineGroup {
  const EngineGroup({required this.engine, required this.models});

  /// The engine value all [models] in this group share.
  final AIEngine engine;

  /// The catalog models assigned to this group, in their original order.
  final List<ModelInfo> models;
}

/// Partitions [catalog] into one group per distinct engine value present.
///
/// The result satisfies design Property 16: the groups are disjoint, their
/// union equals [catalog] (preserving each model's original order within its
/// group), and the set of group engines equals exactly the set of distinct
/// engine values present among the input models. An empty [catalog] yields no
/// groups.
List<EngineGroup> groupCatalogByEngine(List<ModelInfo> catalog) {
  // Insertion-ordered map keyed by engine; iteration order follows the order
  // in which each engine value is first encountered in the catalog.
  final grouped = <AIEngine, List<ModelInfo>>{};
  for (final model in catalog) {
    grouped.putIfAbsent(model.engine, () => <ModelInfo>[]).add(model);
  }
  return [
    for (final entry in grouped.entries)
      EngineGroup(engine: entry.key, models: entry.value),
  ];
}

/// Derives the set of qualifying capability badges for [model].
///
/// Satisfies design Property 17: the tool-calling badge is present iff
/// [ModelInfo.supportsToolCalling] is true, the vision badge iff
/// [ModelInfo.supportsVision] is true, and the fast badge iff the inference
/// speed is the highest-speed value ([ModelInfo.qualifiesFastBadge]).
Set<CapabilityBadge> qualifyingBadges(ModelInfo model) {
  return {
    if (model.supportsToolCalling) CapabilityBadge.toolCalling,
    if (model.supportsVision) CapabilityBadge.vision,
    if (model.qualifiesFastBadge) CapabilityBadge.fast,
  };
}

/// Whether [model] is supported on a device reporting [deviceRamMB] megabytes
/// of total RAM.
///
/// Satisfies the Model_Selector support rule of design Property 25: the
/// supported flag equals `deviceRamMB >= model.minRamMB`.
bool isModelSupported(ModelInfo model, int deviceRamMB) {
  return deviceRamMB >= model.minRamMB;
}
