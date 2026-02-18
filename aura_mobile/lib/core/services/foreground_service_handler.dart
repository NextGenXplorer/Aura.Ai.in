import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:aura_mobile/core/services/parallel_downloader.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ForegroundDownloaderHandler());
}

class ForegroundDownloaderHandler extends TaskHandler {
  final ParallelDownloader _downloader = ParallelDownloader();

  int _lastReceivedBytes = 0;
  DateTime? _lastSpeedCheck;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _lastSpeedCheck = timestamp;
    _lastReceivedBytes = 0;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Not used for one-off downloads
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Cleanup on service stop
  }

  @override
  void onNotificationPressed() {
    // Could bring app to foreground here if needed
  }

  // Note: onReceiveData is void in the base class, so we can't use async.
  // We use unawaited to fire-and-forget the download.
  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    _startDownload(data);
  }

  Future<void> _startDownload(Map<dynamic, dynamic> data) async {
    final String url = data['url']?.toString() ?? '';
    final String savePath = data['savePath']?.toString() ?? '';
    final String fileName = data['fileName']?.toString() ?? 'model';

    if (url.isEmpty || savePath.isEmpty) return;

    DateTime lastUpdateTime = DateTime.now();

    try {
      await _downloader.download(
        url: url,
        savePath: savePath,
        concurrency: 8, // 8 parallel chunks for maximum throughput
        onProgress: (received, total) {
          final now = DateTime.now();
          final elapsedSinceUpdate = now.difference(lastUpdateTime).inMilliseconds;
          
          // THROTTLE: Only update platform channel every 500ms or at 100%
          if (elapsedSinceUpdate < 500 && received < total) {
            return;
          }
          lastUpdateTime = now;

          final percent = ((received / total) * 100).toInt();

          // Calculate download speed (MB/s)
          final elapsedSinceSpeedCheck =
              now.difference(_lastSpeedCheck!).inMilliseconds / 1000.0;
          String speedText = '';
          if (elapsedSinceSpeedCheck >= 1.0) {
            final bytesDelta = received - _lastReceivedBytes;
            final speedMBps = (bytesDelta / elapsedSinceSpeedCheck) / (1024 * 1024);
            speedText = ' • ${speedMBps.toStringAsFixed(1)} MB/s';
            _lastReceivedBytes = received;
            _lastSpeedCheck = now;
          }

          final receivedMB = (received / (1024 * 1024)).toStringAsFixed(1);
          final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);

          FlutterForegroundTask.updateService(
            notificationTitle: 'Downloading $fileName ($percent%)',
            notificationText: '$receivedMB MB / $totalMB MB$speedText',
          );

          // Send progress to main isolate (status 2 = running)
          FlutterForegroundTask.sendDataToMain([url, 2, percent]);
        },
      );

      // Success — notify main isolate (status 3 = complete)
      FlutterForegroundTask.updateService(
        notificationTitle: 'Download Complete ✓',
        notificationText: fileName,
      );
      FlutterForegroundTask.sendDataToMain([url, 3, 100]);
    } catch (e) {
      // Failure — notify main isolate (status 4 = failed)
      final errMsg = e.toString();
      FlutterForegroundTask.updateService(
        notificationTitle: 'Download Failed',
        notificationText:
            errMsg.length > 80 ? '${errMsg.substring(0, 80)}...' : errMsg,
      );
      FlutterForegroundTask.sendDataToMain([url, 4, 0]);
    } finally {
      // Keep notification visible briefly, then stop the service
      await Future.delayed(const Duration(seconds: 4));
      FlutterForegroundTask.stopService();
    }
  }
}
