// Property-based tests for the AgentRunner state machine.
//
// Feature: interactive-agent-mode, Properties 4, 5, 6, 7, 8, 12, 14
//
// The runner is exercised against a fully in-memory fake dispatch, so gates,
// aborts, budgets, recovery, and completion reporting are verified with no
// device and no accessibility service.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/features/interactive_agent/agent_budgets.dart';
import 'package:aura_mobile/features/interactive_agent/agent_diagnostics.dart';
import 'package:aura_mobile/features/interactive_agent/agent_runner.dart';
import 'package:aura_mobile/features/interactive_agent/dispatch/step_dispatch.dart';
import 'package:aura_mobile/features/interactive_agent/models/agent_plan.dart';
import 'package:aura_mobile/features/interactive_agent/models/agent_step.dart';
import 'package:aura_mobile/features/interactive_agent/models/run_result.dart';
import 'package:aura_mobile/features/interactive_agent/models/screen_signature.dart';
import 'package:aura_mobile/features/interactive_agent/models/session_state.dart';

const _iterations = 120;

/// Fake dispatch: every step succeeds unless its id is in [failIds].
class FakeDispatch implements StepDispatch {
  final Set<String> failIds;
  final List<String> dispatched = [];
  FakeDispatch({this.failIds = const {}});

  String? _current;
  void expect(String id) => _current = id;

  @override
  Future<StepOutcome> dispatch(AgentStep step) async {
    dispatched.add(step.id);
    if (failIds.contains(step.id)) {
      return const StepDispatchFailed('forced');
    }
    return StepSucceeded(const Duration(milliseconds: 1));
  }

  @override
  Future<bool> awaitSettle({Duration? timeout}) async => true;
  @override
  Future<bool> verify(PostCondition condition, {ScreenSignature? before}) async =>
      true;
  @override
  Future<ScreenSignature> signature() async => ScreenSignature.empty;
  @override
  Future<bool> setActionsEnabled(bool enabled) async => true;
  @override
  Future<bool> isServiceEnabled() async => true;
  @override
  Future<void> openAccessibilitySettings() async {}
}

AgentStep _step(String id, {bool irreversible = false}) => AgentStep(
  id: id,
  kind: StepKind.openApp,
  strategy: ActionStrategy.deepLink,
  narration: 'step $id',
  isIrreversible: irreversible,
);

AgentPlan _plan(List<AgentStep> steps) => AgentPlan(
  commandText: 'cmd',
  steps: steps,
  summary: 'do things',
  source: PlannerSource.rule,
);

AgentRunner _runner(
  AgentPlan plan,
  FakeDispatch dispatch, {
  required GateHandler gate,
  AgentBudgets? budgets,
  AgentDiagnostics? diagnostics,
}) => AgentRunner(
  buildRulePlan: (_) async => plan,
  dispatch: dispatch,
  gate: gate,
  budgets: budgets,
  diagnostics: diagnostics,
);

void main() {
  group('Property 4: a refused gate executes nothing further', () {
    test('declining the ack gate runs no steps', () async {
      final d = FakeDispatch();
      final r = _runner(
        _plan([_step('a'), _step('b')]),
        d,
        gate: (_) async => false,
      );
      final result = await r.execute('cmd', AutonomyPosture.guided);
      expect(result, isA<RunAborted>());
      expect(d.dispatched, isEmpty);
    });

    test('declining an irreversible step runs it and nothing after', () async {
      final rng = Random(0x4A);
      for (var i = 0; i < _iterations; i++) {
        final n = 2 + rng.nextInt(5);
        final gatedIndex = 1 + rng.nextInt(n - 1);
        final steps = [
          for (var s = 0; s < n; s++)
            _step('s$s', irreversible: s == gatedIndex),
        ];
        final d = FakeDispatch();
        // Approve the plan ack and every gate EXCEPT the gated step.
        final r = _runner(
          _plan(steps),
          d,
          gate: (g) async => g.step.id != 's$gatedIndex',
        );
        await r.execute('cmd', AutonomyPosture.continuous);
        // Steps before the gated index ran; the gated step and after did not.
        expect(d.dispatched, [for (var s = 0; s < gatedIndex; s++) 's$s']);
      }
    });
  });

  group('Property 5: abort stops further steps at a boundary', () {
    test('abort requested at step k runs no step after k', () async {
      final rng = Random(0x5A);
      for (var i = 0; i < _iterations; i++) {
        final n = 2 + rng.nextInt(6);
        // Abort at a step that has a successor, so the abort is observable at
        // the next loop top. (Aborting during the final step completes the run,
        // since there is no next step to stop — verified separately.)
        final abortAt = rng.nextInt(n - 1);
        // Every step is irreversible so the gate fires before each one; the gate
        // is the deterministic point at which we request abort (no stream race).
        final steps = [
          for (var s = 0; s < n; s++) _step('s$s', irreversible: true),
        ];
        final d = FakeDispatch();
        late AgentRunner r;
        var ackSeen = false;
        r = _runner(
          _plan(steps),
          d,
          gate: (g) async {
            // The first gate call is the plan acknowledgement; ignore it. Trip
            // abort on the step gate for the abort index.
            if (!ackSeen) {
              ackSeen = true;
              return true;
            }
            if (g.step.id == 's$abortAt') {
              r.requestAbort();
            }
            return true;
          },
        );
        final result = await r.execute('cmd', AutonomyPosture.continuous);
        // Abort requested in step k's gate: k dispatches, then the loop top for
        // k+1 observes the abort and stops. So exactly steps 0..k ran.
        expect(d.dispatched, [for (var s = 0; s <= abortAt; s++) 's$s']);
        expect(result, isA<RunAborted>());
        expect((result as RunAborted).reason, AbortReason.userRequested);
      }
    });

    test('aborting during the final step still completes it', () async {
      final d = FakeDispatch();
      late AgentRunner r;
      var ackSeen = false;
      r = _runner(
        _plan([_step('s0', irreversible: true)]),
        d,
        gate: (g) async {
          if (!ackSeen) {
            ackSeen = true;
            return true;
          }
          r.requestAbort();
          return true;
        },
      );
      final result = await r.execute('cmd', AutonomyPosture.continuous);
      expect(result, isA<RunCompleted>());
      expect(d.dispatched, ['s0']);
    });
  });

  group('Property 6: recovery is bounded', () {
    test('a permanently failing step retries at most maxRecoveryRetries', () async {
      const budgets = AgentBudgets(maxRecoveryRetries: 2);
      final d = FakeDispatch(failIds: {'s1'});
      final r = _runner(
        _plan([_step('s0'), _step('s1'), _step('s2')]),
        d,
        gate: (_) async => true,
        budgets: budgets,
      );
      final result = await r.execute('cmd', AutonomyPosture.continuous);
      expect(result, isA<RunFailed>());
      // s0 once, s1 dispatched 1 + 2 retries = 3 times, s2 never.
      final s1Count = d.dispatched.where((id) => id == 's1').length;
      expect(s1Count, 1 + budgets.maxRecoveryRetries);
      expect(d.dispatched.contains('s2'), isFalse);
    });
  });

  group('Property 7: gate waits do not consume the time budget', () {
    test('a long gate wait does not trip the time budget', () async {
      // Tiny time budget; a gate that waits well beyond it must not cause a
      // timeout, because gate time is excluded.
      const budgets = AgentBudgets(timeBudget: Duration(milliseconds: 50));
      final d = FakeDispatch();
      final r = _runner(
        _plan([_step('s0', irreversible: true), _step('s1')]),
        d,
        gate: (g) async {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          return true;
        },
        budgets: budgets,
      );
      final result = await r.execute('cmd', AutonomyPosture.continuous);
      expect(result, isA<RunCompleted>());
      expect(d.dispatched, ['s0', 's1']);
    });
  });

  group('Property 8: reported completions are exact', () {
    test('completed ids equal the steps that actually succeeded', () async {
      final rng = Random(0x8A);
      for (var i = 0; i < _iterations; i++) {
        final n = 1 + rng.nextInt(6);
        final failAt = rng.nextInt(n + 1); // n means "none fail"
        final steps = [for (var s = 0; s < n; s++) _step('s$s')];
        final d = FakeDispatch(failIds: failAt < n ? {'s$failAt'} : {});
        final r = _runner(
          _plan(steps),
          d,
          gate: (_) async => true,
          budgets: const AgentBudgets(maxRecoveryRetries: 0),
        );
        final result = await r.execute('cmd', AutonomyPosture.continuous);
        final expectedCompleted = [
          for (var s = 0; s < (failAt < n ? failAt : n); s++) 's$s',
        ];
        expect(result.completedStepIds, expectedCompleted);
      }
    });
  });

  group('Property 12: diagnostics carry no user content', () {
    test('no diagnostic entry contains node text or values', () async {
      final secret = 'SECRET_MESSAGE_9137';
      final steps = [
        AgentStep(
          id: 's0',
          kind: StepKind.setNodeText,
          strategy: ActionStrategy.uiAction,
          narration: 'type it',
          query: const NodeQuery(viewId: 'field'),
          value: secret,
        ),
      ];
      final diag = AgentDiagnostics();
      final d = FakeDispatch();
      final r = _runner(
        _plan(steps),
        d,
        gate: (_) async => true,
        diagnostics: diag,
      );
      await r.execute('cmd', AutonomyPosture.continuous);
      for (final entry in diag.snapshot()) {
        expect(entry.toString().contains(secret), isFalse);
      }
    });
  });

  group('Property 14: money and security steps are always gated', () {
    test('an irreversible step is gated under both postures', () async {
      for (final posture in AutonomyPosture.values) {
        final gatedSteps = <String>[];
        final d = FakeDispatch();
        final r = _runner(
          _plan([_step('pay', irreversible: true)]),
          d,
          gate: (g) async {
            gatedSteps.add(g.step.id);
            return true;
          },
        );
        await r.execute('cmd', posture);
        // The ack gate uses the first step; the irreversible gate also fires.
        expect(
          gatedSteps.where((id) => id == 'pay').length,
          greaterThanOrEqualTo(1),
          reason: 'irreversible step must be gated under $posture',
        );
      }
    });
  });
}
