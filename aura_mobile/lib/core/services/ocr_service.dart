import 'dart:io';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';

/// Offline OCR service using Google ML Kit.
/// Extracts text from camera photos, screenshots, and handwritten notes.
class OcrService {
  final ErrorHandlerService _errorHandler = ErrorHandlerService();
  TextRecognizer? _textRecognizer;

  /// Get or create a reusable recognizer instance.
  /// Avoids creating a new native recognizer on every scan.
  TextRecognizer get _recognizer {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _textRecognizer!;
  }

  /// Extract text from an image file.
  /// Returns structured [OcrResult] with full text, blocks, and lines.
  Future<OcrResult> extractText(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        return const OcrResult(
          fullText: '',
          blocks: [],
          imageWidth: 0,
          imageHeight: 0,
        );
      }

      // Validate file size to prevent OOM on low-end devices
      final fileSize = await imageFile.length();
      if (fileSize == 0) {
        _errorHandler.logWarning('OCR: Image file is empty');
        return const OcrResult(
          fullText: '',
          blocks: [],
          imageWidth: 0,
          imageHeight: 0,
        );
      }

      if (fileSize > 20 * 1024 * 1024) {
        _errorHandler.logWarning('OCR: Image too large (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)');
        return const OcrResult(
          fullText: '',
          blocks: [],
          imageWidth: 0,
          imageHeight: 0,
        );
      }

      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _recognizer.processImage(inputImage);

      final blocks = <OcrBlock>[];
      for (final block in recognizedText.blocks) {
        final lines = <OcrLine>[];
        for (final line in block.lines) {
          lines.add(OcrLine(
            text: line.text,
            confidence: line.confidence ?? 0.0,
            boundingBox: line.boundingBox,
          ));
        }
        blocks.add(OcrBlock(
          text: block.text,
          lines: lines,
          boundingBox: block.boundingBox,
        ));
      }

      final result = OcrResult(
        fullText: recognizedText.text,
        blocks: blocks,
        imageWidth: 0,
        imageHeight: 0,
      );

      _errorHandler.logInfo(
        'OCR: Extracted ${result.fullText.length} chars, '
        '${blocks.length} blocks from image',
      );

      return result;
    } on OutOfMemoryError {
      _errorHandler.logWarning('OCR: Out of memory processing image');
      return const OcrResult(
        fullText: '',
        blocks: [],
        imageWidth: 0,
        imageHeight: 0,
      );
    } catch (e) {
      _errorHandler.logWarning('OCR extraction failed: $e');
      // Return empty result instead of rethrowing — prevents crash
      return const OcrResult(
        fullText: '',
        blocks: [],
        imageWidth: 0,
        imageHeight: 0,
      );
    }
  }

  /// Detect if the text looks like handwritten notes (heuristic).
  /// Handwritten text tends to have more irregular line lengths and lower confidence.
  bool looksHandwritten(OcrResult result) {
    if (result.blocks.isEmpty) return false;

    double avgConfidence = 0;
    int lineCount = 0;
    for (final block in result.blocks) {
      for (final line in block.lines) {
        avgConfidence += line.confidence;
        lineCount++;
      }
    }
    if (lineCount == 0) return false;
    avgConfidence /= lineCount;

    // Lower confidence typically means handwritten
    return avgConfidence < 0.85;
  }

  /// Detect if the text looks like a code/error screenshot.
  bool looksLikeCode(String text) {
    final codeIndicators = [
      RegExp(r'(Exception|Error|Stack\s*Trace|at\s+\w+\.\w+)', caseSensitive: false),
      RegExp(r'[{}();]'),
      RegExp(r'(import|class|function|def|var|let|const|return)\s'),
      RegExp(r'(null|undefined|NaN|true|false)\b'),
      RegExp(r'\d+:\d+'),  // line:col format
    ];

    int hits = 0;
    for (final pattern in codeIndicators) {
      if (pattern.hasMatch(text)) hits++;
    }
    return hits >= 2;
  }

  /// Detect if text looks like a math problem/equation.
  bool looksLikeMath(String text) {
    final mathIndicators = [
      RegExp(r'[+\-*/=]'),
      RegExp(r'\b(sin|cos|tan|log|sqrt|sum|integral|dx|dy)\b', caseSensitive: false),
      RegExp(r'\b\d+\s*[+\-*/^=]\s*\d+'),
      RegExp(r'[xy]\s*[=+\-*/^]\s*\d+'),
      RegExp(r'\b(solve|find|calculate|evaluate|simplify|prove)\b', caseSensitive: false),
    ];

    int hits = 0;
    for (final pattern in mathIndicators) {
      if (pattern.hasMatch(text)) hits++;
    }
    return hits >= 2;
  }

  /// Categorize the scanned content for smart routing.
  ScanCategory categorize(OcrResult result) {
    final text = result.fullText;
    if (text.trim().isEmpty) return ScanCategory.empty;
    if (looksLikeCode(text)) return ScanCategory.code;
    if (looksLikeMath(text)) return ScanCategory.math;
    if (looksHandwritten(result)) return ScanCategory.handwrittenNotes;
    return ScanCategory.printedText;
  }

  /// Release native resources. Call when the service is no longer needed.
  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}

// ── Data Classes ──────────────────────────────────────────────────────────────

class OcrResult {
  final String fullText;
  final List<OcrBlock> blocks;
  final int imageWidth;
  final int imageHeight;

  const OcrResult({
    required this.fullText,
    required this.blocks,
    required this.imageWidth,
    required this.imageHeight,
  });

  bool get isEmpty => fullText.trim().isEmpty;
  int get blockCount => blocks.length;
  int get lineCount => blocks.fold(0, (sum, b) => sum + b.lines.length);
}

class OcrBlock {
  final String text;
  final List<OcrLine> lines;
  final Rect? boundingBox;

  const OcrBlock({
    required this.text,
    required this.lines,
    this.boundingBox,
  });
}

class OcrLine {
  final String text;
  final double confidence;
  final Rect? boundingBox;

  const OcrLine({
    required this.text,
    required this.confidence,
    this.boundingBox,
  });
}

enum ScanCategory {
  empty,
  printedText,
  handwrittenNotes,
  code,
  math,
}
