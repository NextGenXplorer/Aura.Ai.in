import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/data/datasources/model_manager.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Feature: multi-engine-ai-models, Property 22: Delete reduces reported storage
// by file size.
//
// "For any set of downloaded models, deleting one model removes its file and
//  reduces the reported total storage used by exactly that model's file size."
//
// Validates: Requirements 7.6
//
// The mechanism under test spans three ModelManager methods:
//   - getTotalStorageUsed() sums getModelSize() over every catalog model that
//     isModelDownloaded() recognizes (present + correct size + valid header).
//   - getModelSize(id) reports the on-disk length of a present model file.
//   - deleteModel(id) removes the file from disk.
// After a delete, the deleted model is no longer recognized as downloaded, so
// the reported total must drop by exactly the size that model contributed.
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. The
// generated property below runs >= 100 cases.
//
// Disk safety: catalog files are hundreds of MB to multiple GB. Real files are
// written sparsely (header bytes at offset 0, then `truncate` to the catalog
// size) exactly as the Property 23 test does, so they cost almost no physical
// bytes. The generated property additionally draws its "downloaded set" from
// the two smallest catalog models (one gguf .task-less, one litert .task) so
// peak simultaneous logical size stays under ~1 GB.

const int _iterations = 120;

/// The two smallest catalog models, one per engine, used to bound the peak
/// simultaneous file size of the generated property while still exercising both
/// engine code paths (gguf magic-byte vs litert .task header).
const List<String> _smallPoolIds = <String>['qwen2.5-0.5b', 'gemma3-1b'];

/// Mock path provider so the documents directory points at the system temp
/// folder (outside any synced location).
class _MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

/// Returns the correct format-header bytes for [model] so a written file passes
/// the engine-specific header validation in ModelManager.isModelDownloaded.
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

/// Writes a valid, full-size model file at the catalog path for [model]. The
/// body beyond the header is sparse (created with `truncate`) so we do not
/// allocate the full bytes physically.
Future<File> _writeValidModelFile(ModelManager manager, ModelInfo model) async {
  final path = await manager.getModelPath(model.id);
  final file = File(path);
  await file.create(recursive: true);
  final raf = await file.open(mode: FileMode.write);
  try {
    await raf.writeFrom(_validHeaderFor(model));
    // Extend to the expected size so the >= 99% size gate passes; the header at
    // offset 0 is preserved and the remainder reads as zeros.
    await raf.truncate(model.sizeBytes);
  } finally {
    await raf.close();
  }
  return file;
}

Future<void> _deleteIfExists(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

/// Removes any catalog files that might linger in the docs dir so each case
/// starts from a clean slate and the global total is attributable to this case.
Future<void> _purgeAllCatalogFiles(ModelManager manager) async {
  for (final model in modelCatalog) {
    await _deleteIfExists(await manager.getModelPath(model.id));
  }
}

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _MockPathProviderPlatform();
  });

  late ModelManager manager;

  setUp(() async {
    manager = ModelManager();
    await _purgeAllCatalogFiles(manager);
  });

  tearDown(() async {
    await _purgeAllCatalogFiles(manager);
  });

  group('Property 22: Delete reduces reported storage by file size '
      '(multi-engine-ai-models)', () {
    // --- Core generated property: for a randomly chosen non-empty set of
    // downloaded models, deleting one member removes its file and reduces the
    // reported total by exactly that model's file size; the remaining members'
    // contributions are untouched. Runs >= 100 generated cases. ---
    test('deleting one downloaded model reduces total storage by exactly its '
        'file size', () async {
      final rng = Random(0x57064A6E);
      final pool = _smallPoolIds
          .map((id) => modelCatalog.firstWhere((m) => m.id == id))
          .toList();

      for (var i = 0; i < _iterations; i++) {
        // Generate a non-empty subset of the small pool.
        final subset = <ModelInfo>[];
        for (final model in pool) {
          if (rng.nextBool()) subset.add(model);
        }
        if (subset.isEmpty) {
          subset.add(pool[rng.nextInt(pool.length)]);
        }

        // Write every model in the subset as a valid, full-size file.
        for (final model in subset) {
          await _writeValidModelFile(manager, model);
        }

        try {
          final totalBefore = await manager.getTotalStorageUsed();

          // Pick one member to delete and record the size it contributes.
          final victim = subset[rng.nextInt(subset.length)];
          final victimSize = await manager.getModelSize(victim.id);

          // Sanity: a present, valid file reports its full catalog size.
          expect(victimSize, equals(victim.sizeBytes),
              reason: 'getModelSize for present "${victim.id}" should equal '
                  'its catalog size');

          await manager.deleteModel(victim.id);

          final totalAfter = await manager.getTotalStorageUsed();

          // The headline property: total drops by exactly the victim's size.
          expect(totalBefore - totalAfter, equals(victimSize),
              reason: 'deleting "${victim.id}" must reduce reported total by '
                  'exactly its file size ($victimSize bytes); '
                  'before=$totalBefore after=$totalAfter '
                  'set=${subset.map((m) => m.id).toList()}');

          // The file is gone and is no longer recognized as downloaded.
          expect(await File(await manager.getModelPath(victim.id)).exists(),
              isFalse,
              reason: 'deleteModel must remove the file for "${victim.id}"');
          expect(await manager.isModelDownloaded(victim.id), isFalse,
              reason: 'deleted "${victim.id}" must not be recognized as '
                  'downloaded');

          // The survivors are unaffected: the remaining total equals the sum of
          // the other members' sizes.
          final survivors = subset.where((m) => m.id != victim.id);
          var expectedRemaining = 0;
          for (final m in survivors) {
            expectedRemaining += m.sizeBytes;
          }
          expect(totalAfter, equals(expectedRemaining),
              reason: 'remaining total must equal the sum of the survivors '
                  '${survivors.map((m) => m.id).toList()}');
        } finally {
          // Clean every file written this iteration before the next case.
          for (final model in subset) {
            await _deleteIfExists(await manager.getModelPath(model.id));
          }
        }
      }
    });

    // --- Example covering the .litertlm container type (not in the small pool)
    // alongside other engines, deleting it and checking the exact delta. Uses a
    // single sparse multi-GB file at a time, as the Property 23 test does. ---
    test('deleting a .litertlm model reduces total by its size while other '
        'engines remain counted', () async {
      final gguf = modelCatalog.firstWhere((m) => m.id == 'qwen2.5-0.5b');
      final task = modelCatalog.firstWhere((m) => m.id == 'gemma3-1b');
      final litertlm = modelCatalog.firstWhere((m) => m.id == 'gemma4-e2b');

      await _writeValidModelFile(manager, gguf);
      await _writeValidModelFile(manager, task);
      await _writeValidModelFile(manager, litertlm);

      final totalBefore = await manager.getTotalStorageUsed();
      expect(totalBefore,
          equals(gguf.sizeBytes + task.sizeBytes + litertlm.sizeBytes));

      final victimSize = await manager.getModelSize(litertlm.id);
      await manager.deleteModel(litertlm.id);
      final totalAfter = await manager.getTotalStorageUsed();

      expect(totalBefore - totalAfter, equals(victimSize));
      expect(totalAfter, equals(gguf.sizeBytes + task.sizeBytes));
      expect(await manager.isModelDownloaded(litertlm.id), isFalse);
      expect(await manager.isModelDownloaded(gguf.id), isTrue);
      expect(await manager.isModelDownloaded(task.id), isTrue);
    });

    // --- Deleting the only downloaded model drops the total back to zero. ---
    test('deleting the sole downloaded model returns reported total to zero',
        () async {
      final model = modelCatalog.firstWhere((m) => m.id == 'qwen2.5-0.5b');
      await _writeValidModelFile(manager, model);

      final before = await manager.getTotalStorageUsed();
      final size = await manager.getModelSize(model.id);
      expect(before, equals(size));

      await manager.deleteModel(model.id);

      final after = await manager.getTotalStorageUsed();
      expect(before - after, equals(size));
      expect(after, equals(0));
    });
  });
}
