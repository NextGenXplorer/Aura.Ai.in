import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';

void main() {
  group('AuraException', () {
    test('should create exception with all fields', () {
      final exception = AIServiceException(
        message: 'Test message',
        technicalDetails: 'Technical details',
        recoverySuggestion: 'Try this',
        errorCode: 'TEST_ERROR',
      );

      expect(exception.message, 'Test message');
      expect(exception.technicalDetails, 'Technical details');
      expect(exception.recoverySuggestion, 'Try this');
      expect(exception.errorCode, 'TEST_ERROR');
      expect(exception.userMessage, 'Test message');
      expect(exception.timestamp, isNotNull);
    });

    test('should generate full details string', () {
      final exception = AIServiceException(
        message: 'Test message',
        technicalDetails: 'Technical details',
        recoverySuggestion: 'Try this',
        errorCode: 'TEST_ERROR',
      );

      final details = exception.fullDetails;

      expect(details, contains('Error Code: TEST_ERROR'));
      expect(details, contains('Message: Test message'));
      expect(details, contains('Technical Details: Technical details'));
      expect(details, contains('Recovery: Try this'));
      expect(details, contains('Timestamp:'));
    });

    test('toString should return error code and message', () {
      final exception = AIServiceException(
        message: 'Test message',
        technicalDetails: 'Technical details',
        errorCode: 'TEST_ERROR',
      );

      expect(exception.toString(), 'TEST_ERROR: Test message');
    });
  });

  group('AIServiceException', () {
    test('modelNotLoaded factory should create correct exception', () {
      final exception = AIServiceException.modelNotLoaded();

      expect(exception.message, 'AI model is not loaded');
      expect(exception.errorCode, 'AI_MODEL_NOT_LOADED');
      expect(exception.recoverySuggestion, contains('download and select a model'));
    });

    test('modelLoadFailed factory should create correct exception', () {
      final exception = AIServiceException.modelLoadFailed('/path/to/model', 'Test error');

      expect(exception.message, 'Failed to load AI model');
      expect(exception.errorCode, 'AI_MODEL_LOAD_FAILED');
      expect(exception.technicalDetails, contains('/path/to/model'));
      expect(exception.technicalDetails, contains('Test error'));
      expect(exception.recoverySuggestion, contains('corrupted'));
    });

    test('inferenceTimeout factory should create correct exception', () {
      final exception = AIServiceException.inferenceTimeout();

      expect(exception.message, 'AI response took too long');
      expect(exception.errorCode, 'AI_INFERENCE_TIMEOUT');
      expect(exception.recoverySuggestion, contains('smaller model'));
    });

    test('embeddingFailed factory should create correct exception', () {
      final exception = AIServiceException.embeddingFailed('test content', 'Test error');

      expect(exception.message, 'Failed to generate embeddings');
      expect(exception.errorCode, 'AI_EMBEDDING_FAILED');
      expect(exception.technicalDetails, contains('Content length: 12'));
      expect(exception.technicalDetails, contains('Test error'));
    });
  });

  group('NetworkException', () {
    test('noConnection factory should create correct exception', () {
      final exception = NetworkException.noConnection();

      expect(exception.message, 'No internet connection');
      expect(exception.errorCode, 'NETWORK_OFFLINE');
      expect(exception.recoverySuggestion, contains('Wi-Fi or mobile data'));
    });

    test('timeout factory should create correct exception', () {
      final exception = NetworkException.timeout('https://example.com');

      expect(exception.message, 'Connection timed out');
      expect(exception.errorCode, 'NETWORK_TIMEOUT');
      expect(exception.technicalDetails, contains('https://example.com'));
    });

    test('searchFailed factory should create correct exception', () {
      final exception = NetworkException.searchFailed('test query', 'Test error');

      expect(exception.message, 'Web search failed');
      expect(exception.errorCode, 'NETWORK_SEARCH_FAILED');
      expect(exception.technicalDetails, contains('test query'));
    });

    test('httpError factory should create correct exception for 404', () {
      final exception = NetworkException.httpError(404, 'https://example.com');

      expect(exception.message, 'Server error: 404');
      expect(exception.errorCode, 'NETWORK_HTTP_404');
      expect(exception.recoverySuggestion, contains('not found'));
    });

    test('httpError factory should create correct exception for 500', () {
      final exception = NetworkException.httpError(500, 'https://example.com');

      expect(exception.errorCode, 'NETWORK_HTTP_500');
      expect(exception.recoverySuggestion, contains('server is having issues'));
    });
  });

  group('StorageException', () {
    test('databaseError factory should create correct exception', () {
      final exception = StorageException.databaseError('saveMemory', 'DB error');

      expect(exception.message, 'Database operation failed');
      expect(exception.errorCode, 'STORAGE_DB_ERROR');
      expect(exception.technicalDetails, contains('saveMemory'));
      expect(exception.technicalDetails, contains('DB error'));
    });

    test('insufficientSpace factory should create correct exception', () {
      final exception = StorageException.insufficientSpace(100);

      expect(exception.message, 'Not enough storage space');
      expect(exception.errorCode, 'STORAGE_INSUFFICIENT_SPACE');
      expect(exception.technicalDetails, contains('100 MB'));
      expect(exception.recoverySuggestion, contains('free up some space'));
    });

    test('fileNotFound factory should create correct exception', () {
      final exception = StorageException.fileNotFound('/path/to/file');

      expect(exception.message, 'File not found');
      expect(exception.errorCode, 'STORAGE_FILE_NOT_FOUND');
      expect(exception.technicalDetails, contains('/path/to/file'));
    });

    test('fileCorrupted factory should create correct exception', () {
      final exception = StorageException.fileCorrupted('/path/to/file');

      expect(exception.message, 'File is corrupted');
      expect(exception.errorCode, 'STORAGE_FILE_CORRUPTED');
      expect(exception.recoverySuggestion, contains('re-downloading'));
    });
  });

  group('ValidationException', () {
    test('invalidInput factory should create correct exception', () {
      final exception = ValidationException.invalidInput('email', 'Invalid format');

      expect(exception.message, 'Invalid input: email');
      expect(exception.errorCode, 'VALIDATION_INVALID_INPUT');
      expect(exception.technicalDetails, 'Invalid format');
    });

    test('emptyInput factory should create correct exception', () {
      final exception = ValidationException.emptyInput('username');

      expect(exception.message, 'username cannot be empty');
      expect(exception.errorCode, 'VALIDATION_EMPTY_INPUT');
    });

    test('fileTooLarge factory should create correct exception', () {
      final exception = ValidationException.fileTooLarge(100, 50);

      expect(exception.message, 'File too large');
      expect(exception.errorCode, 'VALIDATION_FILE_TOO_LARGE');
      expect(exception.technicalDetails, contains('100 MB'));
      expect(exception.technicalDetails, contains('50 MB'));
    });

    test('unsupportedFormat factory should create correct exception', () {
      final exception = ValidationException.unsupportedFormat('.exe');

      expect(exception.message, 'Unsupported file format');
      expect(exception.errorCode, 'VALIDATION_UNSUPPORTED_FORMAT');
      expect(exception.recoverySuggestion, contains('PDF'));
    });
  });

  group('PermissionException', () {
    test('denied factory should create correct exception', () {
      final exception = PermissionException.denied('camera');

      expect(exception.message, 'Permission required');
      expect(exception.errorCode, 'PERMISSION_DENIED');
      expect(exception.recoverySuggestion, contains('camera permission in Settings'));
    });

    test('permanentlyDenied factory should create correct exception', () {
      final exception = PermissionException.permanentlyDenied('storage');

      expect(exception.message, 'Permission permanently denied');
      expect(exception.errorCode, 'PERMISSION_PERMANENTLY_DENIED');
      expect(exception.recoverySuggestion, contains('device Settings'));
    });
  });

  group('DeviceControlException', () {
    test('featureUnavailable factory should create correct exception', () {
      final exception = DeviceControlException.featureUnavailable('fingerprint');

      expect(exception.message, 'fingerprint is not available');
      expect(exception.errorCode, 'DEVICE_FEATURE_UNAVAILABLE');
    });

    test('appNotFound factory should create correct exception', () {
      final exception = DeviceControlException.appNotFound('WhatsApp');

      expect(exception.message, 'App not found: WhatsApp');
      expect(exception.errorCode, 'DEVICE_APP_NOT_FOUND');
      expect(exception.recoverySuggestion, contains('installed'));
    });
  });
}
