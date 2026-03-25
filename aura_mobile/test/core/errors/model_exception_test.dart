import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';

void main() {
  group('ModelException - Download errors', () {
    test('downloadFailed factory should create correct exception', () {
      final exception = ModelException.downloadFailed('Qwen 2.5 3B', 'Network timeout');

      expect(exception.message, 'Failed to download Qwen 2.5 3B');
      expect(exception.errorCode, 'MODEL_DOWNLOAD_FAILED');
      expect(exception.technicalDetails, contains('Network timeout'));
      expect(exception.recoverySuggestion, contains('Check your internet connection'));
      expect(exception.recoverySuggestion, contains('retried automatically'));
    });

    test('downloadTimeout factory should create correct exception', () {
      final exception = ModelException.downloadTimeout('Qwen 2.5 7B');

      expect(exception.message, 'Download timed out for Qwen 2.5 7B');
      expect(exception.errorCode, 'MODEL_DOWNLOAD_TIMEOUT');
      expect(exception.recoverySuggestion, contains('connection might be slow'));
      expect(exception.recoverySuggestion, contains('smaller model'));
    });

    test('insufficientSpace factory should create correct exception', () {
      final exception = ModelException.insufficientSpace('Qwen 2.5 3B', 2000, 1500);

      expect(exception.message, 'Not enough storage space');
      expect(exception.errorCode, 'MODEL_INSUFFICIENT_SPACE');
      expect(exception.technicalDetails, contains('requires 2000MB'));
      expect(exception.technicalDetails, contains('only 1500MB available'));
      expect(exception.recoverySuggestion, contains('Free up 500MB'));
    });
  });

  group('ModelException - Validation errors', () {
    test('corrupted factory should create correct exception', () {
      final exception = ModelException.corrupted('Qwen 2.5 1.5B', 'Size mismatch');

      expect(exception.message, 'Model file is corrupted');
      expect(exception.errorCode, 'MODEL_CORRUPTED');
      expect(exception.technicalDetails, contains('Qwen 2.5 1.5B'));
      expect(exception.technicalDetails, contains('Size mismatch'));
      expect(exception.recoverySuggestion, contains('Delete and re-download'));
    });

    test('invalidFormat factory should create correct exception', () {
      final exception = ModelException.invalidFormat('test-model.gguf');

      expect(exception.message, 'Invalid model format');
      expect(exception.errorCode, 'MODEL_INVALID_FORMAT');
      expect(exception.technicalDetails, contains('not a valid GGUF file'));
      expect(exception.recoverySuggestion, contains('corrupted'));
      expect(exception.recoverySuggestion, contains('downloading it again'));
    });

    test('sizeMismatch factory should create correct exception', () {
      final exception = ModelException.sizeMismatch('Qwen 2.5 0.5B', 397000000, 350000000);

      expect(exception.message, 'Model file size mismatch');
      expect(exception.errorCode, 'MODEL_SIZE_MISMATCH');
      expect(exception.technicalDetails, contains('Expected 397000000 bytes'));
      expect(exception.technicalDetails, contains('got 350000000 bytes'));
      expect(exception.recoverySuggestion, contains('download was incomplete'));
    });
  });

  group('ModelException - Loading errors', () {
    test('loadFailed factory should create correct exception', () {
      final exception = ModelException.loadFailed('Qwen 2.5 3B', 'Out of memory');

      expect(exception.message, 'Failed to load model');
      expect(exception.errorCode, 'MODEL_LOAD_FAILED');
      expect(exception.technicalDetails, contains('Out of memory'));
      expect(exception.recoverySuggestion, contains('corrupted or incompatible'));
      expect(exception.recoverySuggestion, contains('re-downloading'));
    });

    test('insufficientMemory factory should create correct exception', () {
      final exception = ModelException.insufficientMemory('Qwen 2.5 7B', 7500);

      expect(exception.message, 'Not enough memory to load model');
      expect(exception.errorCode, 'MODEL_INSUFFICIENT_MEMORY');
      expect(exception.technicalDetails, contains('requires 7500MB RAM'));
      expect(exception.recoverySuggestion, contains('Close other apps'));
      expect(exception.recoverySuggestion, contains('smaller model like Qwen 0.5B'));
    });

    test('notFound factory should create correct exception', () {
      final exception = ModelException.notFound('missing-model.gguf');

      expect(exception.message, 'Model not found');
      expect(exception.errorCode, 'MODEL_NOT_FOUND');
      expect(exception.technicalDetails, contains('does not exist'));
      expect(exception.recoverySuggestion, contains('Download the model'));
      expect(exception.recoverySuggestion, contains('Settings > Model Selection'));
    });
  });

  group('ModelException - Inheritance and structure', () {
    test('should extend AuraException', () {
      final exception = ModelException.downloadFailed('Test', 'Error');
      expect(exception, isA<AuraException>());
    });

    test('should have timestamp', () {
      final before = DateTime.now();
      final exception = ModelException.corrupted('Test', 'Reason');
      final after = DateTime.now();

      expect(exception.timestamp.isAfter(before.subtract(const Duration(seconds: 1))), true);
      expect(exception.timestamp.isBefore(after.add(const Duration(seconds: 1))), true);
    });

    test('should format fullDetails correctly', () {
      final exception = ModelException.downloadTimeout('Test Model');

      expect(exception.fullDetails, contains('Error Code: MODEL_DOWNLOAD_TIMEOUT'));
      expect(exception.fullDetails, contains('Message: Download timed out'));
      expect(exception.fullDetails, contains('Technical Details:'));
    });

    test('userMessage should return message', () {
      final exception = ModelException.loadFailed('Test', 'Error');
      expect(exception.userMessage, exception.message);
    });
  });
}
