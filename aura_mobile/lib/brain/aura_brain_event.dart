import 'dart:convert';

import 'aura_brain_protocol.dart';

class AuraBrainEvent {
  final String requestId;
  final String type;
  final String? content;
  final String? errorCode;
  final String? message;

  const AuraBrainEvent({
    required this.requestId,
    required this.type,
    this.content,
    this.errorCode,
    this.message,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'protocolVersion': auraBrainProtocolVersion,
    'requestId': requestId,
    'type': type,
    'content': content,
    'errorCode': errorCode,
    'message': message,
  };

  String toJsonString() => jsonEncode(toJson());
}
