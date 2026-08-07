import 'dart:async';
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:aura_mobile/core/services/foreground_service_handler.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';
import 'package:disk_space_2/disk_space_2.dart';

/// Status of a download task.
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

/// A single update from the download pipeline.
class DownloadUpdate {
  final String id;
  final DownloadTaskStatus status;
  final int progress;
  DownloadUpdate(this.id, this.status, this.progress);
}

/// Lightweight download service for model files.
///
/// Replaces the download functionality that was previously embedded in
/// RunAnywhere. Uses FlutterForegroundTask for background downloads with
/// progress reporting.
class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  bool _isInitialized = false;
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  static const int _minFreeDiskSpaceMB = 100;

  final _downloadStreamController =
      StreamController<DownloadUpdate>.broadcast();
  Stream<DownloadUpdate> get downloadUpdates =>
      _downloadStreamController.stream;

  /// Initialize the download service — sets up foreground task communication.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
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

      _isInitialized = true;
      _errorHandler.logInfo('DownloadService: Initialized');
    } catch (e) {
      _errorHandler.logWarning('DownloadService initialization failed: $e');
      rethrow;
    }
  }

  /// Download a model from [url] to [destinationPath] using a foreground service.
  ///
  /// Returns the task ID (URL) on success, or throws on failure.
  Future<String?> downloadModel(String url, String destinationPath) async {
    if (!_isInitialized) await initialize();

    try {
      if (url.trim().isEmpty) {
        throw ValidationException.emptyInput('Download URL');
      }

      await _checkDiskSpace(destinationPath);

      final file = File(destinationPath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      _errorHandler.logInfo('Starting model download: $url');

      final String fileName = file.uri.pathSegments.last;

      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

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

  /// Cancel a running download task.
  Future<void> cancelDownload(String taskId) async {
    try {
      await FlutterForegroundTask.stopService();
      _errorHandler.logInfo('Download cancelled: $taskId');
    } catch (e) {
      _errorHandler.logWarning('Failed to cancel download: $e');
    }
  }

  Future<void> _checkDiskSpace(String path) async {
    try {
      final freeSpace = await DiskSpace.getFreeDiskSpace;
      if (freeSpace != null && freeSpace < _minFreeDiskSpaceMB) {
        throw StorageException.insufficientSpace(_minFreeDiskSpaceMB);
      }
    } catch (e) {
      if (e is StorageException) rethrow;
      _errorHandler.logWarning('Disk space check failed: $e');
    }
  }

  void dispose() {
    _downloadStreamController.close();
  }
}
