import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';

class ModelManager {
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  // GGUF file magic bytes for validation
  static const int _ggufMagic = 0x46554747; // 'GGUF' in little-endian
  /// Get list of all downloaded models
  Future<List<String>> getDownloadedModels() async {
    return await _errorHandler.safeExecute(
      operation: () async {
        final docsDir = await getApplicationDocumentsDirectory();
        final modelFiles = await Directory(docsDir.path)
            .list()
            .where((entity) => entity is File && entity.path.endsWith('.gguf'))
            .map((entity) {
              // Platform-agnostic path splitting
              final path = entity.path;
              return path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);
            })
            .toList();

        return modelFiles;
      },
      operationName: 'Get downloaded models',
      onError: (error) {
        _errorHandler.logWarning('Failed to get downloaded models: $error');
        return <String>[];
      },
    ) ?? [];
  }

  /// Check if a specific model is downloaded and intact
  Future<bool> isModelDownloaded(String modelId) async {
    try {
      final model = modelCatalog.firstWhere((m) => m.id == modelId);
      final docsDir = await getApplicationDocumentsDirectory();
      final modelPath = '${docsDir.path}${Platform.pathSeparator}${model.fileName}';
      final file = File(modelPath);

      if (!await file.exists()) {
        return false;
      }

      final fileSize = await file.length();

      // Check size (allow 1% variance for metadata differences)
      if (fileSize < (model.sizeBytes * 0.99)) {
        _errorHandler.logWarning(
          'Model ${model.id} size mismatch: Expected ${model.sizeBytes}, got $fileSize',
        );
        return false;
      }

      // Validate GGUF format by checking magic bytes
      if (!await _validateGGUFFormat(file)) {
        _errorHandler.logWarning('Model ${model.id} failed GGUF format validation');
        return false;
      }

      return true;
    } catch (e) {
      _errorHandler.logWarning('Error checking model download status: $e');
      return false;
    }
  }

  /// Validate GGUF file format by checking magic bytes
  Future<bool> _validateGGUFFormat(File file) async {
    try {
      final bytes = await file.openRead(0, 4).first;
      if (bytes.length < 4) return false;

      // GGUF magic is 'GGUF' (0x47475546 in big-endian, 0x46554747 in little-endian)
      final magic = ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0, Endian.little);
      return magic == _ggufMagic;
    } catch (e) {
      _errorHandler.logWarning('Error validating GGUF format: $e');
      return false;
    }
  }

  /// Verify model integrity and delete if corrupt
  Future<bool> verifyAndCleanupModel(String modelId) async {
    try {
      final model = modelCatalog.firstWhere((m) => m.id == modelId);
      final docsDir = await getApplicationDocumentsDirectory();
      final modelPath = '${docsDir.path}${Platform.pathSeparator}${model.fileName}';
      final file = File(modelPath);

      if (!await file.exists()) {
        return false;
      }

      final fileSize = await file.length();
      bool isCorrupt = false;
      String? corruptionReason;

      // Check size
      if (fileSize < (model.sizeBytes * 0.99)) {
        isCorrupt = true;
        corruptionReason = 'Size mismatch: expected ${model.sizeBytes}, got $fileSize';
      }

      // Check GGUF format
      if (!isCorrupt && !await _validateGGUFFormat(file)) {
        isCorrupt = true;
        corruptionReason = 'Invalid GGUF format';
      }

      if (isCorrupt) {
        _errorHandler.logWarning('Deleting corrupt model ${model.id}: $corruptionReason');
        await file.delete();
        return false;
      }

      return true;
    } catch (e) {
      _errorHandler.logWarning('Error verifying model: $e');
      return false;
    }
  }

  /// Check available disk space (in bytes)
  Future<int> getAvailableDiskSpace() async {
    try {
      final freeSpace = await DiskSpace.getFreeDiskSpace;
      return ((freeSpace ?? 0) * 1024 * 1024).toInt(); // Convert MB to bytes
    } catch (e) {
      _errorHandler.logWarning('Error checking disk space: $e');
      return 0;
    }
  }

  /// Validate sufficient disk space for model download
  Future<void> validateDiskSpace(String modelId) async {
    final model = modelCatalog.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw ModelException.notFound(modelId),
    );

    final availableBytes = await getAvailableDiskSpace();
    final requiredBytes = (model.sizeBytes * 1.1).toInt(); // Add 10% buffer

    if (availableBytes < requiredBytes) {
      final availableMB = (availableBytes / (1024 * 1024)).toInt();
      final requiredMB = (requiredBytes / (1024 * 1024)).toInt();
      throw ModelException.insufficientSpace(model.name, requiredMB, availableMB);
    }
  }

  /// Get model file path
  Future<String> getModelPath(String modelId) async {
    final model = modelCatalog.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw ModelException.notFound(modelId),
    );
    final docsDir = await getApplicationDocumentsDirectory();
    return '${docsDir.path}${Platform.pathSeparator}${model.fileName}';
  }

  /// Delete a model
  Future<void> deleteModel(String modelId) async {
    final model = modelCatalog.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw ModelException.notFound(modelId),
    );

    return await _errorHandler.executeWithRetry(
      operation: () async {
        final modelPath = await getModelPath(modelId);
        final file = File(modelPath);

        if (await file.exists()) {
          await file.delete();
          _errorHandler.logInfo('Deleted model: ${model.name}');
        } else {
          throw ModelException.notFound(model.name);
        }
      },
      operationName: 'Delete model ${model.name}',
      maxAttempts: 2,
    );
  }

  /// Get model file size
  Future<int> getModelSize(String modelId) async {
    return await _errorHandler.safeExecute(
      operation: () async {
        final modelPath = await getModelPath(modelId);
        final file = File(modelPath);

        if (await file.exists()) {
          return await file.length();
        }
        return 0;
      },
      operationName: 'Get model size',
      onError: (error) {
        _errorHandler.logWarning('Error getting model size: $error');
        return 0;
      },
    ) ?? 0;
  }

  /// Get total storage used by all models
  Future<int> getTotalStorageUsed() async {
    int total = 0;
    for (final model in modelCatalog) {
      if (await isModelDownloaded(model.id)) {
        total += await getModelSize(model.id);
      }
    }
    return total;
  }

  /// Get ModelInfo by ID
  ModelInfo? getModelById(String modelId) {
    try {
      return modelCatalog.firstWhere((m) => m.id == modelId);
    } catch (e) {
      return null;
    }
  }
}
