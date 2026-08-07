import '../../domain/entities/model_info.dart';

/// Pure helpers backing the Model_Selector UI.
///
/// These functions contain no UI or framework dependencies so the badge-
/// derivation and device-support rules can be unit/property tested in isolation.

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

/// Derives the set of qualifying capability badges for [model].
///
/// The tool-calling badge is present iff [ModelInfo.supportsToolCalling] is
/// true, the vision badge iff [ModelInfo.supportsVision] is true, and the fast
/// badge iff the inference speed is the highest-speed value
/// ([ModelInfo.qualifiesFastBadge]).
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
/// The supported flag equals `deviceRamMB >= model.minRamMB`.
bool isModelSupported(ModelInfo model, int deviceRamMB) {
  return deviceRamMB >= model.minRamMB;
}
