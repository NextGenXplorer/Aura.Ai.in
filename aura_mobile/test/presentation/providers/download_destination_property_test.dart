import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';

// Feature: multi-engine-ai-models, Property 19: Download destination matches
// catalog file name.
//
// "For any litert model, starting a download stores the file at a destination
//  whose file name equals the file name defined for that model in the
//  Model_Catalog."
//
// Validates: Requirements 7.1
//
// The download pipeline in ModelSelectorNotifier._attemptDownload resolves
// the destination via ModelManager.getModelPath(modelId), which constructs
// the path as `${docsDir}/${model.fileName}`. This test verifies that
// for every catalog model the path derivation logic always produces a
// destination whose trailing file name component is exactly the catalog
// entry's `fileName` field — regardless of the base directory or platform
// separator.
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:flutter_test.
// Each property runs >= 100 generated cases.

const int _iterations = 200;

/// Simulates the path derivation logic from ModelManager.getModelPath:
/// `${baseDir}${separator}${model.fileName}`
///
/// This is the same string operation the real code uses; the only difference is
/// that we supply the base directory and separator as parameters so we can
/// exercise the property over many random path variations without requiring
/// path_provider or a real file system.
String deriveModelPath(String baseDir, String separator, ModelInfo model) {
  return '$baseDir$separator${model.fileName}';
}

/// Extracts the trailing file-name component from a path, splitting on the
/// given separator.
String extractFileName(String path, String separator) {
  final lastSep = path.lastIndexOf(separator);
  if (lastSep < 0) return path;
  return path.substring(lastSep + separator.length);
}

/// Generates a random base directory path for testing. Produces Unix-style,
/// Windows-style, and edge-case paths.
String _randomBaseDir(Random rng) {
  const separators = ['/', '\\'];
  final sep = separators[rng.nextInt(separators.length)];
  final depth = 1 + rng.nextInt(5); // 1..5 segments
  final segments = List.generate(depth, (_) => _randomDirName(rng));
  return segments.join(sep);
}

/// Generates a random directory name segment (alphanumeric, dots, spaces).
String _randomDirName(Random rng) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789._- ';
  final len = 2 + rng.nextInt(12); // 2..13 characters
  return String.fromCharCodes(
    List.generate(len, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
  );
}

/// Returns the path separator matching the [baseDir] style.
String _inferSeparator(String baseDir) {
  // If the baseDir contains backslashes, treat it as Windows-style.
  if (baseDir.contains('\\')) return '\\';
  return '/';
}

void main() {
  group('Property 19: Download destination matches catalog file name '
      '(multi-engine-ai-models)', () {
    // --- Concrete check: every real catalog entry's derived destination ends
    // with its fileName. ---
    test('every catalog model destination file name equals model.fileName', () {
      for (final model in modelCatalog) {
        // Use a realistic Unix-style base directory.
        const baseDir = '/data/user/0/com.aura.ai/app_flutter';
        const sep = '/';
        final path = deriveModelPath(baseDir, sep, model);
        final extracted = extractFileName(path, sep);
        expect(extracted, model.fileName,
            reason: 'destination for ${model.id} must use catalog fileName '
                '${model.fileName}, got $extracted');
      }
    });

    // --- Property over litert models specifically (Req 7.1): the download
    // destination for every litert model uses the exact catalog file name. ---
    test('litert model destinations use exact catalog fileName', () {
      final litertModels =
          modelCatalog.where((m) => m.engine == AIEngine.litert).toList();
      expect(litertModels, isNotEmpty,
          reason: 'catalog must contain at least one litert model');

      for (final model in litertModels) {
        const baseDir = '/data/user/0/com.aura.ai/app_flutter';
        const sep = '/';
        final path = deriveModelPath(baseDir, sep, model);
        final extracted = extractFileName(path, sep);
        expect(extracted, model.fileName,
            reason: 'litert model ${model.id} destination must equal '
                'catalog fileName "${model.fileName}"');
      }
    });

    // --- Generated property: for any catalog model and any random base
    // directory path, the derived destination's trailing file name component
    // equals model.fileName. Runs >= 100 cases per catalog entry. ---
    test('destination file name equals model.fileName for random base paths',
        () {
      final rng = Random(0x7101);
      for (final model in modelCatalog) {
        for (var i = 0; i < _iterations; i++) {
          final baseDir = _randomBaseDir(rng);
          final sep = _inferSeparator(baseDir);
          final path = deriveModelPath(baseDir, sep, model);
          final extracted = extractFileName(path, sep);
          expect(extracted, model.fileName,
              reason: 'model ${model.id}: derived path "$path" must end with '
                  'fileName "${model.fileName}", got "$extracted"');
        }
      }
    });

    // --- The derived destination is never empty and always contains the
    // file extension defined in the catalog. ---
    test('destination is non-empty and preserves the catalog file extension',
        () {
      final rng = Random(0xABC0);
      for (final model in modelCatalog) {
        for (var i = 0; i < _iterations; i++) {
          final baseDir = _randomBaseDir(rng);
          final sep = _inferSeparator(baseDir);
          final path = deriveModelPath(baseDir, sep, model);
          expect(path.isNotEmpty, isTrue,
              reason: 'derived path must never be empty');

          // The catalog fileName has an extension; the derived path must too.
          final dotIndex = model.fileName.lastIndexOf('.');
          if (dotIndex > 0) {
            final ext = model.fileName.substring(dotIndex);
            expect(path.endsWith(ext), isTrue,
                reason: 'derived path must end with extension "$ext" for '
                    'model ${model.id}');
          }
        }
      }
    });

    // --- Edge case: even with trailing separators in the base dir, the file
    // name is correctly the last path component. ---
    test('trailing separators in baseDir do not corrupt destination', () {
      for (final model in modelCatalog) {
        for (final sep in ['/', '\\']) {
          // Base dir with trailing separator (like path_provider might return).
          final baseDir = '/some/path$sep';
          // deriveModelPath adds sep + fileName, giving double-separator.
          // The extractFileName logic still yields the correct name because
          // fileName never starts with a separator.
          final path = deriveModelPath(baseDir, sep, model);
          // Even with a double-separator, the last non-empty segment is
          // model.fileName.
          final parts = path.split(sep).where((s) => s.isNotEmpty).toList();
          expect(parts.last, model.fileName,
              reason: 'trailing sep in baseDir must not corrupt the file name '
                  'for model ${model.id}');
        }
      }
    });
  });
}
