import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/data/datasources/model_manager.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Mock PathProviderPlatform for testing
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

// The catalog is now 100% LiteRT (.litertlm). Tests use gemma3-1b, the smallest
// entry, whose file is `gemma3-1b-it-int4.litertlm`.
const _modelId = 'gemma3-1b';
const _modelFileName = 'gemma3-1b-it-int4.litertlm';
const _modelName = 'Gemma 3 1B';

// LITERTLM container magic ('LITERTLM').
const _litertlmMagic = [0x4C, 0x49, 0x54, 0x45, 0x52, 0x54, 0x4C, 0x4D];

void main() {
  late ModelManager modelManager;
  late Directory testDir;

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
  });

  setUp(() async {
    modelManager = ModelManager();
    testDir = Directory.systemTemp.createTempSync('model_manager_test_');
  });

  tearDown(() async {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  // Creates a file at the model's real path, of its expected size, with the
  // given header bytes — without allocating the whole buffer in memory.
  Future<File> createSizedFile(String modelId, List<int> header) async {
    final path = await modelManager.getModelPath(modelId);
    final model = modelManager.getModelById(modelId)!;
    final file = File(path);
    await file.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    await raf.writeFrom(header);
    await raf.setPosition(model.sizeBytes - 1);
    await raf.writeByte(0);
    await raf.close();
    return file;
  }

  group('ModelManager - File operations', () {
    test('getDownloadedModels returns empty list when no models exist', () async {
      final models = await modelManager.getDownloadedModels();
      expect(models, isEmpty);
    });

    test('getDownloadedModels returns a list', () async {
      final models = await modelManager.getDownloadedModels();
      expect(models, isA<List<String>>());
    });

    test('getModelPath returns the correct path for a model', () async {
      final path = await modelManager.getModelPath(_modelId);
      expect(path, contains(_modelFileName));
      expect(path, contains(Platform.pathSeparator));
    });

    test('getModelPath throws ModelException for unknown model', () async {
      expect(
        () => modelManager.getModelPath('unknown-model'),
        throwsA(isA<ModelException>()),
      );
    });

    test('getModelById returns ModelInfo for a valid ID', () {
      final model = modelManager.getModelById(_modelId);
      expect(model, isNotNull);
      expect(model!.id, _modelId);
      expect(model.name, _modelName);
    });

    test('getModelById returns null for an invalid ID', () {
      expect(modelManager.getModelById('invalid-id'), isNull);
    });
  });

  group('ModelManager - Disk space validation', () {
    test('getAvailableDiskSpace returns a non-negative value', () async {
      final space = await modelManager.getAvailableDiskSpace();
      expect(space, greaterThanOrEqualTo(0));
    });

    test('validateDiskSpace either passes or reports insufficient space', () async {
      try {
        await modelManager.validateDiskSpace(_modelId);
        expect(true, true);
      } on ModelException catch (e) {
        expect(e.errorCode, 'MODEL_INSUFFICIENT_SPACE');
      }
    });

    test('validateDiskSpace throws ModelException for unknown model', () async {
      expect(
        () => modelManager.validateDiskSpace('unknown-model'),
        throwsA(isA<ModelException>()),
      );
    });
  });

  group('ModelManager - Model validation', () {
    test('isModelDownloaded returns false for a non-existent model', () async {
      expect(await modelManager.isModelDownloaded(_modelId), false);
    });

    test('isModelDownloaded returns false for a file of the wrong size', () async {
      final path = await modelManager.getModelPath(_modelId);
      final file = File(path);
      await file.create(recursive: true);
      await file.writeAsBytes(_litertlmMagic); // valid header, tiny file

      expect(await modelManager.isModelDownloaded(_modelId), false);
      await file.delete();
    });

    test('verifyAndCleanupModel deletes a corrupt (too-small) file', () async {
      final path = await modelManager.getModelPath(_modelId);
      final file = File(path);
      await file.create(recursive: true);
      await file.writeAsBytes([..._litertlmMagic, 0x00]);

      final result = await modelManager.verifyAndCleanupModel(_modelId);
      expect(result, false);
      expect(await file.exists(), false);
    });

    test('verifyAndCleanupModel returns false for a non-existent model', () async {
      expect(await modelManager.verifyAndCleanupModel(_modelId), false);
    });
  });

  group('ModelManager - LiteRT format validation', () {
    test('accepts a valid .litertlm container of the right size', () async {
      final file = await createSizedFile(_modelId, _litertlmMagic);
      expect(await modelManager.isModelDownloaded(_modelId), true);
      await file.delete();
    });

    test('rejects a .litertlm file with an invalid header', () async {
      final file = await createSizedFile(_modelId, [0x00, 0x00, 0x00, 0x00]);
      expect(await modelManager.isModelDownloaded(_modelId), false);
      await file.delete();
    });

    test('treats a too-small .litertlm file as not downloaded (size gate)', () async {
      final path = await modelManager.getModelPath(_modelId);
      final file = File(path);
      await file.create(recursive: true);
      await file.writeAsBytes(_litertlmMagic);
      expect(await modelManager.isModelDownloaded(_modelId), false);
      await file.delete();
    });
  });

  group('ModelManager - Model deletion', () {
    test('deleteModel removes an existing model file', () async {
      final path = await modelManager.getModelPath(_modelId);
      final file = File(path);
      await file.create(recursive: true);
      await file.writeAsString('test');

      await modelManager.deleteModel(_modelId);
      expect(await file.exists(), false);
    });

    test('deleteModel throws for a non-existent model file', () async {
      expect(
        () => modelManager.deleteModel(_modelId),
        throwsA(isA<ModelException>()),
      );
    });

    test('deleteModel throws for an unknown model ID', () async {
      expect(
        () => modelManager.deleteModel('unknown-model'),
        throwsA(isA<ModelException>()),
      );
    });
  });

  group('ModelManager - Model size operations', () {
    test('getModelSize returns 0 for a non-existent model', () async {
      expect(await modelManager.getModelSize(_modelId), 0);
    });

    test('getModelSize returns the correct size for an existing file', () async {
      final path = await modelManager.getModelPath(_modelId);
      final file = File(path);
      await file.create(recursive: true);
      await file.writeAsBytes(List.filled(1024, 0));

      expect(await modelManager.getModelSize(_modelId), 1024);
      await file.delete();
    });

    test('getTotalStorageUsed returns 0 when no models are downloaded', () async {
      expect(await modelManager.getTotalStorageUsed(), 0);
    });
  });
}
