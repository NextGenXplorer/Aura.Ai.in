/// Resolves a raw plan into an executable one: assigns exactly one action
/// strategy per step (deep-link preferred), marks irreversible steps, and
/// enforces the step budget.
///
/// Pure and synchronous — the whole class is directly testable.
///
/// Feature: interactive-agent-mode
library;

import '../agent_budgets.dart';
import '../models/agent_plan.dart';
import '../models/agent_step.dart';

class StrategyResolver {
  final AgentBudgets budgets;

  const StrategyResolver({this.budgets = AgentBudgets.defaults});

  /// The `com.aura.ai/app_control` methods that already satisfy a step via a
  /// deep link (Req 5.3). A step whose kind is `deepLinkAction` and whose
  /// method is in this set is dispatched as a deep link rather than reimplemented.
  static const Set<String> deepLinkMethods = {
    'openApp',
    'openSettings',
    'openCamera',
    'sendWhatsApp',
    'searchOnApp',
    'makeUpiPayment',
    'playOnSpotify',
    'bookRide',
    'orderFood',
    'shareText',
    'openProfile',
    'dialContact',
    'sendSMS',
    'launchEmailApp',
  };

  /// True when a deep-link capability can satisfy a step of [kind] targeting
  /// [method]. `openApp` is always deep-linkable; a `deepLinkAction` is
  /// deep-linkable when its method is a known capability.
  bool hasDeepLinkFor(StepKind kind, String? method) {
    switch (kind) {
      case StepKind.openApp:
        return true;
      case StepKind.deepLinkAction:
        return method != null && deepLinkMethods.contains(method);
      case StepKind.tapNode:
      case StepKind.setNodeText:
      case StepKind.scrollNode:
      case StepKind.pressBack:
      case StepKind.goHome:
        return false;
    }
  }

  /// Resolves [raw]: every step gets exactly one strategy (deep-link whenever
  /// [hasDeepLinkFor] is true), every step is irreversibility-marked, and the
  /// plan is truncated to the step budget (Req 4.7, 4.8, 5.1, 5.2, 12.1).
  AgentPlan resolve(AgentPlan raw) {
    final resolved = <AgentStep>[];
    for (final step in raw.steps) {
      final preferDeepLink = hasDeepLinkFor(step.kind, step.deepLinkMethod);
      // A step kind fixes its own strategy; deep-link preference only applies
      // where the kind itself is a deep-link kind. UI-action kinds always
      // resolve to uiAction because no deep link can satisfy them.
      final strategy = preferDeepLink
          ? ActionStrategy.deepLink
          : step.kind.strategy;

      final irreversible =
          step.isIrreversible ||
          isIrreversibleStep(
            kind: step.kind,
            deepLinkMethod: step.deepLinkMethod,
            intentVerb: step.narration,
          );

      resolved.add(
        step.copyWith(strategy: strategy, isIrreversible: irreversible),
      );
    }

    var truncated = false;
    var finalSteps = resolved;
    if (resolved.length > budgets.stepBudget) {
      finalSteps = resolved.sublist(0, budgets.stepBudget);
      truncated = true;
    }

    return raw.copyWith(steps: finalSteps, wasTruncated: truncated);
  }
}
