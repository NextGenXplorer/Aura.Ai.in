/// Model-based planner, used only when the active model supports tool calling
/// and the rule planner returned nothing (Req 4.4, 4.5). Parsing is strict: a
/// plan containing any step kind outside [StepKind] is rejected whole, never
/// partially executed (Req 4.7 / Property 11).
///
/// Feature: interactive-agent-mode (Task 9.1)
library;

import 'dart:convert';

import '../agent_budgets.dart';
import '../models/agent_plan.dart';
import '../models/agent_step.dart';

/// Produces raw model output for a planning prompt. Injected so the planner is
/// testable without a model, and so the caller controls which LLM/session runs.
typedef ModelGenerate = Future<String> Function(String prompt);

class ModelPlanner {
  final ModelGenerate generate;

  const ModelPlanner(this.generate);

  /// The step schema shown to the model. Only these kinds are permitted; any
  /// other is rejected at parse time.
  static const String schema = '''
Respond ONLY with a JSON object: {"summary": "...", "steps": [ ... ]}.
Each step is {"kind": "<kind>", "narration": "...", ...}. Allowed kinds:
  openApp        {"targetPackage": "<app>"}
  deepLinkAction {"deepLinkMethod": "<method>", "deepLinkArgs": {..}}
  tapNode        {"query": {"text": "..."}}
  setNodeText    {"query": {"viewId": "..."}, "value": "..."}
  scrollNode     {"query": {"viewId": "..."}, "scrollDirection": "forward|backward"}
  pressBack      {}
  goHome         {}
Output no prose, only the JSON object.''';

  Future<AgentPlan?> plan(String command) async {
    final prompt = '$schema\n\nCommand: $command';
    final String raw;
    try {
      raw = await generate(prompt);
    } catch (_) {
      return null;
    }
    return parsePlan(command, raw);
  }

  /// Pure parse: raw model text → plan, or null if unparseable or containing an
  /// unknown step kind. Extracted so Property 11 tests it directly.
  static AgentPlan? parsePlan(String command, String raw) {
    final jsonText = _extractJsonObject(raw);
    if (jsonText == null) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final rawSteps = decoded['steps'];
    if (rawSteps is! List || rawSteps.isEmpty) return null;

    final steps = <AgentStep>[];
    for (var i = 0; i < rawSteps.length; i++) {
      final raw = rawSteps[i];
      if (raw is! Map) return null;
      final kind = StepKind.fromId(raw['kind']?.toString());
      // Unknown step kind → reject the WHOLE plan (Req 4.7 / Property 11).
      if (kind == null) return null;

      final query = _parseQuery(raw['query']);
      final scroll = _parseScroll(raw['scrollDirection']);
      steps.add(
        AgentStep(
          id: 's$i',
          kind: kind,
          strategy: kind.strategy,
          narration: raw['narration']?.toString() ?? kind.name,
          targetPackage: raw['targetPackage']?.toString(),
          query: query,
          value: raw['value']?.toString(),
          scrollDirection: scroll,
          deepLinkMethod: raw['deepLinkMethod']?.toString(),
          deepLinkArgs: _parseArgs(raw['deepLinkArgs']),
        ),
      );
    }

    if (steps.length > AgentBudgets.defaults.stepBudget * 2) {
      // Absurdly long emissions are rejected outright; the resolver would
      // truncate, but a plan this size signals a bad emission.
      return null;
    }

    return AgentPlan(
      commandText: command,
      steps: steps,
      summary: decoded['summary']?.toString() ?? 'Run $command',
      source: PlannerSource.model,
    );
  }

  static NodeQuery? _parseQuery(Object? raw) {
    if (raw is! Map) return null;
    final viewId = raw['viewId']?.toString();
    final text = raw['text']?.toString();
    final desc = raw['contentDescription']?.toString();
    if (viewId == null && text == null && desc == null) return null;
    return NodeQuery(
      viewId: viewId,
      text: text,
      contentDescription: desc,
      requireEditable: raw['requireEditable'] == true,
      requireClickable: raw['requireClickable'] == true,
    );
  }

  static ScrollDirection? _parseScroll(Object? raw) {
    switch (raw?.toString()) {
      case 'forward':
        return ScrollDirection.forward;
      case 'backward':
        return ScrollDirection.backward;
      default:
        return null;
    }
  }

  static Map<String, String> _parseArgs(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        entry.key.toString(): entry.value?.toString() ?? '',
    };
  }

  /// Extracts the first balanced `{...}` JSON object from [raw], tolerating
  /// leading/trailing prose a model may add despite instructions.
  static String? _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    for (var i = start; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) return raw.substring(start, i + 1);
      }
    }
    return null;
  }
}
