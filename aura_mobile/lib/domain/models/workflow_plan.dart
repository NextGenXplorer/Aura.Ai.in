import 'package:aura_mobile/domain/models/workflow_step.dart';

/// An ordered plan of [WorkflowStep]s derived from a single compound user command.
///
/// Example plan for "Open WhatsApp, text John hi, then set reminder at 8pm":
///   steps[0]: open WhatsApp
///   steps[1]: text John hi
///   steps[2]: set reminder at 8pm
class WorkflowPlan {
  /// Ordered steps to execute sequentially.
  final List<WorkflowStep> steps;

  /// When true, execution aborts on the first failed step.
  /// When false (default), errors are reported and execution continues.
  final bool failFast;

  const WorkflowPlan({
    required this.steps,
    this.failFast = false,
  });

  /// How many steps are in this plan.
  int get length => steps.length;

  /// True when there is more than one step (i.e. it's a real workflow).
  bool get isMultiStep => steps.length > 1;

  @override
  String toString() =>
      'WorkflowPlan(${steps.length} steps, failFast: $failFast)\n'
      '${steps.map((s) => '  $s').join('\n')}';
}
