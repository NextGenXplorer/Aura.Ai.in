/// Budget constants and the irreversible-step classification for Interactive
/// Agent Mode. Referenced by the runner and by the property tests that enforce
/// them, so the numbers live in exactly one place.
///
/// Feature: interactive-agent-mode
library;

import 'package:flutter/foundation.dart';

import 'models/agent_step.dart';

@immutable
class AgentBudgets {
  /// Maximum executed steps per run (Req 12.1).
  final int stepBudget;

  /// Maximum wall-clock execution per run, excluding gate waits (Req 12.2, 12.5).
  final Duration timeBudget;

  /// Maximum wait for a screen to settle after a step (Req 12.6).
  final Duration settleTimeout;

  /// A screen counts as settled once its signature is unchanged for this long
  /// (Req 7.5).
  final Duration settleQuietInterval;

  /// Maximum recovery retries per step (Req 12.7).
  final int maxRecoveryRetries;

  /// Rule-based planning must finish within this budget (Req 13.3).
  final Duration rulePlanBudget;

  /// Model-based planning timeout before falling back (Req 13.4).
  final Duration modelPlanTimeout;

  /// Deep-link dispatch budget, excluding target app launch (Req 13.5).
  final Duration deepLinkDispatchBudget;

  /// Targeted node query budget (Req 13.6).
  final Duration nodeQueryBudget;

  /// Bounds on the signature shallow walk (Req 13.6, 13.9, D2).
  final int signatureWalkDepth;
  final int signatureWalkNodes;

  /// A confirmation gate that goes unanswered this long is treated as declined
  /// (Req 9.5).
  final Duration gateTimeout;

  /// Fixed diagnostics ring size so a long session cannot grow memory without
  /// bound (Req 13.10).
  final int diagnosticsRingSize;

  const AgentBudgets({
    this.stepBudget = 12,
    this.timeBudget = const Duration(seconds: 90),
    this.settleTimeout = const Duration(seconds: 5),
    this.settleQuietInterval = const Duration(milliseconds: 350),
    this.maxRecoveryRetries = 2,
    this.rulePlanBudget = const Duration(milliseconds: 300),
    this.modelPlanTimeout = const Duration(seconds: 6),
    this.deepLinkDispatchBudget = const Duration(milliseconds: 400),
    this.nodeQueryBudget = const Duration(milliseconds: 150),
    this.signatureWalkDepth = 6,
    this.signatureWalkNodes = 40,
    this.gateTimeout = const Duration(seconds: 45),
    this.diagnosticsRingSize = 64,
  });

  static const AgentBudgets defaults = AgentBudgets();
}

/// The set of step kinds that are always irreversible regardless of content.
const Set<StepKind> _alwaysIrreversibleKinds = {};

/// Classifies whether a step is irreversible and therefore requires a
/// confirmation gate (Req 4.8, 9.1, 9.2).
///
/// Irreversibility for UI/deep-link steps is content-driven: the same
/// [StepKind.deepLinkAction] can open a search (reversible) or send a payment
/// (irreversible). Classification therefore inspects the intent verb carried by
/// the step's deep-link method / narration, matched against a fixed set of
/// irreversible verbs: send, call, pay/transfer, order/buy/purchase, delete,
/// and security/permission changes (Req 9.2).
///
/// This predicate is the single source of truth; the resolver calls it, and
/// Property 3 and Property 14 assert against it.
bool isIrreversibleStep({
  required StepKind kind,
  String? deepLinkMethod,
  String? intentVerb,
}) {
  if (_alwaysIrreversibleKinds.contains(kind)) return true;

  final haystack = [
    kind.name,
    deepLinkMethod ?? '',
    intentVerb ?? '',
  ].join(' ').toLowerCase();

  return _irreversiblePattern.hasMatch(haystack);
}

/// Word-boundary matches for the irreversible verb set. Deliberately broad on
/// money and security so those can never slip through (Req 9.7).
final RegExp _irreversiblePattern = RegExp(
  r'\b('
  // transmit a message
  r'send|sendwhatsapp|sendsms|sendmessage|post|submit|reply|'
  // place a call
  r'call|dial|placecall|'
  // move money
  r'pay|payment|makeupipayment|upi|transfer|send\s*money|checkout|'
  // order / purchase
  r'order|orderfood|buy|purchase|book|bookride|confirm\s*order|placeorder|'
  // delete / destroy
  r'delete|remove|erase|clear\s*all|uninstall|wipe|'
  // security / permission
  r'grant|revoke|disable\s*(lock|security)|change\s*password|'
  r'security|permission'
  r')\b',
  caseSensitive: false,
);
