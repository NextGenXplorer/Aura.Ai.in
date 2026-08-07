/// Fixed-size, content-free run diagnostics.
///
/// Records only step id, kind, strategy, outcome type, and elapsed ms — never
/// node text, entered values, or contact identifiers (Req 15.3, 15.4). Backed by
/// a ring buffer so a long session cannot grow memory without bound (Req 13.10).
///
/// Feature: interactive-agent-mode (Task 7.2)
library;

import 'agent_budgets.dart';
import 'models/agent_step.dart';
import 'models/run_result.dart';

class DiagnosticEntry {
  final String stepId;
  final StepKind kind;
  final ActionStrategy strategy;

  /// The runtime type name of the outcome (e.g. "StepSucceeded"). Never carries
  /// user content.
  final String outcome;
  final int elapsedMs;

  const DiagnosticEntry({
    required this.stepId,
    required this.kind,
    required this.strategy,
    required this.outcome,
    required this.elapsedMs,
  });

  @override
  String toString() =>
      '$stepId $kind/$strategy -> $outcome (${elapsedMs}ms)';
}

class AgentDiagnostics {
  final int _capacity;
  final List<DiagnosticEntry> _ring = [];

  AgentDiagnostics({AgentBudgets budgets = AgentBudgets.defaults})
    : _capacity = budgets.diagnosticsRingSize;

  /// Records a step outcome, redacted. [elapsed] defaults to any elapsed the
  /// outcome carries.
  void record(AgentStep step, StepOutcome outcome) {
    final ms = outcome is StepSucceeded ? outcome.elapsed.inMilliseconds : 0;
    _push(
      DiagnosticEntry(
        stepId: step.id,
        kind: step.kind,
        strategy: step.strategy,
        outcome: outcome.runtimeType.toString(),
        elapsedMs: ms,
      ),
    );
  }

  void _push(DiagnosticEntry entry) {
    _ring.add(entry);
    if (_ring.length > _capacity) {
      _ring.removeAt(0);
    }
  }

  /// A redacted snapshot for troubleshooting (Req 15.7).
  List<DiagnosticEntry> snapshot() => List.unmodifiable(_ring);

  /// Discard on run/session end (Req 15.5, 15.6).
  void clear() => _ring.clear();
}
