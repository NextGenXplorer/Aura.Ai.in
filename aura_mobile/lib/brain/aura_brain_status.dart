import 'dart:convert';

import 'aura_brain_protocol.dart';

enum AuraBrainStatusName {
  starting,
  needsSetup,
  ready,
  busy,
  unavailable,
  error,
}

class AuraBrainStatus {
  final AuraBrainStatusName status;
  final bool modelInstalled;
  final bool modelLoaded;
  final bool busy;
  final String? activeRequestId;
  final String message;

  const AuraBrainStatus({
    required this.status,
    required this.modelInstalled,
    required this.modelLoaded,
    required this.busy,
    required this.activeRequestId,
    required this.message,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'protocolVersion': auraBrainProtocolVersion,
    'status': status.name,
    'modelInstalled': modelInstalled,
    'modelLoaded': modelLoaded,
    'busy': busy,
    'activeRequestId': activeRequestId,
    'message': message,
  };

  String toJsonString() => jsonEncode(toJson());
}
