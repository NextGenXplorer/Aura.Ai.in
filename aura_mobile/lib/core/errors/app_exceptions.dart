/// Base exception class for all Aura application errors
abstract class AuraException implements Exception {
  final String message;
  final String technicalDetails;
  final String? recoverySuggestion;
  final String errorCode;
  final DateTime timestamp;
  final StackTrace? stackTrace;

  AuraException({
    required this.message,
    required this.technicalDetails,
    this.recoverySuggestion,
    required this.errorCode,
    this.stackTrace,
  }) : timestamp = DateTime.now();

  @override
  String toString() => '$errorCode: $message';

  /// User-friendly message suitable for displaying in UI
  String get userMessage => message;

  /// Full error details for logging
  String get fullDetails =>
      'Error Code: $errorCode\n'
      'Message: $message\n'
      'Technical Details: $technicalDetails\n'
      'Recovery: ${recoverySuggestion ?? "None"}\n'
      'Timestamp: $timestamp';
}

/// AI/LLM service related errors
class AIServiceException extends AuraException {
  AIServiceException({
    required String message,
    required String technicalDetails,
    String? recoverySuggestion,
    String errorCode = 'AI_ERROR',
    StackTrace? stackTrace,
  }) : super(
          message: message,
          technicalDetails: technicalDetails,
          recoverySuggestion: recoverySuggestion,
          errorCode: errorCode,
          stackTrace: stackTrace,
        );

  factory AIServiceException.modelNotLoaded() => AIServiceException(
        message: 'AI model is not loaded',
        technicalDetails: 'User attempted inference without loading a model',
        recoverySuggestion: 'Please download and select a model from Settings',
        errorCode: 'AI_MODEL_NOT_LOADED',
      );

  factory AIServiceException.modelLoadFailed(String path, dynamic error) =>
      AIServiceException(
        message: 'Failed to load AI model',
        technicalDetails: 'Model path: $path, Error: $error',
        recoverySuggestion: 'The model file may be corrupted. Try re-downloading it.',
        errorCode: 'AI_MODEL_LOAD_FAILED',
      );

  factory AIServiceException.inferenceTimeout() => AIServiceException(
        message: 'AI response took too long',
        technicalDetails: 'Inference exceeded timeout threshold',
        recoverySuggestion: 'Try using a smaller model or simplifying your query',
        errorCode: 'AI_INFERENCE_TIMEOUT',
      );

  factory AIServiceException.embeddingFailed(String content, dynamic error) =>
      AIServiceException(
        message: 'Failed to generate embeddings',
        technicalDetails: 'Content length: ${content.length}, Error: $error',
        recoverySuggestion: 'This usually happens when the model is not loaded properly',
        errorCode: 'AI_EMBEDDING_FAILED',
      );

  factory AIServiceException.contextOverflow() => AIServiceException(
        message: 'Too much context for the model',
        technicalDetails: 'Context window exceeded',
        recoverySuggestion: 'Try starting a new chat or reducing document size',
        errorCode: 'AI_CONTEXT_OVERFLOW',
      );
}

/// Network and connectivity errors
class NetworkException extends AuraException {
  NetworkException({
    required String message,
    required String technicalDetails,
    String? recoverySuggestion,
    String errorCode = 'NETWORK_ERROR',
    StackTrace? stackTrace,
  }) : super(
          message: message,
          technicalDetails: technicalDetails,
          recoverySuggestion: recoverySuggestion,
          errorCode: errorCode,
          stackTrace: stackTrace,
        );

  factory NetworkException.noConnection() => NetworkException(
        message: 'No internet connection',
        technicalDetails: 'Device is offline',
        recoverySuggestion: 'Please check your Wi-Fi or mobile data connection',
        errorCode: 'NETWORK_OFFLINE',
      );

  factory NetworkException.timeout(String url) => NetworkException(
        message: 'Connection timed out',
        technicalDetails: 'Request to $url exceeded timeout',
        recoverySuggestion: 'Check your internet connection and try again',
        errorCode: 'NETWORK_TIMEOUT',
      );

  factory NetworkException.searchFailed(String query, dynamic error) =>
      NetworkException(
        message: 'Web search failed',
        technicalDetails: 'Query: $query, Error: $error',
        recoverySuggestion: 'Please try again or rephrase your query',
        errorCode: 'NETWORK_SEARCH_FAILED',
      );

  factory NetworkException.scrapeFailed(String url, dynamic error) =>
      NetworkException(
        message: 'Failed to read webpage',
        technicalDetails: 'URL: $url, Error: $error',
        recoverySuggestion: 'The website may be blocking access or is temporarily down',
        errorCode: 'NETWORK_SCRAPE_FAILED',
      );

  factory NetworkException.httpError(int statusCode, String url) =>
      NetworkException(
        message: 'Server error: $statusCode',
        technicalDetails: 'HTTP $statusCode from $url',
        recoverySuggestion: statusCode >= 500
            ? 'The server is having issues. Try again later.'
            : 'The requested resource was not found.',
        errorCode: 'NETWORK_HTTP_$statusCode',
      );
}

/// Database and storage errors
class StorageException extends AuraException {
  StorageException({
    required String message,
    required String technicalDetails,
    String? recoverySuggestion,
    String errorCode = 'STORAGE_ERROR',
    StackTrace? stackTrace,
  }) : super(
          message: message,
          technicalDetails: technicalDetails,
          recoverySuggestion: recoverySuggestion,
          errorCode: errorCode,
          stackTrace: stackTrace,
        );

  factory StorageException.databaseError(String operation, dynamic error) =>
      StorageException(
        message: 'Database operation failed',
        technicalDetails: 'Operation: $operation, Error: $error',
        recoverySuggestion: 'Try restarting the app',
        errorCode: 'STORAGE_DB_ERROR',
      );

  factory StorageException.insufficientSpace(int requiredMB) =>
      StorageException(
        message: 'Not enough storage space',
        technicalDetails: 'Required: $requiredMB MB',
        recoverySuggestion: 'Please free up some space on your device',
        errorCode: 'STORAGE_INSUFFICIENT_SPACE',
      );

  factory StorageException.fileNotFound(String path) => StorageException(
        message: 'File not found',
        technicalDetails: 'Path: $path',
        recoverySuggestion: 'The file may have been moved or deleted',
        errorCode: 'STORAGE_FILE_NOT_FOUND',
      );

  factory StorageException.fileCorrupted(String path) => StorageException(
        message: 'File is corrupted',
        technicalDetails: 'Path: $path',
        recoverySuggestion: 'Try re-downloading or re-uploading the file',
        errorCode: 'STORAGE_FILE_CORRUPTED',
      );
}

/// Android permission errors
class PermissionException extends AuraException {
  PermissionException({
    required String message,
    required String technicalDetails,
    String? recoverySuggestion,
    String errorCode = 'PERMISSION_ERROR',
    StackTrace? stackTrace,
  }) : super(
          message: message,
          technicalDetails: technicalDetails,
          recoverySuggestion: recoverySuggestion,
          errorCode: errorCode,
          stackTrace: stackTrace,
        );

  factory PermissionException.denied(String permission) =>
      PermissionException(
        message: 'Permission required',
        technicalDetails: 'Permission denied: $permission',
        recoverySuggestion: 'Please grant $permission permission in Settings',
        errorCode: 'PERMISSION_DENIED',
      );

  factory PermissionException.permanentlyDenied(String permission) =>
      PermissionException(
        message: 'Permission permanently denied',
        technicalDetails: 'User permanently denied: $permission',
        recoverySuggestion: 'Please enable $permission in device Settings > Apps > Aura',
        errorCode: 'PERMISSION_PERMANENTLY_DENIED',
      );
}

/// Input validation errors
class ValidationException extends AuraException {
  ValidationException({
    required String message,
    required String technicalDetails,
    String? recoverySuggestion,
    String errorCode = 'VALIDATION_ERROR',
    StackTrace? stackTrace,
  }) : super(
          message: message,
          technicalDetails: technicalDetails,
          recoverySuggestion: recoverySuggestion,
          errorCode: errorCode,
          stackTrace: stackTrace,
        );

  factory ValidationException.invalidInput(String field, String reason) =>
      ValidationException(
        message: 'Invalid input: $field',
        technicalDetails: reason,
        recoverySuggestion: 'Please check your input and try again',
        errorCode: 'VALIDATION_INVALID_INPUT',
      );

  factory ValidationException.emptyInput(String field) => ValidationException(
        message: '$field cannot be empty',
        technicalDetails: 'Required field is empty: $field',
        recoverySuggestion: 'Please provide a valid $field',
        errorCode: 'VALIDATION_EMPTY_INPUT',
      );

  factory ValidationException.fileTooLarge(int sizeMB, int maxSizeMB) =>
      ValidationException(
        message: 'File too large',
        technicalDetails: 'File size: $sizeMB MB, Max allowed: $maxSizeMB MB',
        recoverySuggestion: 'Please select a smaller file',
        errorCode: 'VALIDATION_FILE_TOO_LARGE',
      );

  factory ValidationException.unsupportedFormat(String format) =>
      ValidationException(
        message: 'Unsupported file format',
        technicalDetails: 'Format: $format',
        recoverySuggestion: 'Please use a supported file format (e.g., PDF)',
        errorCode: 'VALIDATION_UNSUPPORTED_FORMAT',
      );
}

/// Device control and platform-specific errors
class DeviceControlException extends AuraException {
  DeviceControlException({
    required String message,
    required String technicalDetails,
    String? recoverySuggestion,
    String errorCode = 'DEVICE_ERROR',
    StackTrace? stackTrace,
  }) : super(
          message: message,
          technicalDetails: technicalDetails,
          recoverySuggestion: recoverySuggestion,
          errorCode: errorCode,
          stackTrace: stackTrace,
        );

  factory DeviceControlException.featureUnavailable(String feature) =>
      DeviceControlException(
        message: '$feature is not available',
        technicalDetails: 'Device does not support this feature',
        recoverySuggestion: 'This feature may not be supported on your device',
        errorCode: 'DEVICE_FEATURE_UNAVAILABLE',
      );

  factory DeviceControlException.appNotFound(String appName) =>
      DeviceControlException(
        message: 'App not found: $appName',
        technicalDetails: 'Could not find package for $appName',
        recoverySuggestion: 'Make sure the app is installed on your device',
        errorCode: 'DEVICE_APP_NOT_FOUND',
      );

  factory DeviceControlException.operationFailed(String operation, dynamic error) =>
      DeviceControlException(
        message: 'Operation failed: $operation',
        technicalDetails: 'Error: $error',
        recoverySuggestion: 'Please try again',
        errorCode: 'DEVICE_OPERATION_FAILED',
      );
}

/// Model management errors (download, validation, loading)
class ModelException extends AuraException {
  ModelException({
    required String message,
    required String technicalDetails,
    String? recoverySuggestion,
    String errorCode = 'MODEL_ERROR',
    StackTrace? stackTrace,
  }) : super(
          message: message,
          technicalDetails: technicalDetails,
          recoverySuggestion: recoverySuggestion,
          errorCode: errorCode,
          stackTrace: stackTrace,
        );

  // Download errors
  factory ModelException.downloadFailed(String modelName, dynamic error) =>
      ModelException(
        message: 'Failed to download $modelName',
        technicalDetails: 'Download error: $error',
        recoverySuggestion:
            'Check your internet connection and try again. The download will be retried automatically.',
        errorCode: 'MODEL_DOWNLOAD_FAILED',
      );

  factory ModelException.downloadTimeout(String modelName) => ModelException(
        message: 'Download timed out for $modelName',
        technicalDetails: 'Network timeout during model download',
        recoverySuggestion:
            'Your connection might be slow. Try downloading a smaller model or use a faster network.',
        errorCode: 'MODEL_DOWNLOAD_TIMEOUT',
      );

  factory ModelException.insufficientSpace(
          String modelName, int requiredMB, int availableMB) =>
      ModelException(
        message: 'Not enough storage space',
        technicalDetails:
            'Model $modelName requires ${requiredMB}MB, but only ${availableMB}MB available',
        recoverySuggestion:
            'Free up ${requiredMB - availableMB}MB of space by deleting unused models or other files.',
        errorCode: 'MODEL_INSUFFICIENT_SPACE',
      );

  // Validation errors
  factory ModelException.corrupted(String modelName, String reason) =>
      ModelException(
        message: 'Model file is corrupted',
        technicalDetails: 'Model $modelName failed validation: $reason',
        recoverySuggestion:
            'The download may have been incomplete. Delete and re-download the model.',
        errorCode: 'MODEL_CORRUPTED',
      );

  factory ModelException.invalidFormat(String modelName) => ModelException(
        message: 'Invalid model format',
        technicalDetails: 'Model $modelName is not a valid GGUF file',
        recoverySuggestion:
            'This file may be corrupted or not a supported model format. Try downloading it again.',
        errorCode: 'MODEL_INVALID_FORMAT',
      );

  factory ModelException.sizeMismatch(
          String modelName, int expectedBytes, int actualBytes) =>
      ModelException(
        message: 'Model file size mismatch',
        technicalDetails:
            'Expected ${expectedBytes} bytes, got ${actualBytes} bytes for $modelName',
        recoverySuggestion: 'The download was incomplete. Delete and try downloading again.',
        errorCode: 'MODEL_SIZE_MISMATCH',
      );

  // Loading errors
  factory ModelException.loadFailed(String modelName, dynamic error) =>
      ModelException(
        message: 'Failed to load model',
        technicalDetails: 'Could not load $modelName: $error',
        recoverySuggestion:
            'The model file may be corrupted or incompatible. Try re-downloading it.',
        errorCode: 'MODEL_LOAD_FAILED',
      );

  factory ModelException.insufficientMemory(String modelName, int requiredMB) =>
      ModelException(
        message: 'Not enough memory to load model',
        technicalDetails: 'Model $modelName requires ${requiredMB}MB RAM',
        recoverySuggestion:
            'Close other apps to free up memory, or try a smaller model like Qwen 0.5B.',
        errorCode: 'MODEL_INSUFFICIENT_MEMORY',
      );

  factory ModelException.notFound(String modelName) => ModelException(
        message: 'Model not found',
        technicalDetails: 'Model file for $modelName does not exist',
        recoverySuggestion: 'Download the model from Settings > Model Selection.',
        errorCode: 'MODEL_NOT_FOUND',
      );
}

/// Workflow execution and management errors
class WorkflowException extends AuraException {
  WorkflowException({
    required String message,
    required String technicalDetails,
    String? recoverySuggestion,
    String errorCode = 'WORKFLOW_ERROR',
    StackTrace? stackTrace,
  }) : super(
          message: message,
          technicalDetails: technicalDetails,
          recoverySuggestion: recoverySuggestion,
          errorCode: errorCode,
          stackTrace: stackTrace,
        );

  // Step execution errors
  factory WorkflowException.stepFailed(int stepNumber, String stepMessage, dynamic error) =>
      WorkflowException(
        message: 'Step $stepNumber failed to execute',
        technicalDetails: 'Step: "$stepMessage", Error: $error',
        recoverySuggestion:
            'The workflow encountered an error. You can try again or modify your request.',
        errorCode: 'WORKFLOW_STEP_FAILED',
      );

  factory WorkflowException.stepTimeout(int stepNumber, String stepMessage) =>
      WorkflowException(
        message: 'Step $stepNumber timed out',
        technicalDetails: 'Step "$stepMessage" exceeded maximum execution time',
        recoverySuggestion: 'Try simplifying the step or breaking it into smaller parts.',
        errorCode: 'WORKFLOW_STEP_TIMEOUT',
      );

  factory WorkflowException.maxRetriesExceeded(int stepNumber, String stepMessage) =>
      WorkflowException(
        message: 'Step $stepNumber failed after retries',
        technicalDetails: 'Step "$stepMessage" failed after maximum retry attempts',
        recoverySuggestion:
            'This step consistently fails. Check if the request is valid and try again later.',
        errorCode: 'WORKFLOW_MAX_RETRIES',
      );

  // Validation errors
  factory WorkflowException.invalidWorkflow(String reason) => WorkflowException(
        message: 'Invalid workflow',
        technicalDetails: 'Workflow validation failed: $reason',
        recoverySuggestion: 'Please rephrase your request or break it into simpler steps.',
        errorCode: 'WORKFLOW_INVALID',
      );

  factory WorkflowException.circularDependency(String details) => WorkflowException(
        message: 'Circular dependency detected',
        technicalDetails: details,
        recoverySuggestion: 'The workflow steps have circular dependencies. Reorder your request.',
        errorCode: 'WORKFLOW_CIRCULAR_DEPENDENCY',
      );

  factory WorkflowException.missingDependency(String stepMessage, String dependency) =>
      WorkflowException(
        message: 'Missing required dependency',
        technicalDetails: 'Step "$stepMessage" requires "$dependency" which is not available',
        recoverySuggestion:
            'Make sure previous steps provide the required data, or include it in your request.',
        errorCode: 'WORKFLOW_MISSING_DEPENDENCY',
      );

  // Persistence errors
  factory WorkflowException.saveFailed(dynamic error) => WorkflowException(
        message: 'Failed to save workflow',
        technicalDetails: 'Could not persist workflow state: $error',
        recoverySuggestion: 'The workflow cannot be resumed. Try executing it again.',
        errorCode: 'WORKFLOW_SAVE_FAILED',
      );

  factory WorkflowException.loadFailed(String workflowId, dynamic error) =>
      WorkflowException(
        message: 'Failed to load workflow',
        technicalDetails: 'Could not restore workflow $workflowId: $error',
        recoverySuggestion: 'The saved workflow is corrupted. Start a new workflow instead.',
        errorCode: 'WORKFLOW_LOAD_FAILED',
      );

  factory WorkflowException.workflowNotFound(String workflowId) => WorkflowException(
        message: 'Workflow not found',
        technicalDetails: 'No saved workflow with ID: $workflowId',
        recoverySuggestion: 'The workflow may have expired or been deleted.',
        errorCode: 'WORKFLOW_NOT_FOUND',
      );

  // Execution errors
  factory WorkflowException.cancelled(int completedSteps, int totalSteps) =>
      WorkflowException(
        message: 'Workflow cancelled',
        technicalDetails: 'Completed $completedSteps of $totalSteps steps before cancellation',
        recoverySuggestion: 'You can start a new workflow or try resuming if available.',
        errorCode: 'WORKFLOW_CANCELLED',
      );

  factory WorkflowException.executionFailed(String reason) => WorkflowException(
        message: 'Workflow execution failed',
        technicalDetails: reason,
        recoverySuggestion: 'Try breaking your request into simpler steps.',
        errorCode: 'WORKFLOW_EXECUTION_FAILED',
      );
}
