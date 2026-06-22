import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/data/datasources/model_manager.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Feature: multi-engine-ai-models, Property 23: Download recognition by file presence
//
// "For any catalog model (gguf or litert) whose file is present on device
//  under the file name defined for that model, the system recognizes the model
//  as downloaded after an application restart without requiring re-download."
//
// Validates: Requirements 2.4, 7.7
//
// Recognition is engine-agnostic and file-name based: ModelManager.getModelPath
// resolves purely from the catalog file name (no instance/in-memory state), and
// ModelManager.isModelDownloaded checks the on-disk file (presence + size +
// format header). An "application restart" is simulated by constructing a fresh
// ModelManager and verifying it recognizes a file written by a prior instance,
// without any re-download.
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. The
// random model-selection property runs >= 100 generated cases.

const int _iterations = 150;

/// Mock path provider so the documents directory points at the system temp
/// folder (outside any synced location) for both ModelManager instances.
class _MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

/// Returns the correct format-header bytes for [model] so that a written file
/// passes the engine-specific header validation in ModelManager.
List<int> _validHeaderFor(ModelInfo model) {
  switch (model.engine) {
    case AIEngine.gguf:
      // 'GGUF' magic (0x46554747 little-endian) => bytes G G U F.
      return const [0x47, 0x47, 0x55, 0x46];
    case AIEngine.litert:
      final lower = model.fileName.toLowerCase();
      if (lower.endsWith('.task')) {
        // ZIP local-file-header signature 'PK\x03\x04'.
        return const [0x50, 0x4B, 0x03, 0x04];
      }
      // '.litertlm' => ASCII magic 'LITERTLM'.
      return const [0x4C, 0x49, 0x54, 0x45, 0x52, 0x54, 0x4C, 0x4D];
  }
}

/// Writes a valid, full-size model file at the catalog path for [model] using
/// the manager's own path resolution. The body beyond the header is sparse
/// (created with `truncate`) so we do not allocate gigabytes of real bytes.
Future<File> _writeValidModelFile(ModelManager manager, ModelInfo model) async {
  final path = await manager.getModelPath(model.id);
  final file = File(path);
  await file.create(recursive: true);
  final raf = await file.open(mode: FileMode.write);
  try {
    await raf.writeFrom(_validHeaderFor(model));
    // Extend to the expected size so the >= 99% size gate passes; the header
    // written at offset 0 is preserved, the remainder reads as zeros.
    await raf.truncate(model.sizeBytes);
  } finally {
    await raf.close();
  }
  return file;
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _MockPathProviderPlatform();
  });

  group('Property 23: Download recognition by file presence '
      '(multi-engine-ai-models)', () {
    // --- Core property: a file present under the catalog file name is
    // recognized as downloaded by a freshly constructed manager (restart),
    // with no re-download, for every catalog model and both engines. ---
    test('a present, valid file is recognized after restart for every '
        'catalog model', () async {
      for (final model in modelCatalog) {
        final writer = ModelManager();
        final file = await _writeValidModelFile(writer, model);
        try {
          // Simulate an application restart: a brand-new manager with no
          // in-memory state must recognize the model purely from the file.
          final afterRestart = ModelManager();
          final recognized = await afterRestart.isModelDownloaded(model.id);
          expect(recognized, isTrue,
              reason: 'model "${model.id}" (${model.engine.name}, '
                  '${model.fileName}) should be recognized as downloaded '
                  'after restart when its file is present');
        } finally {
          await _deleteIfExists(file);
        }
      }
    });

    // --- The recognized file lives at the catalog file name; removing it
    // makes a fresh manager report "not downloaded" (no phantom recognition). ---
    test('absence of the catalog file means not-downloaded after restart for '
        'every catalog model', () async {
      for (final model in modelCatalog) {
        // Ensure no leftover file from a prior run.
        await _deleteIfExists(File(await ModelManager().getModelPath(model.id)));

        final afterRestart = ModelManager();
        final recognized = await afterRestart.isModelDownloaded(model.id);
        expect(recognized, isFalse,
            reason: 'model "${model.id}" must not be recognized when its '
                'file is absent');
      }
    });

    // --- File-name based, engine-agnostic, restart-invariant path resolution:
    // getModelPath depends only on the catalog file name, so two independent
    // managers (before/after restart) always resolve the identical path. This
    // is the mechanism that lets a previously downloaded file be re-recognized
    // without re-download. Runs >= 100 generated cases. ---
    test('getModelPath is deterministic across instances and file-name based',
        () async {
      final rng = Random(20240611);
      for (var i = 0; i < _iterations; i++) {
        final model = modelCatalog[rng.nextInt(modelCatalog.length)];

        final before = await ModelManager().getModelPath(model.id);
        final afterRestart = await ModelManager().getModelPath(model.id);

        expect(afterRestart, equals(before),
            reason: 'path for "${model.id}" must be stable across restarts');
        expect(before.endsWith(model.fileName), isTrue,
            reason: 'path for "${model.id}" must end with the catalog file '
                'name "${model.fileName}"');
        // Engine-agnostic: gguf and litert resolve through the same logic.
        expect(before, contains(Platform.pathSeparator));
      }
    });

    // --- Generated round-trip over random model selection: write -> recognize
    // (fresh manager) -> delete -> not-recognized (fresh manager). Each
    // iteration writes exactly one file and deletes it before the next, so peak
    // disk use is a single model file. ---
    test('present/absent recognition round-trips for random catalog models',
        () async {
      final rng = Random(31337);
      // Bound the heavy file-writing portion while still covering both engines
      // and all container types across the catalog.
      const roundTrips = 24;
      for (var i = 0; i < roundTrips; i++) {
        final model = modelCatalog[rng.nextInt(modelCatalog.length)];
        final writer = ModelManager();
        final file = await _writeValidModelFile(writer, model);
        try {
          expect(await ModelManager().isModelDownloaded(model.id), isTrue,
              reason: 'present file for "${model.id}" should be recognized');
        } finally {
          await _deleteIfExists(file);
        }
        // After deletion, a fresh manager must no longer recognize it.
        expect(await ModelManager().isModelDownloaded(model.id), isFalse,
            reason: 'removed file for "${model.id}" must not be recognized');
      }
    });
  });
}
