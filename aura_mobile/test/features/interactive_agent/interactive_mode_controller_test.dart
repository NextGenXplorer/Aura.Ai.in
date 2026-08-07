// Tests for InteractiveModeController lifecycle and mediation.
//
// Feature: interactive-agent-mode (Task 10.1)

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/features/interactive_agent/agent_runner.dart';
import 'package:aura_mobile/features/interactive_agent/dispatch/step_dispatch.dart';
import 'package:aura_mobile/features/interactive_agent/interactive_mode_controller.dart';
import 'package:aura_mobile/features/interactive_agent/models/agent_plan.dart';
import 'package:aura_mobile/features/interactive_agent/models/agent_step.dart';
import 'package:aura_mobile/features/interactive_agent/models/run_result.dart';
import 'package:aura_mobile/features/interactive_agent/models/screen_signature.dart';
import 'package:aura_mobile/features/interactive_agent/models/session_state.dart';

class FakeDispatch implements StepDispatch {
  bool enabledResult = true;
  bool? lastSetEnabled;
  final List<String> dispatched = [];

  @override
  Future<StepOutcome> dispatch(AgentStep step) async {
    dispatched.add(step.id);
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
  Future<bool> setActionsEnabled(bool enabled) async {
    lastSetEnabled = enabled;
    return enabledResult;
  }

  @override
  Future<bool> isServiceEnabled() async => true;
  @override
  Future<void> openAccessibilitySettings() async {}
}

AgentPlan _plan(List<String> ids) => AgentPlan(
  commandText: 'cmd',
  steps: [
    for (final id in ids)
      AgentStep(
        id: id,
        kind: StepKind.openApp,
        strategy: ActionStrategy.deepLink,
        narration: 'step $id',
      ),
  ],
  summary: 'do things',
  source: PlannerSource.rule,
);

InteractiveModeController _controller(
  FakeDispatch dispatch, {
  AgentPlan? plan,
  GateHandler? forcedGate,
}) {
  return InteractiveModeController(
    dispatch: dispatch,
    runnerFactory: (gate) => AgentRunner(
      buildRulePlan: (_) async => plan ?? _plan(['s0']),
      dispatch: dispatch,
      gate: forcedGate ?? gate,
    ),
  );
}

void main() {
  test('starts off and enters only when the surface enables', () async {
    final d = FakeDispatch();
    final c = _controller(d);
    expect(c.state.active, isFalse);
    final ok = await c.enterSession();
    expect(ok, isTrue);
    expect(c.state.active, isTrue);
    expect(d.lastSetEnabled, isTrue);
  });

  test('entering fails when the action surface cannot enable', () async {
    final d = FakeDispatch()..enabledResult = false;
    final c = _controller(d);
    expect(await c.enterSession(), isFalse);
    expect(c.state.active, isFalse);
  });

  test('submitCommand is rejected when not active', () async {
    final d = FakeDispatch();
    final c = _controller(d);
    final result = await c.submitCommand('open whatsapp');
    expect(result, isA<RunUnsupported>());
  });

  test('a run auto-approving gates completes', () async {
    final d = FakeDispatch();
    final c = _controller(
      d,
      plan: _plan(['s0', 's1']),
      forcedGate: (_) async => true,
    );
    await c.enterSession();
    final result = await c.submitCommand('do it');
    expect(result, isA<RunCompleted>());
    expect(d.dispatched, ['s0', 's1']);
  });

  test('exiting disables the surface and resets state', () async {
    final d = FakeDispatch();
    final c = _controller(d);
    await c.enterSession();
    await c.exitSession();
    expect(c.state.active, isFalse);
    expect(d.lastSetEnabled, isFalse);
  });

  test('posture change is retained across exit', () async {
    final d = FakeDispatch();
    final c = _controller(d);
    c.setPosture(AutonomyPosture.continuous);
    await c.enterSession();
    await c.exitSession();
    expect(c.state.posture, AutonomyPosture.continuous);
  });

  test('gate mediation: resolveGate lets a gated run proceed', () async {
    final d = FakeDispatch();
    // Use the controller's own gate (not forced) so it routes through state.
    final c = InteractiveModeController(
      dispatch: d,
      runnerFactory: (gate) => AgentRunner(
        buildRulePlan: (_) async => AgentPlan(
          commandText: 'cmd',
          steps: [
            const AgentStep(
              id: 's0',
              kind: StepKind.openApp,
              strategy: ActionStrategy.deepLink,
              narration: 'pay someone',
              isIrreversible: true,
            ),
          ],
          summary: 'pay',
          source: PlannerSource.rule,
        ),
        dispatch: d,
        gate: gate,
      ),
    );
    await c.enterSession();
    final future = c.submitCommand('pay');
    // Drive the two gates (plan ack, then the irreversible step) as they appear.
    for (var i = 0; i < 10 && d.dispatched.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (c.state.gate != null) c.resolveGate(true);
    }
    final result = await future;
    expect(result, isA<RunCompleted>());
    expect(d.dispatched, ['s0']);
  });
}
