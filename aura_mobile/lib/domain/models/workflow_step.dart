import 'package:aura_mobile/domain/services/intent_detection_service.dart';

/// A single actionable step extracted from a compound user command.
///
/// Example:
///   "Search for the weather, then remind me at 8am"
///   → Step 1: WorkflowStep(rawMessage: "Search for the weather", hintType: webSearch)
///   → Step 2: WorkflowStep(rawMessage: "remind me at 8am", hintType: reminderSet)
class WorkflowStep {
  /// The isolated sub-sentence for this step.
  final String rawMessage;

  /// Pre-detected intent type (avoids a second classification round-trip).
  /// May be null if not yet classified.
  final IntentType? hintType;

  /// Extracted parameters for this step (e.g. {destination: 'airport', appName: 'WhatsApp'}).
  final Map<String, dynamic> parameters;

  /// An optional key to store the output of this step in the workflow context.
  final String? outputKey;

  /// An optional natural language description of what needs to be extracted from this step's output.
  final String? extractionRequirement;

  const WorkflowStep({
    required this.rawMessage,
    this.hintType,
    this.parameters = const {},
    this.outputKey,
    this.extractionRequirement,
  });

  /// Returns a copy of this step with an updated [hintType].
  WorkflowStep withHint(IntentType type, [Map<String, dynamic>? newParameters]) {
    return WorkflowStep(
      rawMessage: rawMessage,
      hintType: type,
      parameters: newParameters ?? parameters,
      outputKey: outputKey,
      extractionRequirement: extractionRequirement,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rawMessage': rawMessage,
      'hintType': hintType?.name,
      'parameters': parameters,
      'outputKey': outputKey,
      'extractionRequirement': extractionRequirement,
    };
  }

  factory WorkflowStep.fromMap(Map<String, dynamic> map) {
    return WorkflowStep(
      rawMessage: map['rawMessage'] ?? '',
      hintType: map['hintType'] != null ? IntentType.values.byName(map['hintType']) : null,
      parameters: Map<String, dynamic>.from(map['parameters'] ?? {}),
      outputKey: map['outputKey'],
      extractionRequirement: map['extractionRequirement'],
    );
  }

  @override
  String toString() => 'WorkflowStep(${hintType?.name ?? "??"} | "$rawMessage")';
}
