import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/data/datasources/model_manager.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Feature: multi-engine-ai-models, Property 19: Download destination matches
// catalog file name
//
// "For any litert model, starting a download stores the file at a destination
//  whose file name equals the file name defined for that model in the
//  Model_Catalog."
//
// Validates: Requirements 7.1
//
// The download pipeline resolves the destination path for a model through
// ModelManager.getModelPath, which builds the path from the application
// documents directory plus the catalog file name. This is the destination
// passed to RunAnywhere.downloadModel. The property asserts that, for any
// litert catalog model, the resolved destination's terminal path segment
// (its file name) equals that model's catalog fileName exactly. Path
// resolution is engine-agnostic, so the same guarantee holds for gguf models;
// both are checked to confirm the mechanism is not litert-specific.
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. The
// random model-selection property runs >= 100 generated cases.

const int _iterations = 150;

/// Mock path provider so the documents directory points at the system temp
/// folder rather than a real (and possibly synced) application directory.
class _MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

/// Returns the final path segment (file name) of [path], independent of which
/// platform separator the path uses. ModelManager builds paths with
/// `Platform.pathSeparator`, but we normalize both separators so the assertion
/// is robust across platforms.
String _fileNameOf(String path) {
  final lastSlash = path.lastIndexOf('/');
  final lastBackslash = path.lastIndexOf('\\');
  final cut = max(lastSlash, lastBackslash);
  return cut < 0 ? path : path.substring(cut + 1);
}

void main() {
  late ModelManager modelManager;

  setUpAll(() {
    PathProviderPlatform.instance = _MockPathProviderPlatform();
  });

  setUp(() {
    modelManager = ModelManager();
  });

  group('Property 19: Download destination matches catalog file name '
      '(multi-engine-ai-models)', () {
    // --- Core property over every litert catalog model: the download
    // destination's file name equals the catalog fileName exactly. ---
    test('every litert model resolves a destination ending in its catalog '
        'file name', () async {
      final litertModels =
          modelCatalog.where((m) => m.engine == AIEngine.litert).toList();

      // Guard: the catalog must actually contain litert models, otherwise the
      // property would be vacuously true and hide a regression.
      expect(litertModels, isNotEmpty,
          reason: 'catalog must contain at least one litert model');

      for (final model in litertModels) {
        final destination = await modelManager.getModelPath(model.id);

        expect(_fileNameOf(destination), equals(model.fileName),
            reason: 'litert model "${model.id}" destination file name must '
                'equal its catalog fileName "${model.fileName}"');
        // The destination must be an absolute path under a directory, i.e.
        // the file name is a terminal segment, not the whole path.
        expect(destination.endsWith(model.fileName), isTrue,
            reason: 'destination "$destination" must end with the catalog '
                'fileName "${model.fileName}"');
      }
    });

    // --- Generated property: >= 100 randomly selected litert models always
    // resolve a destination whose file name is the catalog fileName. ---
    test('randomly selected litert models always match their catalog file '
        'name', () async {
      final litertModels =
          modelCatalog.where((m) => m.engine == AIEngine.litert).toList();
      expect(litertModels, isNotEmpty);

      final rng = Random(70123);
      for (var i = 0; i < _iterations; i++) {
        final model = litertModels[rng.nextInt(litertModels.length)];
        final destination = await modelManager.getModelPath(model.id);

        expect(_fileNameOf(destination), equals(model.fileName),
            reason: 'iteration $i: litert model "${model.id}" destination '
                'file name must equal "${model.fileName}"');
      }
    });

    // --- Engine-agnostic confirmation: gguf models resolve the same way, so
    // the destination/file-name guarantee is not litert-specific. ---
    test('destination file name matches catalog for gguf models too '
        '(engine-agnostic)', () async {
      final ggufModels =
          modelCatalog.where((m) => m.engine == AIEngine.gguf).toList();
      expect(ggufModels, isNotEmpty);

      for (final model in ggufModels) {
        final destination = await modelManager.getModelPath(model.id);
        expect(_fileNameOf(destination), equals(model.fileName),
            reason: 'gguf model "${model.id}" destination file name must '
                'equal its catalog fileName "${model.fileName}"');
      }
    });

    // --- Determinism: the resolved destination for a given model is stable
    // across independent manager instances, so a download started at one time
    // targets the same file name a download started later would. ---
    test('destination file name is deterministic across manager instances',
        () async {
      final rng = Random(424242);
      final litertModels =
          modelCatalog.where((m) => m.engine == AIEngine.litert).toList();

      for (var i = 0; i < 50; i++) {
        final model = litertModels[rng.nextInt(litertModels.length)];
        final first = await ModelManager().getModelPath(model.id);
        final second = await ModelManager().getModelPath(model.id);

        expect(_fileNameOf(first), equals(model.fileName));
        expect(_fileNameOf(second), equals(_fileNameOf(first)),
            reason: 'destination file name for "${model.id}" must be stable '
                'across manager instances');
      }
    });
  });
}
