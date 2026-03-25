import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';

void main() {
  late ErrorHandlerService errorHandler;

  setUp(() {
    errorHandler = ErrorHandlerService();
  });

  group('ErrorHandlerService - handleError', () {
    test('should return user message for AuraException', () {
      final exception = AIServiceException.modelNotLoaded();

      final message = errorHandler.handleError(exception);

      expect(message, 'AI model is not loaded');
    });

    test('should handle SocketException and return user-friendly message', () {
      final message = errorHandler.handleError(
        Exception('SocketException: Failed host lookup'),
      );

      expect(message, contains('internet connection'));
    });

    test('should handle TimeoutException and return user-friendly message', () {
      final message = errorHandler.handleError(
        Exception('TimeoutException after 30 seconds'),
      );

      expect(message, contains('timed out'));
    });

    test('should handle FormatException and return user-friendly message', () {
      final message = errorHandler.handleError(
        FormatException('Invalid format'),
      );

      expect(message, contains('Invalid data format'));
    });

    test('should handle FileSystemException and return user-friendly message', () {
      final message = errorHandler.handleError(
        Exception('FileSystemException: Cannot open file'),
      );

      expect(message, contains('File access error'));
    });

    test('should return generic message for unknown errors', () {
      final message = errorHandler.handleError(
        Exception('Some unknown error'),
      );

      expect(message, 'An unexpected error occurred. Please try again.');
    });
  });

  group('ErrorHandlerService - shouldRetry', () {
    test('should not retry ValidationException', () {
      final exception = ValidationException.emptyInput('field');

      expect(errorHandler.shouldRetry(exception, 1), false);
    });

    test('should not retry PermissionException', () {
      final exception = PermissionException.denied('camera');

      expect(errorHandler.shouldRetry(exception, 1), false);
    });

    test('should not retry when max attempts reached', () {
      final exception = NetworkException.timeout('https://example.com');

      expect(errorHandler.shouldRetry(exception, 3, maxAttempts: 3), false);
    });

    test('should not retry offline NetworkException', () {
      final exception = NetworkException.noConnection();

      expect(errorHandler.shouldRetry(exception, 1), false);
    });

    test('should retry NetworkException with timeout', () {
      final exception = NetworkException.timeout('https://example.com');

      expect(errorHandler.shouldRetry(exception, 1, maxAttempts: 3), true);
    });

    test('should retry timeout errors', () {
      expect(errorHandler.shouldRetry(Exception('timeout'), 1), true);
    });

    test('should retry 503 errors', () {
      expect(errorHandler.shouldRetry(Exception('503 Service Unavailable'), 1), true);
    });
  });

  group('ErrorHandlerService - getRetryDelay', () {
    test('should calculate exponential backoff correctly', () {
      expect(errorHandler.getRetryDelay(0), const Duration(seconds: 1));
      expect(errorHandler.getRetryDelay(1), const Duration(seconds: 2));
      expect(errorHandler.getRetryDelay(2), const Duration(seconds: 4));
      expect(errorHandler.getRetryDelay(3), const Duration(seconds: 8));
      expect(errorHandler.getRetryDelay(4), const Duration(seconds: 16));
    });

    test('should clamp delay at 16 seconds', () {
      expect(errorHandler.getRetryDelay(5), const Duration(seconds: 16));
      expect(errorHandler.getRetryDelay(10), const Duration(seconds: 16));
    });
  });

  group('ErrorHandlerService - safeExecute', () {
    test('should return result when operation succeeds', () async {
      final result = await errorHandler.safeExecute(
        operation: () async => 'success',
        operationName: 'Test operation',
      );

      expect(result, 'success');
    });

    test('should return null when operation fails and no error handler', () async {
      final result = await errorHandler.safeExecute(
        operation: () async => throw Exception('Test error'),
        operationName: 'Test operation',
      );

      expect(result, null);
    });

    test('should call onError when operation fails', () async {
      final result = await errorHandler.safeExecute(
        operation: () async => throw Exception('Test error'),
        operationName: 'Test operation',
        onError: (error) => 'fallback',
      );

      expect(result, 'fallback');
    });
  });

  group('ErrorHandlerService - safeExecuteSync', () {
    test('should return result when operation succeeds', () {
      final result = errorHandler.safeExecuteSync(
        operation: () => 'success',
        operationName: 'Test operation',
      );

      expect(result, 'success');
    });

    test('should return null when operation fails and no error handler', () {
      final result = errorHandler.safeExecuteSync(
        operation: () => throw Exception('Test error'),
        operationName: 'Test operation',
      );

      expect(result, null);
    });

    test('should call onError when operation fails', () {
      final result = errorHandler.safeExecuteSync(
        operation: () => throw Exception('Test error'),
        operationName: 'Test operation',
        onError: (error) => 'fallback',
      );

      expect(result, 'fallback');
    });
  });

  group('ErrorHandlerService - executeWithRetry', () {
    test('should return result on first attempt when successful', () async {
      int attempts = 0;

      final result = await errorHandler.executeWithRetry(
        operation: () async {
          attempts++;
          return 'success';
        },
        operationName: 'Test operation',
        maxAttempts: 3,
      );

      expect(result, 'success');
      expect(attempts, 1);
    });

    test('should retry and succeed on second attempt', () async {
      int attempts = 0;

      final result = await errorHandler.executeWithRetry(
        operation: () async {
          attempts++;
          if (attempts == 1) {
            throw Exception('timeout');
          }
          return 'success';
        },
        operationName: 'Test operation',
        maxAttempts: 3,
      );

      expect(result, 'success');
      expect(attempts, 2);
    });

    test('should call onFinalError after max attempts', () async {
      int attempts = 0;

      final result = await errorHandler.executeWithRetry(
        operation: () async {
          attempts++;
          throw Exception('persistent error');
        },
        operationName: 'Test operation',
        maxAttempts: 2,
        onFinalError: (error) => 'fallback',
      );

      expect(result, 'fallback');
      expect(attempts, 2);
    });

    test('should not retry ValidationException', () async {
      int attempts = 0;

      try {
        await errorHandler.executeWithRetry(
          operation: () async {
            attempts++;
            throw ValidationException.emptyInput('field');
          },
          operationName: 'Test operation',
          maxAttempts: 3,
        );
        fail('Should have thrown');
      } catch (e) {
        expect(e, isA<ValidationException>());
        expect(attempts, 1); // Only one attempt
      }
    });

    test('should not retry offline NetworkException', () async {
      int attempts = 0;

      try {
        await errorHandler.executeWithRetry(
          operation: () async {
            attempts++;
            throw NetworkException.noConnection();
          },
          operationName: 'Test operation',
          maxAttempts: 3,
        );
        fail('Should have thrown');
      } catch (e) {
        expect(e, isA<NetworkException>());
        expect(attempts, 1); // Only one attempt
      }
    });
  });
}
