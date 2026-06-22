import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';

// Feature: multi-engine-ai-models, Property 5: GGUF model tier mapping
//
// "For any GGUF model file name, modelTier returns exactly one of small,
//  medium, or large, returning small when the name encodes 0.5B, medium when
//  it encodes 1.5B, and large otherwise."
//
// Validates: Requirements 2.6
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. Each
// property runs >= 100 generated cases.

const int _iterations = 250;

/// The size markers the production mapping recognizes for the small/medium tiers.
const _smallMarkers = ['0.5b', '0_5b'];
const _mediumMarkers = ['1.5b', '1_5b'];

/// Characters used to build random "noise" around the (optional) size marker.
/// Deliberately excludes the digits/separators that could accidentally form a
/// `0.5b` / `1.5b` marker, so generated noise never collides with the markers.
const _noiseAlphabet = 'abcefghijklmnopqrstuvwxyzABCEFGHIJKLMNOPQRSTUVWXYZ-/\\';

/// Generates a random noise fragment guaranteed not to contain any size marker.
String _randomNoise(Random rng, int maxLen) {
  final len = rng.nextInt(maxLen + 1);
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.write(_noiseAlphabet[rng.nextInt(_noiseAlphabet.length)]);
  }
  return sb.toString();
}

/// Randomly varies the case of a marker so the case-insensitivity is exercised.
String _randomCase(Random rng, String s) {
  final sb = StringBuffer();
  for (final ch in s.split('')) {
    sb.write(rng.nextBool() ? ch.toUpperCase() : ch.toLowerCase());
  }
  return sb.toString();
}

/// Embeds [marker] between random noise to build a realistic file name.
String _embed(Random rng, String marker) {
  final ext = rng.nextBool() ? '.gguf' : '';
  return '${_randomNoise(rng, 20)}$marker${_randomNoise(rng, 20)}$ext';
}

void main() {
  group('Property 5: GGUF model tier mapping (multi-engine-ai-models)', () {
    test('result is always exactly one of small/medium/large for any name', () {
      final rng = Random(20240501);
      const tiers = {ModelTier.small, ModelTier.medium, ModelTier.large};
      for (var i = 0; i < _iterations; i++) {
        // Arbitrary file name: pure noise, possibly with a marker injected.
        final name = _randomNoise(rng, 60);
        final tier = LLMServiceImpl.modelTierForPath(name);
        expect(tiers.contains(tier), isTrue,
            reason: 'tier for "$name" was $tier, not one of $tiers');
      }
    });

    test('name encoding 0.5B maps to small', () {
      final rng = Random(7);
      for (var i = 0; i < _iterations; i++) {
        final marker = _smallMarkers[rng.nextInt(_smallMarkers.length)];
        final name = _embed(rng, _randomCase(rng, marker));
        expect(LLMServiceImpl.modelTierForPath(name), ModelTier.small,
            reason: 'expected small for "$name"');
      }
    });

    test('name encoding 1.5B (without 0.5B) maps to medium', () {
      final rng = Random(99);
      for (var i = 0; i < _iterations; i++) {
        final marker = _mediumMarkers[rng.nextInt(_mediumMarkers.length)];
        final name = _embed(rng, _randomCase(rng, marker));
        expect(LLMServiceImpl.modelTierForPath(name), ModelTier.medium,
            reason: 'expected medium for "$name"');
      }
    });

    test('name encoding neither 0.5B nor 1.5B maps to large', () {
      final rng = Random(12345);
      // Common real-world large markers plus random noise.
      const largeHints = ['3b', '7b', '14b', '32b', '', 'instruct', 'q4_k_m'];
      for (var i = 0; i < _iterations; i++) {
        final hint = largeHints[rng.nextInt(largeHints.length)];
        final name = '${_randomNoise(rng, 25)}$hint${_randomNoise(rng, 25)}'
            '${rng.nextBool() ? '.gguf' : ''}';
        // Noise alphabet cannot form a marker, and the hints contain none.
        expect(LLMServiceImpl.modelTierForPath(name), ModelTier.large,
            reason: 'expected large for "$name"');
      }
    });

    test('0.5B takes precedence over 1.5B when both are present', () {
      final rng = Random(2024);
      for (var i = 0; i < _iterations; i++) {
        final small = _randomCase(rng, _smallMarkers[rng.nextInt(2)]);
        final medium = _randomCase(rng, _mediumMarkers[rng.nextInt(2)]);
        // Place both markers in random order surrounded by noise.
        final first = rng.nextBool() ? small : medium;
        final second = identical(first, small) ? medium : small;
        final name = '${_randomNoise(rng, 10)}$first'
            '${_randomNoise(rng, 10)}$second${_randomNoise(rng, 10)}';
        expect(LLMServiceImpl.modelTierForPath(name), ModelTier.small,
            reason: 'expected small (precedence) for "$name"');
      }
    });

    test('null path maps to large (no model loaded / unknown)', () {
      expect(LLMServiceImpl.modelTierForPath(null), ModelTier.large);
    });
  });
}
