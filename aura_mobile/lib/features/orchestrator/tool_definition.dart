/// Data types for native function/tool calling used by tool-capable models.
///
/// These types model the contract between a tool-calling model emission and the
/// orchestrator's tool handlers:
/// - [ToolDefinition] / [ToolParameter] describe the tools made available to a
///   model on each inference call (Requirement 5.1).
/// - [FunctionCallRequest] is a parsed tool invocation: exactly one tool name
///   plus zero or more parameter name-value pairs (Requirement 5.2).
/// - [FunctionCallResult] is the sealed outcome of parsing/validating a model
///   emission into a request, covering the success and error cases.
library;

/// A single parameter declared by a [ToolDefinition].
class ToolParameter {
  /// The parameter name as the model is expected to emit it.
  final String name;

  /// Whether the parameter must be present for the tool to be invoked.
  final bool required;

  const ToolParameter({
    required this.name,
    this.required = false,
  });

  @override
  bool operator ==(Object other) =>
      other is ToolParameter &&
      other.name == name &&
      other.required == required;

  @override
  int get hashCode => Object.hash(name, required);

  @override
  String toString() => 'ToolParameter(name: $name, required: $required)';
}

/// A named, parameterized action a model can request through function calling.
class ToolDefinition {
  /// The unique tool name the model references when invoking the tool.
  final String name;

  /// The parameters this tool declares.
  final List<ToolParameter> parameters;

  const ToolDefinition({
    required this.name,
    this.parameters = const [],
  });

  /// The names of every parameter this tool declares as required.
  List<String> get requiredParameterNames =>
      [for (final p in parameters) if (p.required) p.name];

  @override
  String toString() => 'ToolDefinition(name: $name, parameters: $parameters)';
}

/// A parsed function-call request: exactly one tool name and its arguments.
class FunctionCallRequest {
  /// The name of the tool the model requested.
  final String toolName;

  /// The parsed parameter name-value pairs supplied by the model.
  final Map<String, Object?> arguments;

  const FunctionCallRequest({
    required this.toolName,
    this.arguments = const {},
  });

  @override
  String toString() =>
      'FunctionCallRequest(toolName: $toolName, arguments: $arguments)';
}

/// The sealed outcome of parsing and validating a model's function-call
/// emission.
///
/// Exactly one subtype is produced per emission:
/// - [FunctionCallParsed] when the request is valid and dispatchable.
/// - [FunctionCallUnparseable] when the emission cannot be parsed into a tool
///   name and parameter pairs (Requirement 5.7).
/// - [FunctionCallUnknownTool] when the request names a tool that is not
///   registered (Requirement 5.5).
/// - [FunctionCallMissingParams] when the request omits one or more of the
///   named tool's required parameters (Requirement 5.6).
sealed class FunctionCallResult {
  const FunctionCallResult();
}

/// A successfully parsed and validated function-call request.
class FunctionCallParsed extends FunctionCallResult {
  /// The validated request ready for dispatch to its handler.
  final FunctionCallRequest request;

  const FunctionCallParsed(this.request);

  @override
  String toString() => 'FunctionCallParsed($request)';
}

/// The emission could not be parsed into a tool name and parameter pairs.
class FunctionCallUnparseable extends FunctionCallResult {
  /// The raw emission that failed to parse.
  final String raw;

  const FunctionCallUnparseable(this.raw);

  @override
  String toString() => 'FunctionCallUnparseable(raw: $raw)';
}

/// The request named a tool that is not in the registry.
class FunctionCallUnknownTool extends FunctionCallResult {
  /// The unavailable tool name the model requested.
  final String toolName;

  const FunctionCallUnknownTool(this.toolName);

  @override
  String toString() => 'FunctionCallUnknownTool(toolName: $toolName)';
}

/// The request omitted one or more of the named tool's required parameters.
class FunctionCallMissingParams extends FunctionCallResult {
  /// The name of the tool whose required parameters were missing.
  final String toolName;

  /// Each required parameter name that was missing from the request.
  final List<String> missing;

  const FunctionCallMissingParams({
    required this.toolName,
    required this.missing,
  });

  @override
  String toString() =>
      'FunctionCallMissingParams(toolName: $toolName, missing: $missing)';
}
