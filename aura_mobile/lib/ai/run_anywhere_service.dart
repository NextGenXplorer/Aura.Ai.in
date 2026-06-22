import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:fllama/fllama.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:aura_mobile/core/services/foreground_service_handler.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';
import 'package:disk_space_2/disk_space_2.dart';

/// Status of a download task
enum DownloadTaskStatus {
  undefined,
  enqueued,
  running,
  complete,
  failed,
  canceled,
  paused;

  static DownloadTaskStatus fromInt(int value) {
    if (value >= 0 && value < DownloadTaskStatus.values.length) {
      return DownloadTaskStatus.values[value];
    }
    return DownloadTaskStatus.undefined;
  }
}

class DownloadUpdate {
  final String id;
  final DownloadTaskStatus status;
  final int progress;
  DownloadUpdate(this.id, this.status, this.progress);
}

class RunAnywhere {
  static final RunAnywhere _instance = RunAnywhere._internal();

  factory RunAnywhere() => _instance;

  RunAnywhere._internal();

  bool _isInitialized = false;
  Completer<void>? _initCompleter;
  double? _contextId;
  String? _currentModelPath;
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  // Configuration
  static const Duration _modelLoadTimeout = Duration(seconds: 120);
  static const Duration _inferenceTimeout = Duration(seconds: 180); // 3 min for long code generation
  static const int _minFreeDiskSpaceMB = 100;

  /// Context window (in tokens) the GGUF engine is initialized with. 4096 gives
  /// the model a useful memory of the conversation, documents, and tool context
  /// while keeping the KV-cache memory footprint reasonable on mobile. Qwen3
  /// supports far larger windows, but 4096 balances capability vs. RAM on a
  /// typical phone.
  static const int _contextWindowTokens = 4096;
  static const int _promptBatchTokens = 512;

  /// Whether a model is currently loaded and ready for inference.
  bool get isModelLoaded => _contextId != null;

  final _downloadStreamController =
      StreamController<DownloadUpdate>.broadcast();
  Stream<DownloadUpdate> get downloadUpdates =>
      _downloadStreamController.stream;

  /// Initialize the engine — must be called once at app startup
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      _errorHandler.logInfo('RunAnywhere: Initializing...');

      // Initialize FlutterForegroundTask BEFORE any service calls.
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'download_channel',
          channelName: 'Model Downloads',
          channelDescription: 'AI model download progress',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: true,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );

      // Safe type casting when receiving data from the foreground task
      FlutterForegroundTask.addTaskDataCallback((data) {
        if (data is List && data.length >= 3) {
          try {
            final String id = data[0].toString();
            final int status = data[1] is int
                ? data[1] as int
                : int.tryParse(data[1].toString()) ?? 0;
            final int progress = data[2] is int
                ? data[2] as int
                : int.tryParse(data[2].toString()) ?? 0;
            _downloadStreamController.add(
              DownloadUpdate(id, DownloadTaskStatus.fromInt(status), progress),
            );
          } catch (e) {
            _errorHandler.logDebug('Failed to parse task data: $e');
          }
        }
      });

      // Initialize Token Listener Globally
      Fllama.instance()?.onTokenStream?.listen((data) {
        _errorHandler.logDebug('Stream Data: $data');

        if (data['function'] == 'completion') {
          final result = data['result'];
          if (result is Map && result.containsKey('token')) {
            final token = result['token']?.toString();
            if (_activeChatController != null &&
                !_activeChatController!.isClosed &&
                token != null) {
              _activeChatController!.add(token);
            }
          }
        } else if (data['function'] == 'loadProgress') {
          _errorHandler.logDebug('Load Progress: ${data['result']}');
        }
      });

      _isInitialized = true;
      _initCompleter?.complete();
      _errorHandler.logInfo('RunAnywhere: Initialization complete');
    } catch (e) {
      _errorHandler.logWarning('RunAnywhere initialization failed: $e');
      _initCompleter?.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  StreamController<String>? _activeChatController;
  Timer? _inferenceTimeoutTimer;

  /// Download model from URL to local path using a Foreground Service
  Future<String?> downloadModel(String url, String destinationPath) async {
    if (!_isInitialized) await initialize();

    try {
      // Validation
      if (url.trim().isEmpty) {
        throw ValidationException.emptyInput('Download URL');
      }

      // Check available disk space
      await _checkDiskSpace(destinationPath);

      // Ensure directory exists
      final file = File(destinationPath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      _errorHandler.logInfo('Starting model download: $url');

      final String fileName = file.uri.pathSegments.last;

      // Request battery optimization exemption
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      // Stop any existing service before starting a new download
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: 'Preparing Download',
        notificationText: fileName,
        callback: startCallback,
      );

      // Send download parameters to the service handler
      FlutterForegroundTask.sendDataToTask({
        'url': url,
        'savePath': destinationPath,
        'fileName': fileName,
      });

      _errorHandler.logInfo('Download dispatched successfully');
      return url;
    } catch (e) {
      if (e is AuraException) {
        _errorHandler.handleError(e);
        rethrow;
      }

      _errorHandler.logWarning('Download dispatch failed: $e');
      throw StorageException.databaseError('downloadModel', e);
    }
  }

  /// Check if there's enough disk space for download/model loading
  Future<void> _checkDiskSpace(String path) async {
    try {
      final freeSpace = await DiskSpace.getFreeDiskSpace;
      if (freeSpace != null && freeSpace < _minFreeDiskSpaceMB) {
        throw StorageException.insufficientSpace(_minFreeDiskSpaceMB);
      }
    } catch (e) {
      if (e is StorageException) {
        rethrow;
      }
      _errorHandler.logWarning('Disk space check failed: $e');
      // Continue anyway - check might fail but space might be available
    }
  }

  /// Cancel a specific download task
  Future<void> cancelDownload(String taskId) async {
    try {
      await FlutterForegroundTask.stopService();
      _errorHandler.logInfo('Download cancelled: $taskId');
    } catch (e) {
      _errorHandler.logWarning('Failed to cancel download: $e');
    }
  }

  /// Get existing task ID for a URL
  Future<String?> getTaskIdForUrl(String url) async {
    // The background service announces itself via the stream
    return null;
  }

  /// Load a model from the given path with comprehensive validation
  Future<void> loadModel(String modelPath) async {
    if (!_isInitialized) await initialize();

    // Check if model is already loaded
    if (_currentModelPath == modelPath && _contextId != null) {
      _errorHandler.logDebug('Model already loaded: $modelPath');
      return;
    }

    try {
      // 1. Validate file exists
      final file = File(modelPath);
      if (!await file.exists()) {
        final modelName = modelPath.split(Platform.pathSeparator).last;
        throw ModelException.notFound(modelName);
      }

      // 2. Check file size and validate format
      final fileSizeBytes = await file.length();
      final fileSizeMB = fileSizeBytes / (1024 * 1024);

      if (fileSizeMB < 1) {
        final modelName = modelPath.split(Platform.pathSeparator).last;
        throw ModelException.corrupted(modelName, 'File too small (${fileSizeMB.toStringAsFixed(2)} MB)');
      }

      // 3. Validate GGUF format
      if (!await _validateGGUFFormat(file)) {
        final modelName = modelPath.split(Platform.pathSeparator).last;
        throw ModelException.invalidFormat(modelName);
      }

      _errorHandler.logInfo(
        'Loading model: ${fileSizeMB.toStringAsFixed(2)} MB from $modelPath',
      );

      // 3. Unload previous model if exists
      if (_contextId != null) {
        _errorHandler.logDebug('Unloading previous model');
        try {
          Fllama.instance()?.releaseContext(_contextId!);
        } catch (e) {
          _errorHandler.logWarning('Failed to release previous context: $e');
        }
        _contextId = null;
        _currentModelPath = null;
      }

      // 4. Load model with timeout
      final initFuture = Fllama.instance()?.initContext(
        modelPath,
        nCtx: _contextWindowTokens,
        nBatch: _promptBatchTokens,
        emitLoadProgress: true,
      ) ?? Future.value(null);

      final result = await initFuture.timeout(
        _modelLoadTimeout,
        onTimeout: () {
          throw AIServiceException(
            message: 'Model loading timed out',
            technicalDetails: 'Loading exceeded ${_modelLoadTimeout.inSeconds} seconds',
            recoverySuggestion: 'Try using a smaller model or restart the app',
            errorCode: 'AI_MODEL_LOAD_TIMEOUT',
          );
        },
      );

      // 5. Validate result
      if (result == null || !result.containsKey('contextId')) {
        throw AIServiceException.modelLoadFailed(
          modelPath,
          'Result was null or missing contextId',
        );
      }

      // 6. Parse context ID
      final id = result['contextId'];
      if (id is double) {
        _contextId = id;
      } else if (id is int) {
        _contextId = id.toDouble();
      } else {
        _contextId = double.tryParse(id.toString());
      }

      if (_contextId == null) {
        throw AIServiceException.modelLoadFailed(
          modelPath,
          'Failed to parse contextId from $id',
        );
      }

      // 7. Success
      _currentModelPath = modelPath;
      _errorHandler.logInfo('Model loaded successfully. Context ID: $_contextId');
    } catch (e) {
      _contextId = null;
      _currentModelPath = null;

      if (e is AuraException) {
        _errorHandler.handleError(e);
        rethrow;
      }

      _errorHandler.logWarning('Model loading failed: $e');
      throw AIServiceException.modelLoadFailed(modelPath, e);
    }
  }

  /// Chat with the model (streaming) with timeout handling.
  /// [temperature] controls randomness: lower = more factual (0.3), higher = more creative (0.7).
  Stream<String> chat({
    required String prompt,
    String? systemPrompt,
    int maxTokens = 512,
    Duration? timeout,
    double temperature = 0.7,
  }) async* {
    // Validation
    if (!_isInitialized) {
      throw AIServiceException(
        message: 'AI service not initialized',
        technicalDetails: 'RunAnywhere.initialize() was not called',
        recoverySuggestion: 'Please restart the app',
        errorCode: 'AI_NOT_INITIALIZED',
      );
    }

    if (_contextId == null) {
      throw AIServiceException.modelNotLoaded();
    }

    if (prompt.trim().isEmpty) {
      throw ValidationException.emptyInput('Prompt');
    }

    try {
      // Close any active chat and wait for the previous inference to settle.
      // fllama only supports one inference at a time per context.
      if (_activeChatController != null && !_activeChatController!.isClosed) {
        await _activeChatController!.close();
        // Brief pause for native side to release — 50ms is enough on modern devices
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Build prompt in ChatML format
      final StringBuffer promptBuffer = StringBuffer();
      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        promptBuffer.write('<|im_start|>system\n$systemPrompt\n<|im_end|>\n');
      }
      promptBuffer.write('<|im_start|>user\n$prompt\n<|im_end|>\n');
      promptBuffer.write('<|im_start|>assistant\n');
      final fullPrompt = promptBuffer.toString();

      _errorHandler.logDebug('Starting inference (${maxTokens} tokens max)');

      _activeChatController = StreamController<String>();
      final controller = _activeChatController!;

      // Set up timeout timer — on timeout, gracefully close the stream
      // so whatever tokens were already generated still show up.
      final timeoutDuration = timeout ?? _inferenceTimeout;
      _inferenceTimeoutTimer = Timer(timeoutDuration, () {
        if (!controller.isClosed) {
          _errorHandler.logWarning(
            'Inference timeout after ${timeoutDuration.inSeconds}s — closing stream with partial output',
          );
          // Don't add error — just close the stream so partial response shows
          controller.close();
        }
      });

      // Start inference in background
      _runInference(controller, fullPrompt, maxTokens, temperature);

      // Stream tokens
      await for (final token in controller.stream) {
        yield token;
      }
    } catch (e) {
      if (e is AuraException) {
        _errorHandler.handleError(e);
        rethrow;
      }

      _errorHandler.logWarning('Chat inference failed: $e');
      throw AIServiceException(
        message: 'AI inference failed',
        technicalDetails: e.toString(),
        recoverySuggestion: 'Try starting a new chat or restarting the app',
        errorCode: 'AI_INFERENCE_FAILED',
      );
    } finally {
      _inferenceTimeoutTimer?.cancel();
      _inferenceTimeoutTimer = null;
    }
  }

  Future<void> _runInference(
    StreamController<String> controller,
    String fullPrompt,
    int maxTokens,
    double temperature,
  ) async {
    try {
      final instance = Fllama.instance();
      if (instance == null) {
        if (!controller.isClosed) {
          controller.addError(AIServiceException(
            message: 'AI engine not available',
            technicalDetails: 'Fllama instance is null',
            recoverySuggestion: 'Please restart the app',
            errorCode: 'AI_ENGINE_NULL',
          ));
        }
        return;
      }

      await instance.completion(
        _contextId!,
        prompt: fullPrompt,
        stop: [
          '<|im_end|>',
          '<|im_start|>',
          '<|endoftext|>',
          '\nHuman:',
          '\nUser:',
          '\nAssistant:',
        ],
        temperature: temperature,
        topP: temperature < 0.5 ? 0.75 : 0.85, // tighter nucleus = fewer hallucinations
        nPredict: maxTokens,
        emitRealtimeCompletion: true,
      );
    } catch (e) {
      _errorHandler.logWarning('Inference error: $e');
      if (!controller.isClosed) {
        controller.addError(e);
      }
    } finally {
      _errorHandler.logDebug('Inference complete');
      if (!controller.isClosed) {
        await controller.close();
      }
      if (_activeChatController == controller) {
        _activeChatController = null;
      }
    }
  }

  /// Generate embeddings for a given text
  Future<List<double>> getEmbeddings(String text) async {
    // Validation
    if (!_isInitialized) {
      throw AIServiceException(
        message: 'AI service not initialized',
        technicalDetails: 'RunAnywhere.initialize() was not called',
        recoverySuggestion: 'Please restart the app',
        errorCode: 'AI_NOT_INITIALIZED',
      );
    }

    if (!isModelLoaded) {
      throw AIServiceException.modelNotLoaded();
    }

    if (text.trim().isEmpty) {
      throw ValidationException.emptyInput('Text for embedding');
    }

    try {
      // TODO: Implement actual embedding generation with fllama
      // For now, return empty to maintain compatibility
      _errorHandler.logDebug('Embedding generation requested (not yet implemented)');
      return [];
    } catch (e) {
      _errorHandler.logWarning('Embedding generation failed: $e');
      throw AIServiceException.embeddingFailed(text, e);
    }
  }

  /// Unload the current model and free resources
  void unloadModel() {
    if (_contextId != null) {
      try {
        Fllama.instance()?.releaseContext(_contextId!);
        _errorHandler.logInfo('Model unloaded successfully');
      } catch (e) {
        _errorHandler.logWarning('Failed to unload model: $e');
      }
      _contextId = null;
      _currentModelPath = null;
    }
  }

  /// Get the current model path
  String? get currentModelPath => _currentModelPath;

  /// Validate GGUF file format by checking magic bytes
  Future<bool> _validateGGUFFormat(File file) async {
    try {
      // GGUF magic bytes: 'GGUF' (0x47475546 in big-endian, 0x46554747 in little-endian)
      const int ggufMagic = 0x46554747;

      final bytes = await file.openRead(0, 4).first;
      if (bytes.length < 4) {
        _errorHandler.logWarning('File too small to validate GGUF format');
        return false;
      }

      final magic = ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0, Endian.little);
      final isValid = magic == ggufMagic;

      if (!isValid) {
        _errorHandler.logWarning('Invalid GGUF magic bytes: 0x${magic.toRadixString(16)}');
      }

      return isValid;
    } catch (e) {
      _errorHandler.logWarning('Error validating GGUF format: $e');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _inferenceTimeoutTimer?.cancel();
    unloadModel();
    _downloadStreamController.close();
  }
}
