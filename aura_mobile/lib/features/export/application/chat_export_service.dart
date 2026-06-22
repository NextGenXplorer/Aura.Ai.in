import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

enum ExportResult { success, empty, error, timeout, insufficientStorage }

final chatExportServiceProvider = Provider((ref) => ChatExportService());

class ChatExportService {
  /// Convert messages to Markdown string.
  ///
  /// Each message is formatted as:
  /// **Role** — yyyy-MM-dd HH:mm
  ///
  /// body
  ///
  /// ---
  ///
  /// Pure function — no side effects.
  String convertToMarkdown(List<Map<String, String>> messages) {
    final now = DateTime.now();
    final timestampFormat = DateFormat('yyyy-MM-dd HH:mm');
    final buffer = StringBuffer();

    for (final message in messages) {
      final role = message['role'] ?? 'unknown';
      final content = message['content'] ?? '';
      final roleLabel = role == 'user' ? 'User' : 'Assistant';
      final timestamp = timestampFormat.format(now);

      buffer.writeln('**$roleLabel** — $timestamp');
      buffer.writeln();
      buffer.writeln(content);
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Export as Markdown: convert, write temp file, share, cleanup.
  ///
  /// Returns [ExportResult.empty] if messages is empty.
  /// Filename pattern: chat_export_<yyyy-MM-dd_HHmmss>.md
  /// Shares with MIME type text/markdown and plain text fallback.
  /// Deletes temp file after share completes.
  /// On file write or share failure: deletes partial file, returns [ExportResult.error].
  Future<ExportResult> exportAsMarkdown(
    List<Map<String, String>> messages,
    BuildContext context,
  ) async {
    if (messages.isEmpty) {
      return ExportResult.empty;
    }

    File? tempFile;

    try {
      final markdown = convertToMarkdown(messages);
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
      final fileName = 'chat_export_$timestamp.md';
      final filePath = '${tempDir.path}/$fileName';

      tempFile = File(filePath);
      await tempFile.writeAsString(markdown);

      final xFile = XFile(filePath, mimeType: 'text/markdown');

      await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          text: markdown,
        ),
      );

      // Cleanup temp file after share completes
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      return ExportResult.success;
    } catch (e) {
      // Cleanup partial file on any failure
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
      return ExportResult.error;
    }
  }

  /// Generate a PDF document from chat messages.
  ///
  /// Returns the PDF as [Uint8List] bytes.
  /// Truncates beyond 1000 messages.
  /// Throws [TimeoutException] if generation exceeds 30 seconds.
  Future<Uint8List> generatePdf(List<Map<String, String>> messages) async {
    return await Future<Uint8List>(() {
      final truncatedMessages = messages.length > 1000
          ? messages.sublist(0, 1000)
          : messages;

      final pdf = pw.Document();
      final timestampFormat = DateFormat.yMd().add_jm();
      final now = DateTime.now();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            final widgets = <pw.Widget>[];

            // Title
            widgets.add(
              pw.Header(
                level: 0,
                child: pw.Text(
                  'AURA Chat Export',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            );

            widgets.add(pw.SizedBox(height: 12));

            // Messages
            for (final message in truncatedMessages) {
              final role = message['role'] ?? 'unknown';
              final content = message['content'] ?? '';
              final roleLabel = role == 'user' ? 'User' : 'Assistant';
              final timestamp = timestampFormat.format(now);

              widgets.add(
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: roleLabel,
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.TextSpan(
                            text: '  —  $timestamp',
                            style: const pw.TextStyle(
                              fontSize: 10,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      content,
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Divider(),
                    pw.SizedBox(height: 8),
                  ],
                ),
              );
            }

            return widgets;
          },
        ),
      );

      return pdf.save();
    }).timeout(const Duration(seconds: 30));
  }

  /// Export as PDF: generate, write temp file, share, cleanup.
  ///
  /// Returns [ExportResult.empty] if messages is empty.
  /// Returns [ExportResult.timeout] if PDF generation exceeds 30 seconds.
  /// Returns [ExportResult.insufficientStorage] on "No space left" errors.
  /// Filename pattern: chat_export_<yyyy-MM-dd_HHmmss>.pdf
  /// Shares with MIME type application/pdf.
  /// Deletes temp file after share completes.
  Future<ExportResult> exportAsPdf(
    List<Map<String, String>> messages,
    BuildContext context,
  ) async {
    if (messages.isEmpty) {
      return ExportResult.empty;
    }

    File? tempFile;

    try {
      final Uint8List pdfBytes = await generatePdf(messages);

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
      final fileName = 'chat_export_$timestamp.pdf';
      final filePath = '${tempDir.path}/$fileName';

      tempFile = File(filePath);
      await tempFile.writeAsBytes(pdfBytes);

      final xFile = XFile(filePath, mimeType: 'application/pdf');

      await SharePlus.instance.share(ShareParams(files: [xFile]));

      // Cleanup temp file after share completes
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      return ExportResult.success;
    } on TimeoutException {
      return ExportResult.timeout;
    } on FileSystemException catch (e) {
      if (e.message.contains('No space left')) {
        return ExportResult.insufficientStorage;
      }
      // Cleanup partial file on failure
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
      return ExportResult.error;
    } catch (e) {
      // Cleanup partial file on any failure
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
      return ExportResult.error;
    }
  }
}
