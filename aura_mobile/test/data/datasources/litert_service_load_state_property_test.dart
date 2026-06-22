import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';

// Feature: multi-engine-ai-models, Property 6: LiteRT load state tracking
//
// "For any model path with a supported LiteRT extension (.task or .litertlm)
//  that the engine loads successfully, the LiteRtService reports
//  isModelLoaded == true; and for any path the engine has not successfully
//  loaded, it reports isModelLoaded == false."
//
// Validates: Requirements 3.3, 3.6
//
// flutter_gemma is mocked (injected via the LiteRtService constructor) so the
// property tests LiteRtService's own load-state bookkeeping, not the native
// engine. glados is not a project dependency; per the design's testing
// strategy this uses an equivalent generator-based approach layered on
// package:test. Each property runs >= 100 generated cases.

const int _iterations = 200;

/// Fake [InferenceModel] handle. loadModel only stores the handle; no members
/// are exercised, so an empty fake is sufficient.
class _FakeInferenceModel extends Fake implements InferenceModel {}

/// Fake [ModelFileManager]: the only call LiteRtService.loadModel makes is the
/// (deprecated) setModelPath, which we accept as a no-op.
class _FakeModelManager extends Fake implements ModelFileManager {
  @override
  // ignore: deprecated_member_use
  Future<void> setModelPath(String path, {String? loraPath}) async {}
}

/// Fake [FlutterGemmaPlugin] whose createModel outcome is controlled per test.
///
/// When [shouldFail] is true the model creation throws (an engine
/// initialization failure); otherwise it returns a fresh fake model.
class _FakeGemma extends Fake implements FlutterGemmaPlugin {
  _FakeGemma({this.shouldFail = false});

  bool shouldFail;
  final _FakeModelManager _manager = _FakeModelManager();

  @override
  ModelFileManager get modelManager => _manager;

  @override
  Future<InferenceModel> createModel({
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.task,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
    int? maxNumImages,
    bool supportImage = false,
    bool supportAudio = false,
  }) async {
    if (shouldFail) {
      throw Exception('simulated LiteRT initialization failure');
    }
    return _FakeInferenceModel();
  }
}

/// Supported LiteRT extensions, exercised in mixed case to confirm the
/// extension match is case-insensitive (production lower-cases the path).
const _supportedExtensions = ['.task', '.litertlm', '.TASK', '.LiteRTLM'];

/// Extensions the LiteRT engine must reject.
const _unsupportedExtensions = ['.gguf', '.bin', '.txt', '.zip', '.model', ''];

const _nameAlphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-';

String _randomSegment(Random rng, int maxLen) {
  final len = 1 + rng.nextInt(maxLen);
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.write(_nameAlphabet[rng.nextInt(_nameAlphabet.length)]);
  }
  return sb.toString();
}

/// Builds a random file path (optionally with directory segments) ending in
/// [ext].
String _randomPath(Random rng, String ext) {
  final sep = rng.nextBool() ? '/' : '\\';
  final dirs = rng.nextInt(3);
  final sb = StringBuffer();
  for (var i = 0; i < dirs; i++) {
    sb.write(_randomSegment(rng, 8));
    sb.write(sep);
  }
  sb.write(_randomSegment(rng, 12));
  sb.write(ext);
  return sb.toString();
}

void main() {
  group('Property 6: LiteRT load state tracking (multi-engine-ai-models)', () {
    // --- Baseline: a freshly constructed service has no model loaded. ---
    test('reports not-loaded before any load', () {
      final service = LiteRtService(gemma: _FakeGemma());
      expect(service.isModelLoaded, isFalse);
    });

    // --- A successful load of a supported-extension path => isModelLoaded
    // becomes (and stays) true. Runs >= 100 generated cases. ---
    test('successful supported-extension load sets isModelLoaded true',
        () async {
      final rng = Random(20240701);
      for (var i = 0; i < _iterations; i++) {
        final ext = _supportedExtensions[rng.nextInt(_supportedExtensions.length)];
        final path = _randomPath(rng, ext);
        final service = LiteRtService(gemma: _FakeGemma(shouldFail: false));

        await service.loadModel(path);

        expect(service.isModelLoaded, isTrue,
            reason: 'after a successful load of "$path", isModelLoaded must '
                'be true');
      }
    });

    // --- A path the engine never successfully loads => isModelLoaded stays
    // false. Two failure modes are generated: engine init failure (supported
    // extension, createModel throws) and unsupported-format rejection. ---
    test('a load that does not succeed leaves isModelLoaded false', () async {
      final rng = Random(13579);
      for (var i = 0; i < _iterations; i++) {
        final initFailure = rng.nextBool();
        final String path;
        final _FakeGemma gemma;
        if (initFailure) {
          // Supported extension, but engine initialization fails.
          final ext =
              _supportedExtensions[rng.nextInt(_supportedExtensions.length)];
          path = _randomPath(rng, ext);
          gemma = _FakeGemma(shouldFail: true);
        } else {
          // Unsupported extension is rejected before any engine work.
          final ext = _unsupportedExtensions[
              rng.nextInt(_unsupportedExtensions.length)];
          path = _randomPath(rng, ext);
          gemma = _FakeGemma(shouldFail: false);
        }
        final service = LiteRtService(gemma: gemma);

        await expectLater(service.loadModel(path), throwsA(anything),
            reason: 'an unsuccessful load of "$path" must raise');
        expect(service.isModelLoaded, isFalse,
            reason: 'after an unsuccessful load of "$path", isModelLoaded '
                'must be false');
      }
    });

    // --- A failed reload after a prior success clears the loaded state:
    // because the engine did not successfully load the new model, the service
    // reports not-loaded. Runs >= 100 generated cases. ---
    test('failed reload after a success reports isModelLoaded false', () async {
      final rng = Random(24680);
      for (var i = 0; i < _iterations; i++) {
        final gemma = _FakeGemma(shouldFail: false);
        final service = LiteRtService(gemma: gemma);

        // First: a successful supported-extension load.
        final okExt =
            _supportedExtensions[rng.nextInt(_supportedExtensions.length)];
        await service.loadModel(_randomPath(rng, okExt));
        expect(service.isModelLoaded, isTrue);

        // Then: a supported-extension load whose engine init fails. The new
        // load did not succeed, so the engine reports not-loaded.
        gemma.shouldFail = true;
        final failExt =
            _supportedExtensions[rng.nextInt(_supportedExtensions.length)];
        await expectLater(
            service.loadModel(_randomPath(rng, failExt)), throwsA(anything));

        expect(service.isModelLoaded, isFalse,
            reason: 'a failed reload means no model is successfully loaded, so '
                'isModelLoaded must be false');
      }
    });
  });
}
