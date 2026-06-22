/// Coordinates parsing and validating native function-call emissions from
/// tool-calling models into dispatchable [FunctionCallRequest]s.
///
/// The coordinator is the boundary between a model's raw function-call emission
/// and the orchestrator's tool handlers. It never invokes a handler itself; it
/// only classifies an emission into one of the [FunctionCallResult] outcomes so
/// the orchestrator can decide what to do:
/// - [FunctionCallParsed]      — valid, names a known tool, has all required
///                               parameters; ready to dispatch (Requirement 5.2).
/// - [FunctionCallUnparseable] — the emission is not a parseable tool name +
///                               parameter pairs (Requirement 5.7).
/// - [FunctionCallUnknownTool] — the named tool is not registered (Requirement 5.5).
/// - [FunctionCallMissingParams] — one or more required parameters are absent
///                               (Requirement 5.6).
library;

import 'dart:convert';

import 'tool_definition.dart';

/// Parses and validates model function-call emissions against a set of known
/// [ToolDefinition]s.
class FunctionCallCoordinator {
  /// Registered tools keyed by their unique [ToolDefinition.name].
  final Map<String, ToolDefinition> _tools;

  /// Creates a coordinator over the given [tools] map (name -> definition).
  const FunctionCallCoordinator({Map<String, ToolDefinition> tools = const {}})
      : _tools = tools;

  /// Builds a coordinator from a list of [ToolDefinition]s.
  ///
  /// Later definitions with a duplicate name override earlier ones.
  factory FunctionCallCoordinator.fromDefinitions(
    Iterable<ToolDefinition> definitions,
  ) {
    return FunctionCallCoordinator(
      tools: {for (final d in definitions) d.name: d},
    );
  }

  /// The names of every registered tool.
  Set<String> get knownToolNames => _tools.keys.toSet();

  /// Parses [raw] into a classified [FunctionCallResult].
  ///
  /// [knownTools] is the set of tool names the model was offered on this
  /// inference call; when omitted it defaults to the coordinator's registered
  /// tools. The result is exactly one of:
  /// - [FunctionCallUnparseable] when [raw] cannot be parsed into a tool name
  ///   and parameter name-value pairs (Requirement 5.7).
  /// - [FunctionCallUnknownTool] when the parsed tool name is not in
  ///   [knownTools] (Requirement 5.5).
  /// - the outcome of [validate] otherwise (parsed or missing-params).
  FunctionCallResult parse(String raw, {Set<String>? knownTools}) {
    final known = knownTools ?? knownToolNames;

    final request = _tryParse(raw);
    if (request == null) {
      return FunctionCallUnparseable(raw);
    }
    if (!known.contains(request.toolName)) {
      return FunctionCallUnknownTool(request.toolName);
    }
    return validate(request);
  }

  /// Validates a parsed [request] against the named tool's declared parameters.
  ///
  /// Returns [FunctionCallUnknownTool] when the request names a tool that is not
  /// registered (Requirement 5.5), [FunctionCallMissingParams] listing every
  /// required parameter absent from [FunctionCallRequest.arguments] (Requirement
  /// 5.6), or [FunctionCallParsed] when the request is fully valid.
  FunctionCallResult validate(FunctionCallRequest request) {
    final definition = _tools[request.toolName];
    if (definition == null) {
      return FunctionCallUnknownTool(request.toolName);
    }

    final missing = <String>[
      for (final name in definition.requiredParameterNames)
        if (!request.arguments.containsKey(name)) name,
    ];
    if (missing.isNotEmpty) {
      return FunctionCallMissingParams(
        toolName: request.toolName,
        missing: missing,
      );
    }

    return FunctionCallParsed(request);
  }

  /// Serializes a [request] into the canonical model function-call form.
  ///
  /// This is the inverse of [parse]'s parsing step: `parse(serialize(req))`
  /// recovers a request with the same tool name and arguments.
  static String serialize(FunctionCallRequest request) {
    return jsonEncode(<String, Object?>{
      'name': request.toolName,
      'arguments': request.arguments,
    });
  }

  /// Attempts to recover a [FunctionCallRequest] from a raw model emission.
  ///
  /// Returns `null` when the emission cannot be interpreted as a single tool
  /// name plus parameter pairs.
  FunctionCallRequest? _tryParse(String raw) {
    for (final candidate in _jsonCandidates(raw)) {
      Object? decoded;
      try {
        decoded = jsonDecode(candidate);
      } catch (_) {
        continue;
      }
      if (decoded is! Map) {
        continue;
      }
      final request = _fromMap(decoded);
      if (request != null) {
        return request;
      }
    }
    return null;
  }

  /// Builds a request from a decoded JSON object, or `null` when the object does
  /// not describe a tool name and (optional) parameter object.
  FunctionCallRequest? _fromMap(Map<Object?, Object?> map) {
    final name = map['name'] ??
        map['tool'] ??
        map['toolName'] ??
        map['function'];
    if (name is! String || name.isEmpty) {
      return null;
    }

    final argsRaw = map['arguments'] ??
        map['args'] ??
        map['parameters'] ??
        map['params'];

    Map<String, Object?> arguments;
    if (argsRaw == null) {
      // A bare tool name with no parameters is a valid call.
      arguments = const {};
    } else if (argsRaw is Map) {
      arguments = argsRaw.map((k, v) => MapEntry(k.toString(), v));
    } else {
      // An arguments field that is not an object cannot be interpreted as
      // parameter name-value pairs.
      return null;
    }

    return FunctionCallRequest(toolName: name, arguments: arguments);
  }

  /// Yields JSON candidate strings to attempt decoding, most-likely first.
  ///
  /// Models commonly wrap a JSON object in markdown code fences or surround it
  /// with prose; this tries the raw string, a fence-stripped form, and the text
  /// between the first `{` and the last `}`.
  Iterable<String> _jsonCandidates(String raw) sync* {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return;
    }

    yield trimmed;

    final defenced = _stripCodeFences(trimmed);
    if (defenced != trimmed) {
      yield defenced;
    }

    final start = defenced.indexOf('{');
    final end = defenced.lastIndexOf('}');
    if (start != -1 && end > start) {
      yield defenced.substring(start, end + 1);
    }
  }

  /// Removes a surrounding ```...``` (optionally language-tagged) code fence.
  String _stripCodeFences(String input) {
    var s = input.trim();
    if (!s.startsWith('```')) {
      return s;
    }
    // Drop the opening fence line (e.g. "```json").
    final firstNewline = s.indexOf('\n');
    if (firstNewline == -1) {
      return s;
    }
    s = s.substring(firstNewline + 1);
    final closing = s.lastIndexOf('```');
    if (closing != -1) {
      s = s.substring(0, closing);
    }
    return s.trim();
  }
}
