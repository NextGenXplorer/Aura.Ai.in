// Tests for ModelPlanner strict parsing.
//
// Feature: interactive-agent-mode, Property 11
//
// A model-produced plan containing an unknown step kind is rejected wholesale,
// never partially executed.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/features/interactive_agent/models/agent_plan.dart';
import 'package:aura_mobile/features/interactive_agent/models/agent_step.dart';
import 'package:aura_mobile/features/interactive_agent/planning/model_planner.dart';

const _iterations = 200;
const _validKinds = [
  'openApp',
  'deepLinkAction',
  'tapNode',
  'setNodeText',
  'scrollNode',
  'pressBack',
  'goHome',
];

void main() {
  group('Property 11: unknown step kinds reject the whole plan', () {
    test('a plan with any unknown kind returns null', () {
      final rng = Random(0xB11);
      for (var i = 0; i < _iterations; i++) {
        final n = 1 + rng.nextInt(5);
        final badIndex = rng.nextInt(n);
        final steps = [
          for (var s = 0; s < n; s++)
            '{"kind": "${s == badIndex ? 'frobnicate_$s' : _validKinds[rng.nextInt(_validKinds.length)]}", '
                '"narration": "step $s"}',
        ];
        final raw = '{"summary": "x", "steps": [${steps.join(',')}]}';
        final plan = ModelPlanner.parsePlan('cmd', raw);
        expect(
          plan,
          isNull,
          reason: 'an unknown kind at index $badIndex must reject the plan',
        );
      }
    });

    test('an all-valid plan parses with model source', () {
      const raw = '''
      {"summary": "Open WhatsApp and send",
       "steps": [
         {"kind": "openApp", "narration": "Open WhatsApp", "targetPackage": "whatsapp"},
         {"kind": "tapNode", "narration": "Tap search", "query": {"text": "Search"}}
       ]}''';
      final plan = ModelPlanner.parsePlan('cmd', raw);
      expect(plan, isNotNull);
      expect(plan!.source, PlannerSource.model);
      expect(plan.steps, hasLength(2));
      expect(plan.steps[0].kind, StepKind.openApp);
      expect(plan.steps[1].kind, StepKind.tapNode);
    });

    test('prose around the JSON is tolerated', () {
      const raw =
          'Sure! Here is the plan:\n'
          '{"summary": "s", "steps": [{"kind": "goHome", "narration": "home"}]}\n'
          'Let me know if that works.';
      final plan = ModelPlanner.parsePlan('cmd', raw);
      expect(plan, isNotNull);
      expect(plan!.steps.single.kind, StepKind.goHome);
    });

    test('non-JSON, empty steps, and malformed input return null', () {
      expect(ModelPlanner.parsePlan('cmd', 'no json here'), isNull);
      expect(ModelPlanner.parsePlan('cmd', '{"steps": []}'), isNull);
      expect(ModelPlanner.parsePlan('cmd', '{"steps": "notalist"}'), isNull);
      expect(ModelPlanner.parsePlan('cmd', '{broken'), isNull);
    });

    test('plan() returns null when the model call throws', () async {
      final planner = ModelPlanner((_) async => throw StateError('offline'));
      expect(await planner.plan('cmd'), isNull);
    });

    test('plan() parses a well-formed model response', () async {
      final planner = ModelPlanner(
        (_) async =>
            '{"summary": "s", "steps": [{"kind": "openApp", "narration": "open"}]}',
      );
      final plan = await planner.plan('open maps');
      expect(plan, isNotNull);
      expect(plan!.source, PlannerSource.model);
    });
  });
}
