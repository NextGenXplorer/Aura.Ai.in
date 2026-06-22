import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/features/orchestrator/function_call_coordinator.dart';
import 'package:aura_mobile/features/orchestrator/tool_definition.dart';

// Feature: multi-engine-ai-models, Property 12: Function-call parse round-trip
//
// "For any tool name and any map of parameter name-value pairs, serializing
//  them into the model's function-call form and then parsing yields exactly one
//  tool name equal to the original and a parameter map equal to the original."
//
// Validates: Requirements 5.2
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. The
// property runs >= 100 generated cases over (toolName, arguments) pairs whose
// argument values span the JSON value space the model emits: strings (with
// unicode/whitespace/punctuation), ints, finite doubles, booleans, null, and
// nested lists/maps.

const int _iterations = 300;

/// Alphabet for generated tool names and string content. Rich enough to
/// exercise unicode, whitespace, punctuation, and characters that look like
/// structural JSON/template tokens, so we prove serialize/parse survives them.
const _alphabet = [
  'a', 'b', 'c', 'Z', 'Q', '0', '9',
  ' ', '\n', '\t',
  '.', ',', '!', '?', ':', ';', '-', '_', '/', '\\',
  '"', "'", '<', '>', '|', '{', '}', '[', ']', '#', '@',
  'é', 'ä', 'ñ', '中', '文', '🚀', '😀',
  'name', 'arguments', 'tool',
];

String _randomString(Random rng, int maxLen) {
  final len = rng.nextInt(maxLen + 1);
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.write(_alphabet[rng.nextInt(_alphabet.length)]);
  }
  return sb.toString();
}

/// A non-empty tool name. The parser rejects empty names (treats them as
/// unparseable), so the round-trip is only defined for non-empty names.
String _randomToolName(Random rng) {
  final raw = _randomString(rng, 24);
  return raw.isEmpty ? 'tool_${rng.nextInt(1000)}' : raw;
}

/// Generates a JSON-serializable value. [depth] bounds recursion so nested
/// structures stay small and finite. NaN/Infinity are deliberately excluded
/// because they are not representable in JSON.
Object? _randomJsonValue(Random rng, int depth) {
  // At max depth, only produce scalars.
  final maxKind = depth <= 0 ? 5 : 7;
  switch (rng.nextInt(maxKind)) {
    case 0:
      return _randomString(rng, 16);
    case 1:
      return rng.nextInt(2000000) - 1000000; // bounded int (may be negative)
    case 2:
      // Finite double; keep it well away from NaN/Infinity.
      return (rng.nextDouble() - 0.5) * 1e6;
    case 3:
      return rng.nextBool();
    case 4:
      return null;
    case 5:
      // Nested list.
      final n = rng.nextInt(4);
      return [for (var i = 0; i < n; i++) _randomJsonValue(rng, depth - 1)];
    case 6:
    default:
      // Nested object with string keys.
      final n = rng.nextInt(4);
      final m = <String, Object?>{};
      for (var i = 0; i < n; i++) {
        m[_randomString(rng, 8)] = _randomJsonValue(rng, depth - 1);
      }
      return m;
  }
}

Map<String, Object?> _randomArguments(Random rng) {
  final count = rng.nextInt(6); // 0..5 parameters
  final args = <String, Object?>{};
  for (var i = 0; i < count; i++) {
    args[_randomString(rng, 10)] = _randomJsonValue(rng, 2);
  }
  return args;
}

void main() {
  group('Property 12: Function-call parse round-trip (multi-engine-ai-models)',
      () {
    test(
        'serialize then parse recovers the same tool name and arguments '
        'for any (toolName, arguments)', () {
      final rng = Random(20240712);
      for (var i = 0; i < _iterations; i++) {
        final toolName = _randomToolName(rng);
        final arguments = _randomArguments(rng);
        final original = FunctionCallRequest(
          toolName: toolName,
          arguments: arguments,
        );

        // Register the tool with no required parameters so validation succeeds
        // and the parse step's recovered request is exposed via
        // FunctionCallParsed. This isolates the round-trip (serialize -> parse)
        // from the unrelated required-parameter validation rule.
        final coordinator = FunctionCallCoordinator.fromDefinitions([
          ToolDefinition(name: toolName),
        ]);

        final serialized = FunctionCallCoordinator.serialize(original);
        final result = coordinator.parse(serialized);

        String ctx() => 'Property 12 counterexample\n'
            '  toolName  = ${toolName.codeUnits}\n'
            '  arguments = $arguments\n'
            '  serialized= "$serialized"\n'
            '  result    = $result';

        expect(result, isA<FunctionCallParsed>(), reason: ctx());
        final recovered = (result as FunctionCallParsed).request;

        // Exactly one tool name, equal to the original.
        expect(recovered.toolName, equals(toolName), reason: ctx());

        // Parameter map equal to the original (deep structural equality).
        expect(recovered.arguments, equals(arguments), reason: ctx());
      }
    });

    // Concrete, deterministic examples documenting the intended behavior.
    test('example: tool with no arguments round-trips', () {
      final coordinator = FunctionCallCoordinator.fromDefinitions([
        const ToolDefinition(name: 'get_time'),
      ]);
      final original = const FunctionCallRequest(toolName: 'get_time');
      final result =
          coordinator.parse(FunctionCallCoordinator.serialize(original));
      expect(result, isA<FunctionCallParsed>());
      final recovered = (result as FunctionCallParsed).request;
      expect(recovered.toolName, 'get_time');
      expect(recovered.arguments, isEmpty);
    });

    test('example: mixed-type arguments round-trip', () {
      final coordinator = FunctionCallCoordinator.fromDefinitions([
        const ToolDefinition(name: 'set_alarm'),
      ]);
      final original = const FunctionCallRequest(
        toolName: 'set_alarm',
        arguments: {
          'hour': 7,
          'minute': 30,
          'label': 'wake up',
          'recurring': true,
          'snooze': null,
          'days': ['mon', 'tue'],
          'meta': {'sound': 'chime', 'volume': 0.8},
        },
      );
      final result =
          coordinator.parse(FunctionCallCoordinator.serialize(original));
      expect(result, isA<FunctionCallParsed>());
      final recovered = (result as FunctionCallParsed).request;
      expect(recovered.toolName, 'set_alarm');
      expect(
        recovered.arguments,
        equals({
          'hour': 7,
          'minute': 30,
          'label': 'wake up',
          'recurring': true,
          'snooze': null,
          'days': ['mon', 'tue'],
          'meta': {'sound': 'chime', 'volume': 0.8},
        }),
      );
    });
  });
}
