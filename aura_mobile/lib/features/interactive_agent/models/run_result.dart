/// Outcomes of a single step and of a whole run.
///
/// Feature: interactive-agent-mode
library;

import 'package:flutter/foundation.dart';

import 'agent_step.dart';

/// The result of dispatching and verifying one step.
@immutable
sealed class StepOutcome {
  const StepOutcome();
}

class StepSucceeded extends StepOutcome {
  final Duration elapsed;
  const StepSucceeded(this.elapsed);
}

/// A targeted node query found nothing (Req 6.4).
class StepNoMatch extends StepOutcome {
  final NodeQuery query;
  const StepNoMatch(this.query);
}

/// A targeted node query found multiple plausible matches and disambiguation
/// required uniqueness (Req 6.5).
class StepAmbiguous extends StepOutcome {
  final int matchCount;
  const StepAmbiguous(this.matchCount);
}

/// The screen never settled within the settle timeout (Req 7.6).
class StepNotSettled extends StepOutcome {
  const StepNotSettled();
}

/// The step dispatched but its post-condition did not hold (Req 6.6).
class StepPostConditionFailed extends StepOutcome {
  final PostCondition expected;
  const StepPostConditionFailed(this.expected);
}

/// The foreground window is marked secure; UI actions are refused (Req 6.7).
class StepBlockedBySecureWindow extends StepOutcome {
  const StepBlockedBySecureWindow();
}

/// Dispatch itself failed (deep-link rejected, channel error, disabled).
class StepDispatchFailed extends StepOutcome {
  final String reason;
  const StepDispatchFailed(this.reason);
}

extension StepOutcomeX on StepOutcome {
  bool get succeeded => this is StepSucceeded;
}

/// Why a run aborted.
enum AbortReason {
  userRequested,
  gateDeclined,
  gateTimeout,
  stepBudget,
  timeBudget,
  serviceLost,
  pauseAborted,
}

/// The terminal result of a run. Every variant reports exactly the step ids
/// that completed (Req 8.5, 10.4).
@immutable
sealed class RunResult {
  final List<String> completedStepIds;
  const RunResult(this.completedStepIds);
}

class RunCompleted extends RunResult {
  const RunCompleted(super.completedStepIds);
}

class RunAborted extends RunResult {
  final AbortReason reason;
  const RunAborted(super.completedStepIds, this.reason);
}

class RunFailed extends RunResult {
  final AgentStep failedStep;
  final StepOutcome cause;
  const RunFailed(super.completedStepIds, this.failedStep, this.cause);
}

/// A run that never started because no plan could be produced (Req 4.6).
class RunUnsupported extends RunResult {
  final String reason;
  const RunUnsupported(this.reason) : super(const []);
}
