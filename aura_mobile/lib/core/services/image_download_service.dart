import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Downloads a generated (network) image and saves it into the device gallery
/// via a native MediaStore write. Used by the chat bubble's "download" button
/// on AI-generated images.
class ImageDownloadService {
  ImageDownloadService._();

  static const MethodChannel _channel = MethodChannel('com.aura.ai/app_control');
  static final Dio _dio = Dio();

  /// Fetches [url] and stores it in Pictures/AURA. Returns `true` on success.
  ///
  /// Throws nothing — callers get a simple bool so the UI can show a snackbar.
  static Future<bool> saveFromUrl(String url, {String? filename}) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      final data = response.data;
      if (data == null || data.isEmpty) {
        debugPrint('ImageDownload: empty response for $url');
        return false;
      }

      final bytes = Uint8List.fromList(data);
      final name = filename ?? _fileNameFor(url, response.headers);

      final String result = await _channel.invokeMethod('saveImageToGallery', {
        'bytes': bytes,
        'filename': name,
      });
      debugPrint('ImageDownload: $result');
      return true;
    } on PlatformException catch (e) {
      debugPrint('ImageDownload: native save failed: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('ImageDownload: failed: $e');
      return false;
    }
  }

  /// Picks a sensible filename + extension from the URL / content type.
  static String _fileNameFor(String url, Headers headers) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final contentType = headers.value('content-type') ?? '';
    String ext = 'jpg';
    if (contentType.contains('png') || url.toLowerCase().contains('.png')) {
      ext = 'png';
    } else if (contentType.contains('webp') ||
        url.toLowerCase().contains('.webp')) {
      ext = 'webp';
    }
    return 'aura_$ts.$ext';
  }
}
