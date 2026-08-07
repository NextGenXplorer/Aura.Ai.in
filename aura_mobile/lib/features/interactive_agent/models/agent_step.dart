/// Core step model for Interactive Agent Mode.
///
/// A step is the atomic unit of a plan: exactly one operation, resolved to
/// exactly one [ActionStrategy] at plan time. Steps are immutable and inspectable
/// so a plan can be previewed, budgeted, and aborted at a step boundary without
/// any of the execution machinery running.
///
/// Feature: interactive-agent-mode
library;

import 'package:flutter/foundation.dart';

/// How a step is carried out. Exactly one per step (Req 4.7, 5.1, 5.2).
enum ActionStrategy {
  /// Satisfied by an Android intent / deep link — near-instant, no screen
  /// reading, no accessibility permission required.
  deepLink,

  /// Satisfied by driving another app's UI through the accessibility service.
  /// Used only when no deep-link action can satisfy the step.
  uiAction,
}

/// The concrete operation a step performs. The strategy each kind belongs to is
/// fixed and exposed by [strategyFor].
enum StepKind {
  // deepLink strategy
  openApp,
  deepLinkAction,

  // uiAction strategy
  tapNode,
  setNodeText,
  scrollNode,
  pressBack,
  goHome;

  /// The strategy this kind always executes under.
  ActionStrategy get strategy => switch (this) {
    StepKind.openApp || StepKind.deepLinkAction => ActionStrategy.deepLink,
    StepKind.tapNode ||
    StepKind.setNodeText ||
    StepKind.scrollNode ||
    StepKind.pressBack ||
    StepKind.goHome => ActionStrategy.uiAction,
  };

  /// Parses a wire/string name into a [StepKind], or null when unknown. Used to
  /// reject model-produced plans containing step kinds outside this set
  /// (Req 4.7) rather than partially executing them.
  static StepKind? fromId(String? id) {
    if (id == null) return null;
    for (final kind in StepKind.values) {
      if (kind.name == id) return kind;
    }
    return null;
  }
}

/// When a targeted node query returns more than one match, how to choose
/// (Req 6.5) — never arbitrary.
enum NodeDisambiguation {
  /// Take the first match in reading order.
  firstInReadingOrder,

  /// Only proceed when the match is unique; multiple matches fail the step.
  onlyIfUnique,
}

/// Scroll direction for a [StepKind.scrollNode] step.
enum ScrollDirection { forward, backward }

/// A bounded lookup for a node by id, text, or content description, without
/// walking the whole tree (Req 6.2, 6.3).
@immutable
class NodeQuery {
  final String? viewId;
  final String? text;
  final String? contentDescription;
  final bool requireEditable;
  final bool requireClickable;
  final NodeDisambiguation onMultiple;

  const NodeQuery({
    this.viewId,
    this.text,
    this.contentDescription,
    this.requireEditable = false,
    this.requireClickable = false,
    this.onMultiple = NodeDisambiguation.firstInReadingOrder,
  }) : assert(
         viewId != null || text != null || contentDescription != null,
         'A NodeQuery must constrain at least one of viewId, text, or '
         'contentDescription.',
       );

  Map<String, Object?> toWire() => {
    if (viewId != null) 'viewId': viewId,
    if (text != null) 'text': text,
    if (contentDescription != null) 'contentDescription': contentDescription,
    'requireEditable': requireEditable,
    'requireClickable': requireClickable,
  };

  @override
  bool operator ==(Object other) =>
      other is NodeQuery &&
      other.viewId == viewId &&
      other.text == text &&
      other.contentDescription == contentDescription &&
      other.requireEditable == requireEditable &&
      other.requireClickable == requireClickable &&
      other.onMultiple == onMultiple;

  @override
  int get hashCode => Object.hash(
    viewId,
    text,
    contentDescription,
    requireEditable,
    requireClickable,
    onMultiple,
  );

  @override
  String toString() =>
      'NodeQuery(viewId: $viewId, text: $text, '
      'contentDescription: $contentDescription)';
}

/// What must hold after a step for it to count as done (Req 6.6). A null
/// post-condition means "no verification needed beyond dispatch success".
@immutable
sealed class PostCondition {
  const PostCondition();
}

/// The screen structure changed (signature differs from before the step).
class SignatureChanged extends PostCondition {
  const SignatureChanged();
}

/// The foreground package became [packageName].
class PackageBecomes extends PostCondition {
  final String packageName;
  const PackageBecomes(this.packageName);
}

/// A node matching [query] now exists on screen.
class NodeExists extends PostCondition {
  final NodeQuery query;
  const NodeExists(this.query);
}

/// A node matching [query] now holds exactly [value].
class NodeTextEquals extends PostCondition {
  final NodeQuery query;
  final String value;
  const NodeTextEquals(this.query, this.value);
}

/// One atomic operation in a plan.
@immutable
class AgentStep {
  /// Stable within a plan.
  final String id;
  final StepKind kind;

  /// The strategy this step executes under. Always equals `kind.strategy`;
  /// stored so a resolved plan is self-describing.
  final ActionStrategy strategy;

  /// Shown and optionally spoken before the step executes (Req 10.1).
  final String narration;

  /// Marked at plan time (Req 4.8). Irreversible steps require a confirmation
  /// gate before executing (Req 9.1).
  final bool isIrreversible;

  final String? targetPackage;

  /// Present only for [ActionStrategy.uiAction] steps.
  final NodeQuery? query;

  /// The value written by a [StepKind.setNodeText] step.
  final String? value;

  /// Scroll direction for a [StepKind.scrollNode] step.
  final ScrollDirection? scrollDirection;

  /// The `com.aura.ai/app_control` method a [StepKind.deepLinkAction] delegates
  /// to (Req 5.3).
  final String? deepLinkMethod;
  final Map<String, String> deepLinkArgs;

  final PostCondition? postCondition;

  const AgentStep({
    required this.id,
    required this.kind,
    required this.strategy,
    required this.narration,
    this.isIrreversible = false,
    this.targetPackage,
    this.query,
    this.value,
    this.scrollDirection,
    this.deepLinkMethod,
    this.deepLinkArgs = const {},
    this.postCondition,
  });

  AgentStep copyWith({
    ActionStrategy? strategy,
    bool? isIrreversible,
    PostCondition? postCondition,
  }) => AgentStep(
    id: id,
    kind: kind,
    strategy: strategy ?? this.strategy,
    narration: narration,
    isIrreversible: isIrreversible ?? this.isIrreversible,
    targetPackage: targetPackage,
    query: query,
    value: value,
    scrollDirection: scrollDirection,
    deepLinkMethod: deepLinkMethod,
    deepLinkArgs: deepLinkArgs,
    postCondition: postCondition ?? this.postCondition,
  );

  @override
  String toString() =>
      'AgentStep($id, $kind, $strategy, irreversible: $isIrreversible)';
}
