// Automated micro-benchmark for rule-planning latency (Req 13.3, budget B2).
//
// The 300 ms budget is a low-end-device ceiling; on any dev/CI machine the pure
// Dart planner should complete in well under that. We assert a strict fraction
// of the budget so a regression that makes planning pathologically slow is
// caught here rather than only on-device.
//
// Feature: interactive-agent-mode (Task 13, B2)

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/features/interactive_agent/agent_budgets.dart';
import 'package:aura_mobile/features/interactive_agent/planning/rule_based_planner.dart';
import 'package:aura_mobile/features/interactive_agent/planning/strategy_resolver.dart';

void main() {
  const planner = RuleBasedPlanner();
  const resolver = StrategyResolver();
  final budget = AgentBudgets.defaults.rulePlanBudget; // 300 ms

  const commands = [
    'open whatsapp',
    'message John on whatsapp saying I am running late for the meeting',
    'search for wireless headphones under 2000 on amazon',
    'play calm lofi study beats on spotify',
    'navigate to the central railway station',
    'what is the capital of france', // unsupported → null, still fast
    'launch settings',
  ];

  test('rule planning + resolution stays far under the 300ms budget', () async {
    // Warm up (first-call regex compilation, JIT).
    for (final c in commands) {
      final p = await planner.plan(c);
      if (p != null) resolver.resolve(p);
    }

    const runs = 500;
    final sw = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      final c = commands[i % commands.length];
      final p = await planner.plan(c);
      if (p != null) resolver.resolve(p);
    }
    sw.stop();

    final avgMs = sw.elapsedMicroseconds / runs / 1000.0;
    // Even allowing a large low-end-device multiplier, the average must be a
    // small fraction of the budget. 10% is a generous ceiling for CI hardware.
    expect(
      avgMs,
      lessThan(budget.inMilliseconds * 0.10),
      reason:
          'avg plan+resolve was ${avgMs.toStringAsFixed(3)}ms; budget is '
          '${budget.inMilliseconds}ms (asserting < 10% of budget on CI)',
    );
  });
}
