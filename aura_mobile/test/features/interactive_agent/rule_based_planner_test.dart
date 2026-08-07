// Unit tests for RuleBasedPlanner coverage and refusal.
//
// Feature: interactive-agent-mode, Task 3.2

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/features/interactive_agent/models/agent_step.dart';
import 'package:aura_mobile/features/interactive_agent/planning/rule_based_planner.dart';

void main() {
  const planner = RuleBasedPlanner();

  test('bare open command yields a single openApp step', () async {
    final plan = await planner.plan('open whatsapp');
    expect(plan, isNotNull);
    expect(plan!.steps, hasLength(1));
    expect(plan.steps.single.kind, StepKind.openApp);
    expect(plan.steps.single.strategy, ActionStrategy.deepLink);
  });

  test('whatsapp send yields open then an irreversible send', () async {
    final plan = await planner.plan('message John on whatsapp saying I am late');
    expect(plan, isNotNull);
    expect(plan!.steps, hasLength(2));
    expect(plan.steps[0].kind, StepKind.openApp);
    expect(plan.steps[1].kind, StepKind.deepLinkAction);
    expect(plan.steps[1].deepLinkMethod, 'sendWhatsApp');
    expect(plan.steps[1].isIrreversible, isTrue);
    expect(plan.steps[1].deepLinkArgs['contact'], 'john');
    expect(plan.steps[1].deepLinkArgs['message'], 'I am late');
  });

  test('search-in-app yields open then a searchOnApp step', () async {
    final plan = await planner.plan('search for running shoes on amazon');
    expect(plan, isNotNull);
    expect(plan!.steps.last.deepLinkMethod, 'searchOnApp');
    expect(plan.steps.last.deepLinkArgs['query'], 'running shoes');
    expect(plan.steps.last.isIrreversible, isFalse);
  });

  test('play command yields a single Spotify step', () async {
    final plan = await planner.plan('play lofi beats on spotify');
    expect(plan, isNotNull);
    expect(plan!.steps.single.deepLinkMethod, 'playOnSpotify');
    expect(plan.steps.single.deepLinkArgs['query'], 'lofi beats');
  });

  test('navigate command yields a maps navigation step', () async {
    final plan = await planner.plan('navigate to central park');
    expect(plan, isNotNull);
    expect(plan!.steps.single.deepLinkArgs['app'], 'navigate:central park');
  });

  test('empty command is not planned', () async {
    expect(await planner.plan('   '), isNull);
  });

  test('unsupported command returns null for model fallback', () async {
    expect(await planner.plan('what is the meaning of life'), isNull);
    expect(await planner.plan('tell me a joke'), isNull);
  });

  test('rule planning is well within its 300ms budget', () async {
    final sw = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      await planner.plan('message John on whatsapp saying hello there');
    }
    sw.stop();
    // 200 plans must average far below the 300ms single-plan budget.
    expect(sw.elapsedMilliseconds / 200, lessThan(50));
  });
}
