import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'dart:isolate';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fllama/fllama.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:dio/dio.dart';

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



  // NATIVE DOWNLOAD IMPLEMENTATION (Using FlutterDownloader for Background Support)
  
  /// Download model from URL to local path
  /// Returns the taskId for the download
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
      if (kDebugMode) print('RunAnywhere: Starting FlutterDownloader: $url -> ${directory.path}');

      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: directory.path,
        fileName: file.uri.pathSegments.last, 
        showNotification: true,
        openFileFromNotification: false,
        saveInPublicStorage: false,
      );
      
      return taskId;
      
    } catch (e) {
      print('RunAnywhere: Download Enqueue Failed: $e');
      return null;
    }
  }

  /// Cancel a specific download task
  Future<void> cancelDownload(String taskId) async {
    await FlutterDownloader.cancel(taskId: taskId);
  }

  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    print('Background Isolate Callback: $id, $status, $progress'); // Debug log
    final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
    send?.send([id, status, progress]);
  }

  StreamController<String>? _activeChatController;
  StreamSubscription? _tokenSubscription;

  /// Initialize the engine
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    if (kDebugMode) {
      print('RunAnywhere: Initializing...');
    }
    
    // Register background isolate communication for downloader
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
    
    _port.listen((dynamic data) {
       String id = data[0];
       int status = data[1];
       int progress = data[2];
       _downloadStreamController.add(DownloadUpdate(id, DownloadTaskStatus.fromInt(status), progress));
    });

    await FlutterDownloader.registerCallback(RunAnywhere.downloadCallback);

    // Sync existing tasks
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks != null) {
      for (var task in tasks) {
        if (task.status == DownloadTaskStatus.running || 
            task.status == DownloadTaskStatus.enqueued ||
            task.status == DownloadTaskStatus.paused ||
            task.status == DownloadTaskStatus.complete) {
              _downloadStreamController.add(DownloadUpdate(task.taskId, task.status, task.progress));
        }
      }
    }

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
    if (!_isInitialized) await initialize();
    
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks == null) return null;
    
    for (var task in tasks) {
      if (task.url == url && 
          (task.status == DownloadTaskStatus.running || 
           task.status == DownloadTaskStatus.paused ||
           task.status == DownloadTaskStatus.enqueued)) {
        return task.taskId;
      }
    }
    return null;
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

