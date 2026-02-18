import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ParallelDownloader {
  final Dio dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 90),
  ));

  Future<void> download({
    required String url,
    required String savePath,
    int concurrency = 8,
    Function(int received, int total)? onProgress,
  }) async {
    // 1. Get file size via HEAD request
    final headResponse = await dio.head(url);
    final totalSize = int.tryParse(
          headResponse.headers.value('content-length') ?? '0',
        ) ??
        0;

    if (totalSize <= 0) {
      // Fallback to single-stream download if size is unknown
      await dio.download(url, savePath, onReceiveProgress: onProgress);
      return;
    }

    final chunkSize = (totalSize / concurrency).ceil();
    final List<String> chunkPaths = [];

    // Ensure directory exists
    final saveFile = File(savePath);
    if (!await saveFile.parent.exists()) {
      await saveFile.parent.create(recursive: true);
    }

    // FIX: Use a List<int> to track per-chunk received bytes.
    // This avoids the race condition of a shared counter being
    // incremented by 4 concurrent async operations.
    final List<int> chunkReceived = List<int>.filled(concurrency, 0);

    void reportProgress() {
      final totalReceived = chunkReceived.fold<int>(0, (a, b) => a + b);
      onProgress?.call(totalReceived, totalSize);
    }

    final List<Future<void>> futures = [];

    for (int i = 0; i < concurrency; i++) {
      final start = i * chunkSize;
      final end = (i == concurrency - 1) ? totalSize - 1 : (i + 1) * chunkSize - 1;
      final chunkPath = '$savePath.chunk$i';
      chunkPaths.add(chunkPath);
      final chunkIndex = i;

      futures.add(
        _downloadChunk(
          url: url,
          path: chunkPath,
          start: start,
          end: end,
          onChunkProgress: (received) {
            chunkReceived[chunkIndex] = received;
            reportProgress();
          },
        ),
      );
    }

    try {
      await Future.wait(futures);
      
      final tempPath = '$savePath.part';
      await _mergeFiles(chunkPaths, tempPath);

      // Final integrity check before renaming
      final tempFile = File(tempPath);
      final finalSize = await tempFile.length();
      
      if (finalSize != totalSize) {
        throw Exception(
          'Download incomplete: Expected $totalSize bytes, got $finalSize',
        );
      }

      // Atomic rename: the file only exists at savePath if it's 100% complete
      await tempFile.rename(savePath);
      
    } catch (e) {
      // Clean up final file if it somehow exists and is corrupted
      final f = File(savePath);
      if (await f.exists()) await f.delete();
      rethrow;
    } finally {
      // Clean up ALL temporary files: chunks and .part file
      final tempPart = File('$savePath.part');
      if (await tempPart.exists()) {
        try { await tempPart.delete(); } catch (_) {}
      }
      
      for (var path in chunkPaths) {
        final f = File(path);
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _downloadChunk({
    required String url,
    required String path,
    required int start,
    required int end,
    required Function(int received) onChunkProgress,
  }) async {
    final file = File(path);
    int attempts = 0;
    const maxAttempts = 3;

    while (attempts < maxAttempts) {
      try {
        int existingSize = 0;
        if (await file.exists()) {
          existingSize = await file.length();
        }
        final expectedSize = end - start + 1;

        if (existingSize > expectedSize) {
          await file.delete();
          attempts++;
          continue; // Restart chunk
        } else if (existingSize == expectedSize) {
          onChunkProgress(existingSize);
          return;
        }

        // Report what we have
        onChunkProgress(existingSize);

        final response = await dio.get(
          url,
          options: Options(
            headers: {'Range': 'bytes=${start + existingSize}-$end'},
            responseType: ResponseType.stream,
          ),
        );

        final raf = await file.open(mode: FileMode.append);
        int chunkTotal = existingSize;

        try {
          final stream = response.data.stream as Stream<List<int>>;
          await for (final bytes in stream) {
            await raf.writeFrom(bytes);
            chunkTotal += bytes.length;
            onChunkProgress(chunkTotal);
          }
          return; // Success!
        } finally {
          await raf.close();
        }
      } catch (e) {
        attempts++;
        if (kDebugMode) print('RunAnywhere: Chunk download attempt $attempts failed: $e');
        if (attempts >= maxAttempts) rethrow;
        // Wait 1s before retry
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _mergeFiles(List<String> paths, String targetPath) async {
    final targetFile = File(targetPath);
    final raf = await targetFile.open(mode: FileMode.write);
    try {
      for (var path in paths) {
        final chunkFile = File(path);
        // Read in 4MB blocks to avoid loading entire chunk into memory
        final raf2 = await chunkFile.open(mode: FileMode.read);
        try {
          const blockSize = 4 * 1024 * 1024; // 4 MB
          List<int> block;
          do {
            block = await raf2.read(blockSize);
            if (block.isNotEmpty) await raf.writeFrom(block);
          } while (block.length == blockSize);
        } finally {
          await raf2.close();
        }
      }
    } finally {
      await raf.close();
    }
  }
}
