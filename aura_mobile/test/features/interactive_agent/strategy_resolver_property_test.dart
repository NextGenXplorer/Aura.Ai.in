// Property-based tests for StrategyResolver.
//
// Feature: interactive-agent-mode, Properties 1, 2, 3
//
// glados is not a project dependency; per the established convention these use a
// seeded generator layered on package:flutter_test, each running >= 100 cases.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/features/interactive_agent/agent_budgets.dart';
import 'package:aura_mobile/features/interactive_agent/models/agent_plan.dart';
import 'package:aura_mobile/features/interactive_agent/models/agent_step.dart';
import 'package:aura_mobile/features/interactive_agent/planning/strategy_resolver.dart';

const int _iterations = 250;
const _budgets = AgentBudgets.defaults;
const _resolver = StrategyResolver(budgets: _budgets);

final _deepLinkMethods = StrategyResolver.deepLinkMethods.toList();
const _irreversibleVerbs = ['send', 'pay', 'delete', 'order', 'call', 'buy'];
const _safeVerbs = ['open', 'show', 'read', 'view', 'scroll', 'find'];

AgentStep _genStep(Random rng, int i) {
  final kind = StepKind.values[rng.nextInt(StepKind.values.length)];
  final irreversibleVerb = rng.nextBool();
  final verb = irreversibleVerb
      ? _irreversibleVerbs[rng.nextInt(_irreversibleVerbs.length)]
      : _safeVerbs[rng.nextInt(_safeVerbs.length)];
  String? method;
  if (kind == StepKind.deepLinkAction) {
    // Half the time a known method, half an unknown one.
    method = rng.nextBool()
        ? _deepLinkMethods[rng.nextInt(_deepLinkMethods.length)]
        : 'unknown_method_${rng.nextInt(1000)}';
  }
  return AgentStep(
    id: 's$i',
    kind: kind,
    strategy: kind.strategy,
    narration: '$verb something',
    targetPackage: 'pkg',
    query: kind.strategy == ActionStrategy.uiAction
        ? const NodeQuery(text: 'x')
        : null,
    value: kind == StepKind.setNodeText ? 'v' : null,
    scrollDirection: kind == StepKind.scrollNode
        ? ScrollDirection.forward
        : null,
    deepLinkMethod: method,
  );
}

AgentPlan _genPlan(Random rng) {
  final count = rng.nextInt(20); // 0..19 — spans over and under the budget
  return AgentPlan(
    commandText: 'cmd',
    steps: [for (var i = 0; i < count; i++) _genStep(rng, i)],
    summary: 'summary',
    source: PlannerSource.rule,
  );
}

void main() {
  group('Property 1: Plan length is bounded (interactive-agent-mode)', () {
    test('resolved plan never exceeds the step budget', () {
      final rng = Random(0xA1);
      for (var i = 0; i < _iterations; i++) {
        final resolved = _resolver.resolve(_genPlan(rng));
        expect(
          resolved.steps.length,
          lessThanOrEqualTo(_budgets.stepBudget),
          reason: 'a resolved plan must fit the step budget',
        );
      }
    });

    test('a plan over budget is marked truncated', () {
      final rng = Random(0xA2);
      final big = AgentPlan(
        commandText: 'cmd',
        steps: [for (var i = 0; i < 20; i++) _genStep(rng, i)],
        summary: 's',
        source: PlannerSource.rule,
      );
      final resolved = _resolver.resolve(big);
      expect(resolved.wasTruncated, isTrue);
      expect(resolved.steps.length, _budgets.stepBudget);
    });
  });

  group(
    'Property 2: exactly one strategy, deep-link preferred '
    '(interactive-agent-mode)',
    () {
      test('every step has a strategy and deep-link wins when available', () {
        final rng = Random(0xB1);
        for (var i = 0; i < _iterations; i++) {
          final resolved = _resolver.resolve(_genPlan(rng));
          for (final step in resolved.steps) {
            // Exactly one strategy is intrinsic to the type; assert consistency
            // with the deep-link preference rule.
            final canDeepLink = _resolver.hasDeepLinkFor(
              step.kind,
              step.deepLinkMethod,
            );
            if (canDeepLink) {
              expect(
                step.strategy,
                ActionStrategy.deepLink,
                reason:
                    'a step with a matching deep-link capability must resolve '
                    'to deepLink: $step',
              );
            }
            // UI-action kinds can never be deep-linked.
            if (step.kind.strategy == ActionStrategy.uiAction) {
              expect(step.strategy, ActionStrategy.uiAction);
            }
          }
        }
      });
    },
  );

  group('Property 3: irreversible steps are marked (interactive-agent-mode)', () {
    test('any irreversible verb yields an irreversible step', () {
      final rng = Random(0xC1);
      for (var i = 0; i < _iterations; i++) {
        final verb = _irreversibleVerbs[rng.nextInt(_irreversibleVerbs.length)];
        final plan = AgentPlan(
          commandText: 'cmd',
          steps: [
            AgentStep(
              id: 's1',
              kind: StepKind.deepLinkAction,
              strategy: ActionStrategy.deepLink,
              narration: '$verb it now',
              deepLinkMethod: 'sendWhatsApp',
            ),
          ],
          summary: 's',
          source: PlannerSource.rule,
        );
        final resolved = _resolver.resolve(plan);
        expect(
          resolved.steps.single.isIrreversible,
          isTrue,
          reason: 'verb "$verb" must be classified irreversible',
        );
      }
    });

    test('money and security methods are always irreversible', () {
      for (final method in ['makeUpiPayment', 'orderFood']) {
        final resolved = _resolver.resolve(
          AgentPlan(
            commandText: 'cmd',
            steps: [
              AgentStep(
                id: 's1',
                kind: StepKind.deepLinkAction,
                strategy: ActionStrategy.deepLink,
                narration: 'do it',
                deepLinkMethod: method,
              ),
            ],
            summary: 's',
            source: PlannerSource.rule,
          ),
        );
        expect(resolved.steps.single.isIrreversible, isTrue, reason: method);
      }
    });
  });
}
