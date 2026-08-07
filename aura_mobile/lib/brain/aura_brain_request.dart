import 'dart:convert';

import 'aura_brain_protocol.dart';

class AuraBrainPage {
  final String title;
  final String url;
  final String selectedText;
  final String visibleText;

  const AuraBrainPage({
    required this.title,
    required this.url,
    required this.selectedText,
    required this.visibleText,
  });
}

class AuraBrainRequest {
  final int protocolVersion;
  final String requestId;
  final String clientId;
  final String task;
  final String prompt;
  final AuraBrainPage? page;

  const AuraBrainRequest({
    required this.protocolVersion,
    required this.requestId,
    required this.clientId,
    required this.task,
    required this.prompt,
    required this.page,
  });

  static AuraBrainRequest parse(String source) {
    if (utf8.encode(source).length > auraBrainMaxSerializedRequestBytes) {
      throw const AuraBrainProtocolException(
        AuraBrainErrorCode.contextTooLarge,
        'The serialized request exceeds 128 KiB.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const AuraBrainProtocolException(
        AuraBrainErrorCode.invalidRequest,
        'Request JSON is malformed.',
      );
    }
    if (decoded is! Map) {
      throw const AuraBrainProtocolException(
        AuraBrainErrorCode.invalidRequest,
        'Request JSON must be an object.',
      );
    }
    final root = Map<String, dynamic>.from(decoded);
    final version = _requiredInt(root, 'protocolVersion');
    if (version != auraBrainProtocolVersion) {
      throw const AuraBrainProtocolException(
        AuraBrainErrorCode.unsupportedProtocol,
        'Only Aura Brain Protocol Version 1 is supported.',
      );
    }

    final requestId = _normalized(_requiredString(root, 'requestId'));
    if (requestId.isEmpty) {
      throw const AuraBrainProtocolException(
        AuraBrainErrorCode.invalidRequest,
        'requestId must not be blank.',
      );
    }
    if (requestId.length > 200) {
      throw const AuraBrainProtocolException(
        AuraBrainErrorCode.invalidRequest,
        'requestId exceeds 200 characters.',
      );
    }

    final clientId = _normalized(_requiredString(root, 'clientId'));
    if (clientId.isEmpty || clientId.length > 200) {
      throw const AuraBrainProtocolException(
        AuraBrainErrorCode.invalidRequest,
        'clientId is invalid.',
      );
    }
    final task = _normalized(_requiredString(root, 'task'));
    if (!AuraBrainTask.supported.contains(task)) {
      throw const AuraBrainProtocolException(
        AuraBrainErrorCode.unsupportedTask,
        'The requested task is not supported by Protocol V1.',
      );
    }
    final prompt = _normalized(_requiredString(root, 'prompt'));
    _checkLength(prompt, 4000, 'prompt');

    final privacy = _requiredMap(root, 'privacy');
    final retention = _requiredString(privacy, 'retention');
    final allowMemory = _requiredBool(privacy, 'allowMemory');
    final localOnly = _requiredBool(privacy, 'localOnly');
    if (retention != 'ephemeral' || allowMemory || !localOnly) {
      throw const AuraBrainProtocolException(
        AuraBrainErrorCode.invalidRequest,
        'Protocol V1 requires ephemeral retention, memory disabled, and local-only inference.',
      );
    }

    AuraBrainPage? page;
    if (task == AuraBrainTask.summarizePage) {
      final pageJson = _requiredMap(root, 'page');
      final title = _normalized(_requiredString(pageJson, 'title'));
      final url = _normalized(_requiredString(pageJson, 'url'));
      final selected = _normalized(_requiredString(pageJson, 'selectedText'));
      final visible = _normalized(_requiredString(pageJson, 'visibleText'));
      _checkLength(title, 500, 'page.title');
      _checkLength(url, 4096, 'page.url');
      _checkLength(selected, 8000, 'page.selectedText');
      _checkLength(visible, 32000, 'page.visibleText');
      if (selected.isEmpty && visible.isEmpty) {
        throw const AuraBrainProtocolException(
          AuraBrainErrorCode.invalidRequest,
          'At least one page text field must contain approved context.',
        );
      }
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !uri.hasAuthority ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw const AuraBrainProtocolException(
          AuraBrainErrorCode.invalidRequest,
          'page.url must be an HTTP or HTTPS URL.',
        );
      }
      page = AuraBrainPage(
        title: title,
        url: url,
        selectedText: selected,
        visibleText: visible,
      );
    }

    return AuraBrainRequest(
      protocolVersion: version,
      requestId: requestId,
      clientId: clientId,
      task: task,
      prompt: prompt,
      page: page,
    );
  }

  static Map<String, dynamic> _requiredMap(
    Map<String, dynamic> source,
    String key,
  ) {
    final value = source[key];
    if (value is! Map) {
      throw AuraBrainProtocolException(
        AuraBrainErrorCode.invalidRequest,
        '$key must be an object.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  static String _requiredString(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is! String) {
      throw AuraBrainProtocolException(
        AuraBrainErrorCode.invalidRequest,
        '$key must be a string.',
      );
    }
    return value;
  }

  static int _requiredInt(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is! int) {
      throw AuraBrainProtocolException(
        AuraBrainErrorCode.invalidRequest,
        '$key must be an integer.',
      );
    }
    return value;
  }

  static bool _requiredBool(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is! bool) {
      throw AuraBrainProtocolException(
        AuraBrainErrorCode.invalidRequest,
        '$key must be a boolean.',
      );
    }
    return value;
  }

  static String _normalized(String value) =>
      value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();

  static void _checkLength(String value, int maximum, String field) {
    if (value.length > maximum) {
      throw AuraBrainProtocolException(
        AuraBrainErrorCode.contextTooLarge,
        '$field exceeds $maximum characters.',
      );
    }
  }
}
