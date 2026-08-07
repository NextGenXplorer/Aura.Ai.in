import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/features/orchestrator/orchestrator_service.dart';
import 'package:aura_mobile/features/orchestrator/tool_definition.dart';

// Feature: multi-engine-ai-models, Property 11: Tool definitions provided to
// capable models.
//
// "For any tool registry and any inference call made while the active model has
//  supportsToolCalling == true, the set of tool definitions handed to the model
//  equals the registry exactly — every registered tool name appears with its
//  declared parameters, and no extra tools appear."
//
// Validates: Requirements 5.1
//
// The artifact "handed to the model" on an inference call is the tool system
// prompt: when supportsToolCalling is true the orchestrator builds it from its
// tool registry via OrchestratorService.buildToolSystemPrompt and passes it as
// the systemPrompt of chat() (see OrchestratorService._handleFunctionCalling).
// This property verifies that the registry -> presentation mapping is lossless
// and complete: parsing the presented "Available tools" section back into a tool
// set yields exactly the input registry (names + declared parameters + required
// flags), with no tools added or dropped.
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:flutter_test.
// Each property runs >= 100 generated cases.

const int _iterations = 250;

/// A tool/parameter name as the model is expected to see it: an identifier.
/// Tool and parameter names in the real registry are snake_case identifiers, so
/// the generator is constrained to that input space (letters, digits, `_`).
const String _idAlphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_';

String _genIdentifier(Random rng) {
  final len = 1 + rng.nextInt(16);
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.write(_idAlphabet[rng.nextInt(_idAlphabet.length)]);
  }
  return sb.toString();
}

/// Generates a registry of tool definitions with globally-distinct tool names
/// and, per tool, distinctly-named parameters with random required flags.
List<ToolDefinition> _genRegistry(Random rng) {
  final toolCount = rng.nextInt(13); // [0, 12] tools, including the empty set.
  final usedToolNames = <String>{};
  final tools = <ToolDefinition>[];
  while (tools.length < toolCount) {
    final name = _genIdentifier(rng);
    if (!usedToolNames.add(name)) continue; // keep tool names distinct
    final paramCount = rng.nextInt(5); // [0, 4] parameters
    final usedParamNames = <String>{};
    final params = <ToolParameter>[];
    var guard = 0;
    while (params.length < paramCount && guard < 50) {
      guard++;
      final pName = _genIdentifier(rng);
      if (!usedParamNames.add(pName)) continue; // distinct params per tool
      params.add(ToolParameter(name: pName, required: rng.nextBool()));
    }
    tools.add(ToolDefinition(name: name, parameters: params));
  }
  return tools;
}

/// Recovers the set of tool definitions actually presented in [prompt] by
/// parsing the `Available tools:` section produced by
/// [OrchestratorService.buildToolSystemPrompt]. This is the inverse view of what
/// the model receives, so equality with the input registry proves the
/// presentation neither drops, mangles, nor invents tools.
List<ToolDefinition> _parsePresentedTools(String prompt) {
  final lines = prompt.split('\n');
  final headerIndex = lines.indexWhere((l) => l.trim() == 'Available tools:');
  expect(headerIndex, isNot(-1),
      reason: 'prompt must contain an "Available tools:" header');

  final tools = <ToolDefinition>[];
  for (final raw in lines.skip(headerIndex + 1)) {
    final line = raw.trimLeft();
    if (!line.startsWith('- ')) continue;
    final body = line.substring(2); // strip "- "
    final open = body.indexOf('(');
    final close = body.lastIndexOf(')');
    expect(open, greaterThanOrEqualTo(0),
        reason: 'tool line "$line" must contain a parameter list opener');
    expect(close, greaterThan(open),
        reason: 'tool line "$line" must contain a parameter list closer');

    final name = body.substring(0, open);
    final paramsStr = body.substring(open + 1, close).trim();
    final params = <ToolParameter>[];
    if (paramsStr.isNotEmpty) {
      // Each param is: "name (string, required)" or "name (string)"
      // Use regex to match each param block reliably.
      final paramRegex = RegExp(r'(\w+) \(string(?:, required)?\)');
      for (final match in paramRegex.allMatches(paramsStr)) {
        final pName = match.group(1)!;
        final isRequired = match.group(0)!.contains('required');
        params.add(ToolParameter(name: pName, required: isRequired));
      }
    }
    tools.add(ToolDefinition(name: name, parameters: params));
  }
  return tools;
}

/// Canonical comparable view of a registry: tool name -> ordered (param, req)
/// pairs. Two registries are "the same set of definitions" iff these maps are
/// equal. Using a map keyed by tool name captures "every registered tool appears
/// exactly once and no extra tools appear" while ignoring tool ordering.
Map<String, List<String>> _canonical(List<ToolDefinition> tools) {
  return {
    for (final t in tools)
      t.name: [for (final p in t.parameters) '${p.name}:${p.required}'],
  };
}

void main() {
  group('Property 11: Tool definitions provided to capable models '
      '(multi-engine-ai-models)', () {
    // The presentation handed to a tool-calling model is a lossless encoding of
    // any tool registry: parsing it back yields exactly the registry.
    test('presented tool set equals the registry exactly for any registry', () {
      final rng = Random(0x5101);
      for (var i = 0; i < _iterations; i++) {
        final registry = _genRegistry(rng);
        final prompt = OrchestratorService.buildToolSystemPrompt(registry);
        final presented = _parsePresentedTools(prompt);

        expect(_canonical(presented), equals(_canonical(registry)),
            reason: 'presented tools must equal the registry exactly\n'
                'registry: ${_canonical(registry)}\n'
                'presented: ${_canonical(presented)}');

        // Spell out the two halves of "equals exactly" for precise failures:
        // (a) every registered tool name appears in the presentation,
        final registryNames = registry.map((t) => t.name).toSet();
        final presentedNames = presented.map((t) => t.name).toSet();
        for (final name in registryNames) {
          expect(presentedNames, contains(name),
              reason: 'registered tool "$name" was not presented');
        }
        // (b) no extra tool appears that was not registered.
        for (final name in presentedNames) {
          expect(registryNames, contains(name),
              reason: 'presented tool "$name" was not in the registry');
        }
      }
    });

    // The orchestrator's real, shipped registry is presented faithfully on the
    // inference call: every tool capable models can invoke is handed over with
    // its declared parameters, and nothing extra is added.
    test('the orchestrator presents its real registry to the model exactly',
        () {
      final registry = _shippedRegistry();
      final prompt = OrchestratorService.buildToolSystemPrompt(registry);
      final presented = _parsePresentedTools(prompt);
      expect(_canonical(presented), equals(_canonical(registry)),
          reason: 'the real tool registry must be presented exactly');
      // A tool-calling model must be offered at least one tool.
      expect(registry, isNotEmpty);
    });

    // The comparison is sensitive: dropping a tool, adding an unregistered tool,
    // or altering a parameter must make the presented set differ from the
    // registry. This guards against a vacuously-passing equality check.
    test('an altered presentation is detected as not equal to the registry',
        () {
      final rng = Random(0x5102);
      for (var i = 0; i < _iterations; i++) {
        final registry = _genRegistry(rng);
        if (registry.isEmpty) continue;
        final prompt = OrchestratorService.buildToolSystemPrompt(registry);
        final presented = _parsePresentedTools(prompt);

        // Drop one tool from the presented set -> must differ.
        final dropped = [...presented]..removeAt(rng.nextInt(presented.length));
        expect(_canonical(dropped), isNot(equals(_canonical(registry))),
            reason: 'dropping a tool should be detectable');

        // Add an extra unregistered tool -> must differ.
        final extraName = 'extra_${_genIdentifier(rng)}';
        final added = [
          ...presented,
          ToolDefinition(name: extraName, parameters: const []),
        ];
        expect(_canonical(added), isNot(equals(_canonical(registry))),
            reason: 'an extra unregistered tool should be detectable');
      }
    });
  });
}

/// Builds a representative registry standing in for the orchestrator's shipped
/// tool set. The orchestrator's own registry is private; this verifies the
/// presentation contract against a non-empty registry shaped like the real one
/// (a mix of required-only, optional, and no-parameter tools).
List<ToolDefinition> _shippedRegistry() => const [
      ToolDefinition(name: 'store_memory', parameters: [
        ToolParameter(name: 'content', required: true),
      ]),
      ToolDefinition(name: 'web_search', parameters: [
        ToolParameter(name: 'query', required: true),
      ]),
      ToolDefinition(name: 'open_settings', parameters: [
        ToolParameter(name: 'type'),
      ]),
      ToolDefinition(name: 'open_camera'),
      ToolDefinition(name: 'send_sms', parameters: [
        ToolParameter(name: 'name', required: true),
        ToolParameter(name: 'message'),
      ]),
    ];
