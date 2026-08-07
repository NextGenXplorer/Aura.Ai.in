/// A plan: an ordered, finite, inspectable list of steps derived from one user
/// command before execution begins.
///
/// Feature: interactive-agent-mode
library;

import 'package:flutter/foundation.dart';

import 'agent_step.dart';

/// Which planner produced a plan.
enum PlannerSource { rule, model }

@immutable
class AgentPlan {
  final String commandText;

  /// Ordered steps. After resolution this is at most the step budget in length
  /// (Req 12.1).
  final List<AgentStep> steps;

  /// Human-readable summary shown before the first step executes (Req 4.3).
  final String summary;

  final PlannerSource source;

  /// True when the plan was truncated to fit the step budget, so the UI can say
  /// the remaining intent was dropped (Req 12.3).
  final bool wasTruncated;

  const AgentPlan({
    required this.commandText,
    required this.steps,
    required this.summary,
    required this.source,
    this.wasTruncated = false,
  });

  bool get isEmpty => steps.isEmpty;
  int get length => steps.length;

  AgentPlan copyWith({List<AgentStep>? steps, bool? wasTruncated}) => AgentPlan(
    commandText: commandText,
    steps: steps ?? this.steps,
    summary: summary,
    source: source,
    wasTruncated: wasTruncated ?? this.wasTruncated,
  );

  @override
  String toString() =>
      'AgentPlan(${steps.length} steps, source: $source, '
      'truncated: $wasTruncated)';
}
