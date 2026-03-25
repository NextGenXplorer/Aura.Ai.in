import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:logger/logger.dart';

/// Centralized error handling service for consistent error management
class ErrorHandlerService {
  static final ErrorHandlerService _instance = ErrorHandlerService._internal();
  factory ErrorHandlerService() => _instance;
  ErrorHandlerService._internal();

  final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      printTime: true,
    ),
  );

  // Track error rates to prevent spam
  final Map<String, DateTime> _lastErrorTimes = {};
  final Duration _errorRateLimit = const Duration(seconds: 5);

  /// Handle an exception and return a user-friendly message
  String handleError(dynamic error, {StackTrace? stackTrace}) {
    if (error is AuraException) {
      return _handleAuraException(error);
    } else {
      return _handleGenericError(error, stackTrace);
    }
  }

  String _handleAuraException(AuraException error) {
    // Rate limiting
    if (_shouldRateLimit(error.errorCode)) {
      debugPrint('Error rate-limited: ${error.errorCode}');
      return error.userMessage;
    }

    // Log the error
    _logger.e(
      error.fullDetails,
      error: error,
      stackTrace: error.stackTrace,
    );

    _lastErrorTimes[error.errorCode] = DateTime.now();
    return error.userMessage;
  }

  String _handleGenericError(dynamic error, StackTrace? stackTrace) {
    _logger.e(
      'Unhandled error: $error',
      error: error,
      stackTrace: stackTrace,
    );

    // Convert common errors to user-friendly messages
    final errorString = error.toString();

    if (errorString.contains('SocketException') ||
        errorString.contains('Failed host lookup')) {
      return 'No internet connection. Please check your network.';
    }

    if (errorString.contains('TimeoutException')) {
      return 'Request timed out. Please try again.';
    }

    if (errorString.contains('FormatException')) {
      return 'Invalid data format received. Please try again.';
    }

    if (errorString.contains('FileSystemException')) {
      return 'File access error. Please check permissions.';
    }

    // Generic fallback
    return 'An unexpected error occurred. Please try again.';
  }

  bool _shouldRateLimit(String errorCode) {
    if (!_lastErrorTimes.containsKey(errorCode)) {
      return false;
    }

    final lastTime = _lastErrorTimes[errorCode]!;
    final now = DateTime.now();
    return now.difference(lastTime) < _errorRateLimit;
  }

  /// Show error to user via SnackBar
  void showErrorSnackBar(BuildContext context, dynamic error, {StackTrace? stackTrace}) {
    final message = handleError(error, stackTrace: stackTrace);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        action: error is AuraException && error.recoverySuggestion != null
            ? SnackBarAction(
                label: 'Help',
                textColor: Colors.white,
                onPressed: () => _showRecoveryDialog(context, error),
              )
            : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showRecoveryDialog(BuildContext context, AuraException error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How to Fix'),
        content: Text(error.recoverySuggestion!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Log info message
  void logInfo(String message) {
    _logger.i(message);
  }

  /// Log warning
  void logWarning(String message) {
    _logger.w(message);
  }

  /// Log debug message (only in debug mode)
  void logDebug(String message) {
    if (kDebugMode) {
      _logger.d(message);
    }
  }

  /// Wrap an async operation with error handling
  Future<T?> safeExecute<T>({
    required Future<T> Function() operation,
    required String operationName,
    T? Function(dynamic error)? onError,
  }) async {
    try {
      logDebug('Starting operation: $operationName');
      final result = await operation();
      logDebug('Completed operation: $operationName');
      return result;
    } catch (error, stackTrace) {
      _logger.e(
        'Operation failed: $operationName',
        error: error,
        stackTrace: stackTrace,
      );

      if (onError != null) {
        return onError(error);
      }

      return null;
    }
  }

  /// Wrap a synchronous operation with error handling
  T? safeExecuteSync<T>({
    required T Function() operation,
    required String operationName,
    T? Function(dynamic error)? onError,
  }) {
    try {
      logDebug('Starting sync operation: $operationName');
      final result = operation();
      logDebug('Completed sync operation: $operationName');
      return result;
    } catch (error, stackTrace) {
      _logger.e(
        'Sync operation failed: $operationName',
        error: error,
        stackTrace: stackTrace,
      );

      if (onError != null) {
        return onError(error);
      }

      return null;
    }
  }

  /// Check if an error should retry
  bool shouldRetry(dynamic error, int attemptCount, {int maxAttempts = 3}) {
    if (attemptCount >= maxAttempts) return false;

    // Don't retry validation errors or permission errors (user errors that won't change on retry)
    if (error is ValidationException || error is PermissionException) {
      return false;
    }

    // Don't retry if explicitly offline
    if (error is NetworkException && error.errorCode == 'NETWORK_OFFLINE') {
      return false;
    }

    // Default to retrying for all other errors (they might be transient)
    // This includes NetworkException, AIServiceException, StorageException, and generic exceptions
    return true;
  }

  /// Calculate exponential backoff delay
  Duration getRetryDelay(int attemptCount) {
    // Exponential backoff: 1s, 2s, 4s, 8s...
    final delaySeconds = (1 << attemptCount).clamp(1, 16);
    return Duration(seconds: delaySeconds);
  }

  /// Execute operation with retry logic
  Future<T?> executeWithRetry<T>({
    required Future<T> Function() operation,
    required String operationName,
    int maxAttempts = 3,
    T? Function(dynamic error)? onFinalError,
  }) async {
    int attempts = 0;

    while (attempts < maxAttempts) {
      try {
        logDebug('Attempt ${attempts + 1}/$maxAttempts for: $operationName');
        return await operation();
      } catch (error, stackTrace) {
        attempts++;

        if (!shouldRetry(error, attempts, maxAttempts: maxAttempts)) {
          _logger.e(
            'Operation failed (no retry): $operationName',
            error: error,
            stackTrace: stackTrace,
          );

          if (onFinalError != null) {
            return onFinalError(error);
          }
          rethrow;
        }

        if (attempts < maxAttempts) {
          final delay = getRetryDelay(attempts);
          logWarning('Retry attempt $attempts after ${delay.inSeconds}s for: $operationName');
          await Future.delayed(delay);
        } else {
          _logger.e(
            'Operation failed after $maxAttempts attempts: $operationName',
            error: error,
            stackTrace: stackTrace,
          );

          if (onFinalError != null) {
            return onFinalError(error);
          }
          rethrow;
        }
      }
    }

    return null;
  }
}
