const int auraBrainProtocolVersion = 1;
const int auraBrainMaxSerializedRequestBytes = 128 * 1024;

abstract final class AuraBrainTask {
  static const healthCheck = 'healthCheck';
  static const summarizePage = 'summarizePage';
  static const supported = {healthCheck, summarizePage};
}

abstract final class AuraBrainErrorCode {
  static const invalidRequest = 'invalidRequest';
  static const unsupportedProtocol = 'unsupportedProtocol';
  static const unsupportedTask = 'unsupportedTask';
  static const unauthorizedClient = 'unauthorizedClient';
  static const contextTooLarge = 'contextTooLarge';
  static const needsSetup = 'needsSetup';
  static const brainBusy = 'brainBusy';
  static const modelUnavailable = 'modelUnavailable';
  static const localInferenceFailed = 'localInferenceFailed';
  static const requestCancelled = 'requestCancelled';
  static const serviceUnavailable = 'serviceUnavailable';
  static const internalError = 'internalError';
}

class AuraBrainProtocolException implements Exception {
  final String code;
  final String message;
  const AuraBrainProtocolException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}
