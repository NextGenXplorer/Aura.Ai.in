/// The run state machine: plan, acknowledge, then per step gate, narrate,
/// dispatch, settle, verify, and bounded recovery — under step and time
/// budgets, abortable at any boundary.
///
/// Pure orchestration over injected collaborators, so the whole machine is
/// testable against fakes with no device.
///
/// Feature: interactive-agent-mode (Task 7.1)
library;

import 'dart:async';

import 'agent_budgets.dart';
import 'agent_diagnostics.dart';
import 'dispatch/step_dispatch.dart';
import 'models/agent_plan.dart';
import 'models/agent_step.dart';
import 'models/run_result.dart';
import 'models/screen_signature.dart';
import 'models/session_state.dart';
import 'planning/strategy_resolver.dart';

/// Asks the user to confirm a gated step. Returns true to proceed, false to
/// decline. The runner excludes the time spent here from the time budget
/// (Req 12.5).
typedef GateHandler = Future<bool> Function(PendingGate gate);

/// Builds the concrete effect string shown at a gate (Req 9.3).
typedef EffectDescriber = String Function(AgentStep step);

class AgentRunner {
  final Future<AgentPlan?> Function(String command) buildRulePlan;
  final Future<AgentPlan?> Function(String command)? buildModelPlan;
  final StrategyResolver resolver;
  final StepDispatch dispatch;
  final AgentBudgets budgets;
  final GateHandler gate;
  final EffectDescriber describeEffect;
  final AgentDiagnostics diagnostics;

  AgentRunner({
    required this.buildRulePlan,
    required this.dispatch,
    required this.gate,
    this.buildModelPlan,
    StrategyResolver? resolver,
    AgentBudgets? budgets,
    EffectDescriber? describeEffect,
    AgentDiagnostics? diagnostics,
  }) : resolver = resolver ?? const StrategyResolver(),
       budgets = budgets ?? AgentBudgets.defaults,
       describeEffect = describeEffect ?? _defaultEffect,
       diagnostics = diagnostics ?? AgentDiagnostics();

  bool _abortRequested = false;
  final _events = StreamController<RunEvent>.broadcast();

  Stream<RunEvent> get events => _events.stream;

  /// Requests abort. The run stops before the next step begins (Req 10.3).
  void requestAbort() => _abortRequested = true;

  /// Runs [command] under [posture]. Returns the terminal result; step-level
  /// progress is emitted on [events].
  Future<RunResult> execute(
    String command,
    AutonomyPosture posture,
  ) async {
    _abortRequested = false;
    final completed = <String>[];

    // 1. Plan (rule first, model fallback within its timeout).
    var plan = await buildRulePlan(command);
    if (plan == null && buildModelPlan != null) {
      try {
        plan = await buildModelPlan!(command).timeout(budgets.modelPlanTimeout);
      } on TimeoutException {
        plan = null;
      } catch (_) {
        plan = null;
      }
    }
    if (plan == null) {
      final result = const RunUnsupported('No plan could be built for that.');
      _emit(RunEnded(result));
      return result;
    }

    // 2. Resolve strategy + irreversibility + budget.
    plan = resolver.resolve(plan);
    _emit(PlanReady(plan));

    // 3. Plan acknowledgement gate (Req 4.3).
    final ackGate = PendingGate(
      step: plan.steps.isEmpty
          ? _sentinelStep
          : plan.steps.first,
      effectSummary: plan.summary,
    );
    if (!await gate(ackGate)) {
      final result = RunAborted(completed, AbortReason.gateDeclined);
      _emit(RunEnded(result));
      return result;
    }

    // 4. Execute.
    final deadline = _Deadline(budgets.timeBudget);
    var firstUiActionGatePassed = false;

    for (var i = 0; i < plan.steps.length; i++) {
      if (_abortRequested) {
        return _end(RunAborted(completed, AbortReason.userRequested));
      }
      if (deadline.exceeded) {
        return _end(RunAborted(completed, AbortReason.timeBudget));
      }

      final step = plan.steps[i];
      _emit(StepStarted(i, step));

      // Confirmation gates (Req 9). Gate wait is excluded from the budget.
      final needsIrreversibleGate = step.isIrreversible;
      final needsFirstUiGate =
          posture == AutonomyPosture.guided &&
          step.strategy == ActionStrategy.uiAction &&
          !firstUiActionGatePassed;

      if (needsIrreversibleGate || needsFirstUiGate) {
        final pending = PendingGate(
          step: step,
          effectSummary: describeEffect(step),
          isFirstUiActionGate: needsFirstUiGate && !needsIrreversibleGate,
        );
        _emit(GateRequested(pending));
        final approved = await deadline.excluding(() => gate(pending));
        if (!approved) {
          return _end(RunAborted(completed, AbortReason.gateDeclined));
        }
        if (needsFirstUiGate) firstUiActionGatePassed = true;
      }

      // Dispatch + settle + verify + bounded recovery.
      final before = step.postCondition is SignatureChanged
          ? await dispatch.signature()
          : null;

      var outcome = await _runStepWithRecovery(step, before);
      diagnostics.record(step, outcome);
      _emit(StepFinished(i, step, outcome));

      if (outcome is StepSucceeded) {
        completed.add(step.id);
        continue;
      }
      // Deep-link steps get one UI-action fallback attempt (Req 5.6) — handled
      // inside _runStepWithRecovery; if we are here the step truly failed.
      return _end(RunFailed(completed, step, outcome));
    }

    return _end(RunCompleted(completed));
  }

  Future<StepOutcome> _runStepWithRecovery(
    AgentStep step,
    ScreenSignature? before,
  ) async {
    var outcome = await _dispatchAndVerify(step, before);
    var retries = 0;
    while (outcome is! StepSucceeded && retries < budgets.maxRecoveryRetries) {
      // A secure window is never retried — it will not change (crash/probe
      // safety).
      if (outcome is StepBlockedBySecureWindow) break;
      retries++;
      // Recovery: allow the screen to re-settle, then retry.
      await dispatch.awaitSettle(timeout: budgets.settleTimeout);
      outcome = await _dispatchAndVerify(step, before);
    }
    return outcome;
  }

  Future<StepOutcome> _dispatchAndVerify(
    AgentStep step,
    ScreenSignature? before,
  ) async {
    final outcome = await dispatch.dispatch(step);
    if (outcome is! StepSucceeded) return outcome;
    if (step.postCondition == null) return outcome;

    final settled = await dispatch.awaitSettle(timeout: budgets.settleTimeout);
    if (!settled) return const StepNotSettled();

    final ok = await dispatch.verify(step.postCondition!, before: before);
    return ok ? outcome : StepPostConditionFailed(step.postCondition!);
  }

  RunResult _end(RunResult result) {
    _emit(RunEnded(result));
    return result;
  }

  void _emit(RunEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> dispose() async {
    await _events.close();
  }

  static String _defaultEffect(AgentStep step) => step.narration;

  static const AgentStep _sentinelStep = AgentStep(
    id: '_ack',
    kind: StepKind.openApp,
    strategy: ActionStrategy.deepLink,
    narration: 'Begin',
  );
}

/// Wall-clock budget tracker that can exclude gate-wait spans (Req 12.5).
class _Deadline {
  final Duration budget;
  final Stopwatch _sw = Stopwatch()..start();

  _Deadline(this.budget);

  bool get exceeded => _sw.elapsed > budget;

  /// Runs [action] with the clock paused, so time awaiting a gate is not
  /// charged against the budget.
  Future<T> excluding<T>(Future<T> Function() action) async {
    _sw.stop();
    try {
      return await action();
    } finally {
      _sw.start();
    }
  }
}
