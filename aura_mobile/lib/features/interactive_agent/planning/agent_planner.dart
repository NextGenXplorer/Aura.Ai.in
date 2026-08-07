/// Planner interface and the context passed to planners.
///
/// Feature: interactive-agent-mode
library;

import '../models/agent_plan.dart';

/// Context a planner may consult when building a plan.
class PlanningContext {
  /// Package names of apps installed on the device, lower-cased common names
  /// mapped to package ids where known. Used to reject commands naming an app
  /// that is not installed (Req 3.7) and to resolve common names (Req 3.6).
  final Map<String, String> installedApps;

  const PlanningContext({this.installedApps = const {}});
}

/// A planner turns one command into a plan, or returns null when it cannot
/// handle the command (Req 4.5, 4.6).
abstract interface class AgentPlanner {
  Future<AgentPlan?> plan(String command, PlanningContext context);
}
