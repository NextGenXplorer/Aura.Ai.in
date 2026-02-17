import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'dart:isolate';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fllama/fllama.dart';
import 'package:workmanager/workmanager.dart';
import 'package:dio/dio.dart';
// import 'package:aura_mobile/core/utils/download_callback.dart'; // No longer needed directly here

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

/// Simulated RunAnywhere SDK Wrapper
/// In a real scenario, this would import the native package or platform channel.

@pragma('vm:entry-point')
class RunAnywhere {
  static final RunAnywhere _instance = RunAnywhere._internal();
  
  factory RunAnywhere() => _instance;
  
  RunAnywhere._internal();

  bool _isInitialized = false;
  double? _contextId;
  String? _currentModelPath;

  final _downloadStreamController = StreamController<DownloadUpdate>.broadcast();
  Stream<DownloadUpdate> get downloadUpdates => _downloadStreamController.stream;
  
  final ReceivePort _port = ReceivePort();



  // WORKMANAGER DOWNLOAD IMPLEMENTATION
  
  /// Download model from URL to local path
  /// Returns the taskId (URL in this case for simplicity in mapping)
  Future<String?> downloadModel(String url, String destinationPath) async {
    if (!_isInitialized) {
        await initialize();
    }
    
    // Ensure directory exists
    final file = File(destinationPath);
    final directory = file.parent;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    try {
      if (kDebugMode) print('RunAnywhere: Starting Workmanager Task: $url -> ${directory.path}');

      final String fileName = file.uri.pathSegments.last;
      
      // Dispatch Unique Work
      await Workmanager().registerOneOffTask(
        url, // Unique Name (using URL as ID)
        'download_model_task',
        inputData: {
          'url': url,
          'savePath': destinationPath,
          'fileName': fileName,
          'notificationId': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: true,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: Duration(seconds: 10),
      );
      
      // We return the URL as the taskId for tracking
      return url;
      
    } catch (e) {
      print('RunAnywhere: Download Dispatch Failed: $e');
      return null;
    }
  }

  /// Cancel a specific download task
  Future<void> cancelDownload(String taskId) async {
    await Workmanager().cancelByUniqueName(taskId);
  }

  StreamController<String>? _activeChatController;
  StreamSubscription? _tokenSubscription;

  /// Initialize the engine
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    if (kDebugMode) {
      print('RunAnywhere: Initializing...');
    }
    
    // Register background isolate communication
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
    
    _port.listen((dynamic data) {
       String id = data[0];
       int status = data[1];
       int progress = data[2];
       _downloadStreamController.add(DownloadUpdate(id, DownloadTaskStatus.fromInt(status), progress));
    });

    // Workmanager is initialized in main.dart

    // Initialize Token Listener Globally
    _tokenSubscription = Fllama.instance()?.onTokenStream?.listen((data) {
        if (kDebugMode) print('RunAnywhere: Stream Data: $data');

        if (data is! Map) return;

        if (data['function'] == 'completion') {
           final result = data['result'];
           if (result is Map && result.containsKey('token')) {
              final token = result['token']?.toString();
               // Dispatch to active controller if it exists
              if (_activeChatController != null && !_activeChatController!.isClosed) {
                  if (token != null) {
                       // if (kDebugMode) print('Token received: "$token"'); 
                      _activeChatController!.add(token);
                  }
              }
           }
        } else if (data['function'] == 'loadProgress') {
           if (kDebugMode) print('RunAnywhere: Load Progress: ${data['result']}');
        }
    });

    _isInitialized = true;
  }

  /// Get existing task ID for a URL
  Future<String?> getTaskIdForUrl(String url) async {
    // With Workmanager, we use the URL as the Unique Name/ID
    // So we just return the URL itself if we want to check it.
    // In a real implementation, we might check Workmanager().getWorkInfosByUniqueName(url)
    // but that is async and complex. For now, assuming if requested, it's the ID.
    return url; 
  }

  /// Load a model from the given path
  Future<void> loadModel(String modelPath) async {
    if (!_isInitialized) await initialize();
    
    if (_currentModelPath == modelPath && _contextId != null) {
      if (kDebugMode) print('RunAnywhere: Model already loaded: $modelPath');
      return; // Already loaded
    }

    if (_contextId != null) {
      if (kDebugMode) print('RunAnywhere: Unloading previous model');
      Fllama.instance()?.releaseContext(_contextId!);
      _contextId = null;
    }

    if (kDebugMode) print('RunAnywhere: Loading model from $modelPath');

    try {
      // Check if file exists
      final file = File(modelPath);
      if (!await file.exists()) {
        throw Exception('Model file not found at $modelPath');
      }

      final result = await Fllama.instance()?.initContext(
        modelPath,
        emitLoadProgress: true, // Useful for debugging
      );
      
      if (result != null && result.containsKey('contextId')) {
        final id = result['contextId'];
        if (id is double) {
          _contextId = id;
        } else if (id is int) {
          _contextId = id.toDouble();
        } else {
           // Fallback parsing just in case
           _contextId = double.tryParse(id.toString());
        }
        
        if (_contextId != null) {
            _currentModelPath = modelPath;
            if (kDebugMode) print('RunAnywhere: Model loaded successfully. ID: $_contextId');
        } else {
             throw Exception('Failed to parse contextId from $id');
        }
      } else {
        throw Exception('Failed to load model context: Result was null or missing contextId');
      }
    } catch (e) {
      print('RunAnywhere: Load Model Failed: $e');
      rethrow;
    }
  }

  /// Chat with the model (streaming)
  Stream<String> chat({
    required String prompt,
    String? systemPrompt,
    int maxTokens = 256,
  }) {
    if (!_isInitialized) throw Exception('RunAnywhere not initialized');
    if (_contextId == null) throw Exception('No model loaded');

    // If there is an active chat, close it? Or throw?
    // For now, we'll just overwrite it, but ideally we should only allow one at a time.
    if (_activeChatController != null && !_activeChatController!.isClosed) {
       _activeChatController!.close();
    }

    // Default to ChatML format
    final StringBuffer promptBuffer = StringBuffer();
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      promptBuffer.write('<|im_start|>system\n$systemPrompt\n<|im_end|>\n');
    }
    promptBuffer.write('<|im_start|>user\n$prompt\n<|im_end|>\n');
    promptBuffer.write('<|im_start|>assistant\n');
    final fullPrompt = promptBuffer.toString();
    
    if (kDebugMode) print('RunAnywhere: Sending Prompt: $fullPrompt');

    // Create a controller to stream tokens as they arrive
    _activeChatController = StreamController<String>();
    final controller = _activeChatController!;

    // Start inference asynchronously
    _runInference(controller, fullPrompt, maxTokens);
    
    return controller.stream;
  }

  Future<void> _runInference(StreamController<String> controller, String fullPrompt, int maxTokens) async {
    try {
      // NOTE: Listener is already active in initialize()

      await Fllama.instance()?.completion(
        _contextId!,
        prompt: fullPrompt,
        stop: ["<|im_end|>", "<|im_start|>", "User:", "System:"],
        temperature: 0.7,
        topP: 0.9,
        nPredict: maxTokens,
        emitRealtimeCompletion: true,
      );
    } catch (e) {
      print('Error during inference: $e');
      if (!controller.isClosed) {
        controller.add(" [Error: $e]");
      }
    } finally {
      if (kDebugMode) print('\nRunAnywhere: Generation Complete');
      // Do NOT cancel the global subscription
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
    if (!_isInitialized) throw Exception('RunAnywhere not initialized');
    return [];
  }

  void dispose() {
    _tokenSubscription?.cancel();
    if (_contextId != null) {
        Fllama.instance()?.releaseContext(_contextId!);
        _contextId = null;
    }
  }
}

