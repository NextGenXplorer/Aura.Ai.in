import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/presentation/providers/model_catalog_grouping.dart';

// Feature: multi-engine-ai-models, Property 17: Capability badge derivation.
//
// "For any model, the set of capability badges the Model_Selector displays
//  equals exactly the set of qualifying capabilities: the tool-calling badge
//  if and only if supportsToolCalling is true, the vision badge if and only if
//  supportsVision is true, and the fast badge if and only if the inference
//  speed is the highest-speed value (fast)."
//
// Validates: Requirements 6.2, 6.3, 6.4, 6.5
//
// This property test generates random ModelInfo objects with various
// combinations of capability flags (supportsToolCalling, supportsVision,
// inferenceSpeed) and verifies that qualifyingBadges returns exactly the
// correct set of CapabilityBadge values — no more, no fewer.
//
// Uses the generator-based approach (Random + iterations >= 100), NOT glados.

const int _iterations = 200;

/// Generates a random ModelInfo with arbitrary capability flags.
ModelInfo _randomModelInfo(Random rng) {
  final supportsToolCalling = rng.nextBool();
  final supportsVision = rng.nextBool();
  final inferenceSpeed =
      InferenceSpeed.values[rng.nextInt(InferenceSpeed.values.length)];
  final engine = AIEngine.values[rng.nextInt(AIEngine.values.length)];

  return ModelInfo(
    id: 'test-model-${rng.nextInt(100000)}',
    name: 'Test Model',
    description: 'A randomly generated test model',
    url: 'https://example.com/model.bin',
    sizeBytes: 100000000 + rng.nextInt(4000000000),
    ramRequirement: '${1 + rng.nextInt(16)}GB',
    speed: 'Medium',
    fileName: 'test-model-${rng.nextInt(100000)}.gguf',
    minRamMB: 512 + rng.nextInt(8192),
    engine: engine,
    supportsToolCalling: supportsToolCalling,
    supportsVision: supportsVision,
    inferenceSpeed: inferenceSpeed,
  );
}

/// Computes the expected badge set from capability flags directly, serving as
/// an independent oracle against which qualifyingBadges is checked.
Set<CapabilityBadge> _expectedBadges(ModelInfo model) {
  return {
    if (model.supportsToolCalling) CapabilityBadge.toolCalling,
    if (model.supportsVision) CapabilityBadge.vision,
    if (model.inferenceSpeed == InferenceSpeed.fast) CapabilityBadge.fast,
  };
}

void main() {
  group('Property 17: Capability badge derivation '
      '(multi-engine-ai-models)', () {
    // --- Property: tool-calling badge present iff supportsToolCalling is true
    // (Req 6.2) ---
    test('tool-calling badge present iff supportsToolCalling is true', () {
      final rng = Random(0xBEEF);
      for (var i = 0; i < _iterations; i++) {
        final model = _randomModelInfo(rng);
        final badges = qualifyingBadges(model);

        if (model.supportsToolCalling) {
          expect(badges.contains(CapabilityBadge.toolCalling), isTrue,
              reason: 'model with supportsToolCalling=true must have '
                  'toolCalling badge (iteration $i)');
        } else {
          expect(badges.contains(CapabilityBadge.toolCalling), isFalse,
              reason: 'model with supportsToolCalling=false must NOT have '
                  'toolCalling badge (iteration $i)');
        }
      }
    });

    // --- Property: vision badge present iff supportsVision is true
    // (Req 6.3) ---
    test('vision badge present iff supportsVision is true', () {
      final rng = Random(0xCAFE);
      for (var i = 0; i < _iterations; i++) {
        final model = _randomModelInfo(rng);
        final badges = qualifyingBadges(model);

        if (model.supportsVision) {
          expect(badges.contains(CapabilityBadge.vision), isTrue,
              reason: 'model with supportsVision=true must have '
                  'vision badge (iteration $i)');
        } else {
          expect(badges.contains(CapabilityBadge.vision), isFalse,
              reason: 'model with supportsVision=false must NOT have '
                  'vision badge (iteration $i)');
        }
      }
    });

    // --- Property: fast badge present iff inferenceSpeed == fast
    // (Req 6.4) ---
    test('fast badge present iff inferenceSpeed is fast', () {
      final rng = Random(0xFACE);
      for (var i = 0; i < _iterations; i++) {
        final model = _randomModelInfo(rng);
        final badges = qualifyingBadges(model);

        if (model.inferenceSpeed == InferenceSpeed.fast) {
          expect(badges.contains(CapabilityBadge.fast), isTrue,
              reason: 'model with inferenceSpeed=fast must have '
                  'fast badge (iteration $i)');
        } else {
          expect(badges.contains(CapabilityBadge.fast), isFalse,
              reason: 'model with inferenceSpeed!=fast must NOT have '
                  'fast badge (iteration $i)');
        }
      }
    });

    // --- Property: badge set equals exactly the qualifying capabilities
    // (Req 6.5: concurrent display of all qualifying badges) ---
    test('badge set equals exactly the set of qualifying capabilities', () {
      final rng = Random(0xD00D);
      for (var i = 0; i < _iterations; i++) {
        final model = _randomModelInfo(rng);
        final badges = qualifyingBadges(model);
        final expected = _expectedBadges(model);

        expect(badges, expected,
            reason: 'model (toolCalling=${model.supportsToolCalling}, '
                'vision=${model.supportsVision}, '
                'speed=${model.inferenceSpeed}) '
                'expected badges $expected but got $badges (iteration $i)');
      }
    });

    // --- Exhaustive: all 2x2x3 = 12 flag combinations produce correct
    // badge sets. ---
    test('all 12 flag combinations produce correct badge sets', () {
      for (final toolCalling in [true, false]) {
        for (final vision in [true, false]) {
          for (final speed in InferenceSpeed.values) {
            final model = ModelInfo(
              id: 'combo-tc$toolCalling-v$vision-s${speed.name}',
              name: 'Combo Model',
              description: 'Exhaustive combination test',
              url: 'https://example.com/model.bin',
              sizeBytes: 500000000,
              ramRequirement: '4GB',
              speed: 'Medium',
              fileName: 'combo.gguf',
              minRamMB: 4096,
              supportsToolCalling: toolCalling,
              supportsVision: vision,
              inferenceSpeed: speed,
            );

            final badges = qualifyingBadges(model);
            final expected = _expectedBadges(model);

            expect(badges, expected,
                reason: 'combination (toolCalling=$toolCalling, '
                    'vision=$vision, speed=${speed.name}) '
                    'expected $expected but got $badges');
          }
        }
      }
    });

    // --- Verify on real catalog models that badges match expectations ---
    test('real catalog models have correct badges', () {
      for (final model in modelCatalog) {
        final badges = qualifyingBadges(model);
        final expected = _expectedBadges(model);

        expect(badges, expected,
            reason: 'catalog model "${model.id}" '
                '(toolCalling=${model.supportsToolCalling}, '
                'vision=${model.supportsVision}, '
                'speed=${model.inferenceSpeed}) '
                'expected $expected but got $badges');
      }
    });

    // --- No spurious badges: the returned set contains only defined
    // CapabilityBadge values (a model with no capabilities gets empty set) ---
    test('model with no capabilities gets empty badge set', () {
      final rng = Random(0xABC1);
      for (var i = 0; i < _iterations; i++) {
        final model = ModelInfo(
          id: 'no-caps-${rng.nextInt(100000)}',
          name: 'No Capabilities',
          description: 'Model with no qualifying capabilities',
          url: 'https://example.com/model.bin',
          sizeBytes: 100000000 + rng.nextInt(4000000000),
          ramRequirement: '2GB',
          speed: 'Slow',
          fileName: 'no-caps.gguf',
          minRamMB: 2048,
          engine: AIEngine.values[rng.nextInt(AIEngine.values.length)],
          supportsToolCalling: false,
          supportsVision: false,
          // medium or slow — neither qualifies for fast badge
          inferenceSpeed: rng.nextBool()
              ? InferenceSpeed.medium
              : InferenceSpeed.slow,
        );

        final badges = qualifyingBadges(model);
        expect(badges, isEmpty,
            reason: 'model with no qualifying capabilities must have '
                'empty badge set (iteration $i)');
      }
    });

    // --- All capabilities true + fast speed => all three badges ---
    test('model with all capabilities gets all three badges', () {
      final rng = Random(0xFFFF);
      for (var i = 0; i < _iterations; i++) {
        final model = ModelInfo(
          id: 'all-caps-${rng.nextInt(100000)}',
          name: 'All Capabilities',
          description: 'Model with all qualifying capabilities',
          url: 'https://example.com/model.bin',
          sizeBytes: 100000000 + rng.nextInt(4000000000),
          ramRequirement: '8GB',
          speed: 'Fast',
          fileName: 'all-caps.gguf',
          minRamMB: 8192,
          engine: AIEngine.values[rng.nextInt(AIEngine.values.length)],
          supportsToolCalling: true,
          supportsVision: true,
          inferenceSpeed: InferenceSpeed.fast,
        );

        final badges = qualifyingBadges(model);
        expect(badges.length, 3,
            reason: 'model with all capabilities must have 3 badges '
                '(iteration $i)');
        expect(badges.contains(CapabilityBadge.toolCalling), isTrue);
        expect(badges.contains(CapabilityBadge.vision), isTrue);
        expect(badges.contains(CapabilityBadge.fast), isTrue);
      }
    });
  });
}
