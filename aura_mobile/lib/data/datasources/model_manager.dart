import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';

class ModelManager {
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  // GGUF file magic bytes for validation
  static const int _ggufMagic = 0x46554747; // 'GGUF' in little-endian

  // LiteRT `.task` files are MediaPipe Task bundles, which are ZIP archives.
  // A ZIP archive begins with one of these local-file-header signatures.
  static const List<int> _zipLocalFileHeader = [0x50, 0x4B, 0x03, 0x04]; // 'PK\x03\x04'
  static const List<int> _zipEmptyArchive = [0x50, 0x4B, 0x05, 0x06]; // 'PK\x05\x06'
  static const List<int> _zipSpannedArchive = [0x50, 0x4B, 0x07, 0x08]; // 'PK\x07\x08'

  // LiteRT `.litertlm` files are LiteRT-LM unified containers whose header
  // begins with the ASCII magic string 'LITERTLM'.
  static const List<int> _litertlmMagic = [
    0x4C, 0x49, 0x54, 0x45, 0x52, 0x54, 0x4C, 0x4D, // 'LITERTLM'
  ];

  // Supported LiteRT container extensions.
  static const String _taskExtension = '.task';
  static const String _litertlmExtension = '.litertlm';
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

      // Validate the file format header for the model's engine.
      if (!await _validateModelFormat(file, model)) {
        _errorHandler.logWarning(
          'Model ${model.id} failed ${model.engine.name} format validation',
        );
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

  /// Validate a model file's format header based on the engine that owns it.
  ///
  /// - `gguf` models keep the existing GGUF magic-byte check.
  /// - `litert` models validate the `.task` / `.litertlm` container header.
  Future<bool> _validateModelFormat(File file, ModelInfo model) async {
    switch (model.engine) {
      case AIEngine.gguf:
        return _validateGGUFFormat(file);
      case AIEngine.litert:
        return _validateLiteRtFormat(file, model.fileName);
    }
  }

  /// Validate a LiteRT container file by checking its header against the
  /// signature implied by the file's extension.
  ///
  /// `.task` files may be either MediaPipe Task bundles (ZIP archives) or
  /// TFLite FlatBuffer containers. We accept both formats: ZIP signature OR
  /// a non-empty file with at least 1KB (TFLite FlatBuffers don't have a
  /// universally consistent magic header, so we rely on size + extension).
  /// `.litertlm` files are LiteRT-LM unified containers and begin with the
  /// ASCII magic string 'LITERTLM'.
  Future<bool> _validateLiteRtFormat(File file, String fileName) async {
    try {
      final lowerName = fileName.toLowerCase();
      if (lowerName.endsWith(_taskExtension)) {
        // Check if it's a ZIP-based .task file first.
        final bytes = await file.openRead(0, 4).first;
        if (bytes.length < 4) return false;
        final header = bytes.sublist(0, 4);
        if (_bytesMatch(header, _zipLocalFileHeader) ||
            _bytesMatch(header, _zipEmptyArchive) ||
            _bytesMatch(header, _zipSpannedArchive)) {
          return true;
        }
        // Not a ZIP — accept if it's a non-trivial file (TFLite FlatBuffer
        // or other valid .task container). A file >= 1KB with .task extension
        // that downloaded successfully is considered valid.
        final fileSize = await file.length();
        return fileSize >= 1024;
      }

      if (lowerName.endsWith(_litertlmExtension)) {
        final bytes = await file.openRead(0, _litertlmMagic.length).first;
        if (bytes.length < _litertlmMagic.length) return false;
        return _bytesMatch(bytes.sublist(0, _litertlmMagic.length), _litertlmMagic);
      }

      // Unsupported LiteRT extension.
      _errorHandler.logWarning('Unsupported LiteRT file extension for $fileName');
      return false;
    } catch (e) {
      _errorHandler.logWarning('Error validating LiteRT format: $e');
      return false;
    }
  }

  /// Returns true when [actual] starts with the same bytes as [expected].
  bool _bytesMatch(List<int> actual, List<int> expected) {
    if (actual.length < expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (actual[i] != expected[i]) return false;
    }
    return true;
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

      // Check format header for the model's engine.
      if (!isCorrupt && !await _validateModelFormat(file, model)) {
        isCorrupt = true;
        corruptionReason = 'Invalid ${model.engine.name} format';
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

  /// Remove a partially downloaded model file if present.
  ///
  /// Safe to call when the file does not exist; engine-agnostic, so it works
  /// for both `gguf` and `litert` models. Used to clean up after a download
  /// fails on all attempts (Req 7.5).
  Future<void> removePartialDownload(String modelId) async {
    try {
      final modelPath = await getModelPath(modelId);
      final file = File(modelPath);
      if (await file.exists()) {
        await file.delete();
        _errorHandler.logInfo('Removed partial download for $modelId');
      }
    } catch (e) {
      _errorHandler.logWarning('Failed to remove partial download for $modelId: $e');
    }
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
