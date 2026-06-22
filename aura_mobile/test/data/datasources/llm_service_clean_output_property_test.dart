import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';

// Feature: multi-engine-ai-models, Property 4: GGUF output cleaning removes stop markers
//
// "For any stream of GGUF tokens, the cleaned output returned to the
//  orchestrator contains none of the stop/hallucination markers
//  (<|im_end|>, <|im_start|>, <|endoftext|>, Human:, User:, and the
//  conversation-continuation markers) and is truncated at the first occurrence
//  of any such marker."
//
// Validates: Requirements 2.3
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. The
// property runs >= 100 generated cases (token streams that inject stop markers
// as whole tokens, embedded inside a token, and — as a real GGUF tokenizer
// would — split across several tokens).

const int _iterations = 400;

/// The exact marker set the production cleaner recognizes, in the order it
/// scans them. Kept identical to `LLMServiceImpl.cleanModelOutput` so the test
/// mirrors the spec'd behavior rather than re-deriving it.
const List<String> _markers = [
  '<|endoftext|>',
  '<|im_end|>',
  '<|im_start|>',
  'Human:',
  'User:',
  'ASSISTANT RESPONSE',
  'USER REQUEST',
  'CURRENT USER REQUEST',
];

/// Lowercase-alphanumeric alphabet for "clean" content. It deliberately
/// excludes upper-case letters, ':', '<', '|', '>', and sentence punctuation
/// ('.', '!', '?', '\n') so generated clean tokens can never accidentally
/// form one of the markers nor trip the cleaner's repeat/sentence heuristics.
const String _cleanAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

String _randomCleanChunk(Random rng, int maxLen) {
  final len = rng.nextInt(maxLen + 1);
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.write(_cleanAlphabet[rng.nextInt(_cleanAlphabet.length)]);
  }
  return sb.toString();
}

/// Generates a list of unique clean word-tokens. Uniqueness (via an embedded
/// index) guarantees the cleaner's token-level/sentence-level repeat detection
/// never fires, isolating the property under test to marker handling.
List<String> _cleanWords(Random rng, int count) {
  return List.generate(count, (i) {
    return 't${i}x${_randomCleanChunk(rng, 4)}';
  });
}

/// Splits [marker] into [parts] non-empty consecutive pieces (a realistic
/// subword tokenization of the marker).
List<String> _splitMarker(Random rng, String marker, int parts) {
  if (parts <= 1 || marker.length <= 1) return [marker];
  final cutCount = min(parts, marker.length) - 1;
  final cuts = <int>{};
  while (cuts.length < cutCount) {
    cuts.add(1 + rng.nextInt(marker.length - 1));
  }
  final sorted = cuts.toList()..sort();
  final pieces = <String>[];
  var prev = 0;
  for (final c in sorted) {
    pieces.add(marker.substring(prev, c));
    prev = c;
  }
  pieces.add(marker.substring(prev));
  return pieces;
}

class _Case {
  final List<String> tokens;
  final String fullText;
  _Case(this.tokens, this.fullText);
}

/// Builds one random token stream. With ~80% probability it injects exactly one
/// marker (chosen at random) in one of three forms: a whole token, embedded
/// inside a clean token, or split across 2-3 tokens.
_Case _generateCase(Random rng) {
  final tokens = <String>[];

  // Leading clean words.
  tokens.addAll(_cleanWords(rng, rng.nextInt(6)));

  final injectMarker = rng.nextInt(10) < 8;
  if (injectMarker) {
    final marker = _markers[rng.nextInt(_markers.length)];
    final form = rng.nextInt(3);
    switch (form) {
      case 0: // whole marker as its own token
        tokens.add(marker);
        break;
      case 1: // marker embedded between clean text inside a single token
        tokens.add('${_randomCleanChunk(rng, 5)}$marker${_randomCleanChunk(rng, 5)}');
        break;
      case 2: // marker split across multiple tokens (subword tokenization)
        tokens.addAll(_splitMarker(rng, marker, 2 + rng.nextInt(2)));
        break;
    }
    // Trailing clean words after the marker (should be dropped by truncation).
    tokens.addAll(_cleanWords(rng, rng.nextInt(6)));
  }

  // Re-index clean words across the whole list so none repeat (the marker
  // tokens are inserted between distinct indices, never duplicated).
  return _Case(tokens, tokens.join());
}

/// The expected cleaned output: the prefix of [fullText] up to the first
/// occurrence of any marker (or the whole text when no marker is present).
String _expectedClean(String fullText) {
  var first = -1;
  for (final m in _markers) {
    final idx = fullText.indexOf(m);
    if (idx >= 0 && (first < 0 || idx < first)) first = idx;
  }
  return first < 0 ? fullText : fullText.substring(0, first);
}

Future<String> _runCleaner(List<String> tokens) async {
  final cleaned = await LLMServiceImpl.cleanModelOutput(
    Stream<String>.fromIterable(tokens),
  ).toList();
  return cleaned.join();
}

void main() {
  group('Property 4: GGUF output cleaning removes stop markers (multi-engine-ai-models)', () {
    test('cleaned output drops every marker and truncates at the first one', () async {
      final rng = Random(20240620);
      for (var i = 0; i < _iterations; i++) {
        final c = _generateCase(rng);
        final expected = _expectedClean(c.fullText);

        String actual;
        try {
          actual = await _runCleaner(c.tokens);
        } catch (e) {
          fail('Property 4 counterexample (threw $e)\n'
              '  tokens   = ${c.tokens}\n'
              '  fullText = "${c.fullText}"\n'
              '  expected = "$expected"');
        }

        // (a) Truncated at the first marker occurrence.
        if (actual != expected) {
          fail('Property 4 counterexample (truncation mismatch)\n'
              '  tokens   = ${c.tokens}\n'
              '  fullText = "${c.fullText}"\n'
              '  expected = "$expected"\n'
              '  actual   = "$actual"');
        }

        // (b) Contains none of the stop markers.
        for (final m in _markers) {
          if (actual.contains(m)) {
            fail('Property 4 counterexample (marker "$m" leaked)\n'
                '  tokens   = ${c.tokens}\n'
                '  fullText = "${c.fullText}"\n'
                '  actual   = "$actual"');
          }
        }
      }
    });

    // A few concrete, deterministic examples alongside the property to document
    // the intended behavior at a glance.
    test('example: marker as a standalone token truncates the stream', () async {
      final out = await _runCleaner(['hello ', 'world', '<|im_end|>', 'leaked']);
      expect(out, 'hello world');
    });

    test('example: marker embedded inside a token keeps the clean prefix', () async {
      final out = await _runCleaner(['answer is 42', ' done<|endoftext|>more']);
      expect(out, 'answer is 42 done');
    });

    test('example: no marker passes the stream through unchanged', () async {
      final out = await _runCleaner(['the ', 'quick ', 'brown ', 'fox']);
      expect(out, 'the quick brown fox');
    });
  });
}
