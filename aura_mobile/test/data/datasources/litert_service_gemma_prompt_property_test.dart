import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';

// Feature: multi-engine-ai-models, Property 7: Gemma prompt formatting
//
// "For any prompt and optional system prompt, the LiteRtService formats the
//  input using the Gemma <start_of_turn> template: the output contains a
//  <start_of_turn>user turn embedding the prompt text (and the system prompt
//  when present), ends with a <start_of_turn>model opener, and never contains
//  ChatML markers (<|im_start|>)."
//
// Validates: Requirements 3.4
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. The
// property runs >= 100 generated cases over prompts and optional system
// prompts that include unicode, whitespace, and punctuation edge content.

const int _iterations = 300;

/// ChatML markers that belong to the GGUF engine and must NEVER appear in a
/// Gemma-formatted prompt.
const _chatMlMarkers = ['<|im_start|>', '<|im_end|>', '<|endoftext|>'];

/// Alphabet for generated content. Deliberately rich (unicode, whitespace,
/// punctuation, angle brackets and pipes) so we exercise tricky inputs, but it
/// excludes the literal ChatML marker substrings so generated content can never
/// itself introduce a marker and create a false positive for the "no ChatML"
/// check. Bare '<', '>', '|' characters are included to prove the formatter
/// does not assemble them into ChatML markers.
const _contentAlphabet = [
  'a', 'b', 'c', 'Z', 'Q', '0', '9',
  ' ', '\n', '\t',
  '.', ',', '!', '?', ':', ';', '-', '_', '/', '\\',
  '<', '>', '|', '{', '}', '#', '@',
  'é', 'ä', 'ñ', '中', '文', '🚀', '😀',
  '<start_of_turn>', // include partial template tokens as adversarial content
  'user', 'model', 'end_of_turn',
];

String _randomContent(Random rng, int maxLen) {
  final len = rng.nextInt(maxLen + 1);
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.write(_contentAlphabet[rng.nextInt(_contentAlphabet.length)]);
  }
  return sb.toString();
}

void main() {
  group('Property 7: Gemma prompt formatting (multi-engine-ai-models)', () {
    test('formats with the <start_of_turn> template for any prompt/system prompt',
        () {
      final rng = Random(20240707);
      for (var i = 0; i < _iterations; i++) {
        final prompt = _randomContent(rng, 60);

        // Cover the three system-prompt cases: absent (null), empty string,
        // and a non-empty value.
        final int sysCase = rng.nextInt(3);
        final String? systemPrompt = sysCase == 0
            ? null
            : sysCase == 1
                ? ''
                : _randomContent(rng, 40);

        final out = LiteRtService.formatGemmaPrompt(
          prompt,
          systemPrompt: systemPrompt,
        );

        String ctx() => 'Property 7 counterexample\n'
            '  prompt       = ${prompt.codeUnits}\n'
            '  systemPrompt = ${systemPrompt?.codeUnits}\n'
            '  output       = ${out.codeUnits}\n'
            '  outputStr    = "$out"';

        // (a) Opens a user turn.
        expect(out.startsWith('<start_of_turn>user\n'), isTrue, reason: ctx());

        // (b) Contains an end-of-turn marker closing the user turn.
        expect(out.contains('<end_of_turn>'), isTrue, reason: ctx());

        // (c) Ends with the model opener so the engine continues as the model.
        expect(out.endsWith('<start_of_turn>model\n'), isTrue, reason: ctx());

        // (d) Embeds the prompt text verbatim.
        expect(out.contains(prompt), isTrue, reason: ctx());

        // (e) Embeds the system prompt when (and only relevantly when) present
        //     and non-empty, ahead of the prompt inside the user turn.
        if (systemPrompt != null && systemPrompt.isNotEmpty) {
          expect(out.contains(systemPrompt), isTrue, reason: ctx());
          // System prompt appears before the user prompt within the turn.
          final sysIdx = out.indexOf(systemPrompt);
          final userTurnStart = '<start_of_turn>user\n'.length;
          expect(sysIdx >= userTurnStart, isTrue, reason: ctx());
        }

        // (f) Never emits ChatML markers (those belong to the GGUF engine).
        for (final marker in _chatMlMarkers) {
          expect(out.contains(marker), isFalse,
              reason: '${ctx()}\n  leaked ChatML marker "$marker"');
        }
      }
    });

    // Concrete, deterministic examples documenting the intended structure.
    test('example: prompt only produces a single user turn + model opener', () {
      final out = LiteRtService.formatGemmaPrompt('Hello there');
      expect(out, '<start_of_turn>user\nHello there<end_of_turn>\n'
          '<start_of_turn>model\n');
    });

    test('example: system prompt is embedded ahead of the prompt', () {
      final out = LiteRtService.formatGemmaPrompt(
        'What is 2+2?',
        systemPrompt: 'You are AURA.',
      );
      expect(out, '<start_of_turn>user\nYou are AURA.\n\nWhat is 2+2?'
          '<end_of_turn>\n<start_of_turn>model\n');
    });

    test('example: empty system prompt is treated as absent', () {
      final out = LiteRtService.formatGemmaPrompt('Hi', systemPrompt: '');
      expect(out, '<start_of_turn>user\nHi<end_of_turn>\n'
          '<start_of_turn>model\n');
    });
  });
}
