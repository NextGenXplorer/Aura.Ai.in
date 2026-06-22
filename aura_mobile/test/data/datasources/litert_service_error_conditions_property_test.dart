import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// Feature: multi-engine-ai-models, Property 9: LiteRT error conditions
//
// "For any LiteRT load attempt where initialization or a supported-format load
//  fails, the service raises an error and reports isModelLoaded == false; for
//  any path with an unsupported extension, the service raises an
//  unsupported-format error and leaves any previously loaded model loaded; and
//  for any chat call while no LiteRT model is loaded, the service raises a
//  'no model loaded' error."
//
// Validates: Requirements 3.7, 3.8, 3.9, 3.10
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. Each
// property runs >= 100 generated cases. The external `flutter_gemma` engine is
// replaced with controllable fakes so the property tests *our* error-handling
// logic (state transitions + exception surface) cheaply and deterministically.

const int _iterations = 200;

// ---------------------------------------------------------------------------
// Controllable fakes for the flutter_gemma surface LiteRtService touches.
// ---------------------------------------------------------------------------

/// A fake [InferenceModelSession] — never exercised by these error paths but
/// required as a return type for a fully-loaded fake model.
class _FakeSession implements InferenceModelSession {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

/// A fake [InferenceModel]. Only used as a non-null sentinel stored by
/// [LiteRtService] after a successful load, so `isModelLoaded` reads true.
class _FakeInferenceModel implements InferenceModel {
  @override
  Future<InferenceModelSession> createSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality,
    bool? enableAudioModality,
  }) async =>
      _FakeSession();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

/// A fake [ModelFileManager] whose `setModelPath` can be made to throw, with a
/// call counter so the test can assert the engine is never touched on an
/// unsupported-format rejection.
class _FakeModelManager implements ModelFileManager {
  Object? setModelPathError;
  int setModelPathCalls = 0;

  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {
    setModelPathCalls++;
    final err = setModelPathError;
    if (err != null) throw err;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

/// A fake [FlutterGemmaPlugin] whose `createModel` can succeed, throw, or hang
/// forever (to exercise the 30-second init timeout).
class _FakeGemma implements FlutterGemmaPlugin {
  final _FakeModelManager fakeManager;
  final InferenceModel modelToReturn;

  /// When non-null, `createModel` completes with this error.
  Object? createModelError;

  /// When true, `createModel` returns a future that never completes (so the
  /// 30-second timeout in [LiteRtService.loadModel] is what fails the load).
  bool createModelHangs = false;

  int createModelCalls = 0;

  _FakeGemma(this.fakeManager, this.modelToReturn);

  @override
  ModelFileManager get modelManager => fakeManager;

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
  }) {
    createModelCalls++;
    if (createModelHangs) {
      return Completer<InferenceModel>().future; // never completes
    }
    final err = createModelError;
    if (err != null) return Future<InferenceModel>.error(err);
    return Future<InferenceModel>.value(modelToReturn);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

// ---------------------------------------------------------------------------
// Generators.
// ---------------------------------------------------------------------------

const _letters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// Random run of letters only (never contains a dot or path separator), so the
/// extension we append is the only extension the parser can find.
String _word(Random rng, int maxLen) {
  final len = 1 + rng.nextInt(maxLen);
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.write(_letters[rng.nextInt(_letters.length)]);
  }
  return sb.toString();
}

/// Optional directory prefix using a random separator, exercising the path
/// handling in the extension parser.
String _dirPrefix(Random rng) {
  if (rng.nextBool()) return '';
  final sep = rng.nextBool() ? '/' : '\\';
  final depth = 1 + rng.nextInt(3);
  return [for (var i = 0; i < depth; i++) _word(rng, 8)].join(sep) + sep;
}

/// Randomly varies the case of [s] (the supported extensions are matched
/// case-insensitively).
String _randomCase(Random rng, String s) {
  final sb = StringBuffer();
  for (final ch in s.split('')) {
    sb.write(rng.nextBool() ? ch.toUpperCase() : ch.toLowerCase());
  }
  return sb.toString();
}

const _supportedExts = ['.task', '.litertlm'];

/// Builds a random path whose extension IS a supported LiteRT extension.
String _supportedPath(Random rng) {
  final ext = _randomCase(rng, _supportedExts[rng.nextInt(_supportedExts.length)]);
  return '${_dirPrefix(rng)}${_word(rng, 16)}$ext';
}

/// Curated extensions that are NOT supported (none normalize to .task /
/// .litertlm). The empty entry yields a name with no extension at all.
const _unsupportedExts = [
  '.gguf',
  '.bin',
  '.tflite',
  '.txt',
  '.zip',
  '.json',
  '.litert',
  '.tas',
  '.taskx',
  '.lm',
  '.model',
  '', // no extension
];

/// Builds a random path whose extension is NOT a supported LiteRT extension.
String _unsupportedPath(Random rng) {
  final ext = _randomCase(rng, _unsupportedExts[rng.nextInt(_unsupportedExts.length)]);
  return '${_dirPrefix(rng)}${_word(rng, 16)}$ext';
}

/// A grab-bag of error objects an underlying engine might surface; LiteRtService
/// must treat them all the same way.
List<Object> _engineErrors() => [
      Exception('engine boom'),
      StateError('bad state'),
      ArgumentError('bad arg'),
      const FormatException('corrupt header'),
      'plain string failure',
    ];

LiteRtService _newService(_FakeGemma gemma) => LiteRtService(gemma: gemma);

_FakeGemma _newGemma() =>
    _FakeGemma(_FakeModelManager(), _FakeInferenceModel());

void main() {
  group('Property 9: LiteRT error conditions (multi-engine-ai-models)', () {
    // -----------------------------------------------------------------------
    // 3.7 / 3.9: a supported-format load that fails to initialize raises an
    // error AND reports isModelLoaded == false (and chat then reports no model).
    // -----------------------------------------------------------------------
    test('supported-format load failure raises error and isModelLoaded==false',
        () async {
      final rng = Random(20240901);
      final errors = _engineErrors();

      for (var i = 0; i < _iterations; i++) {
        final gemma = _newGemma();
        // Randomly fail at the install step or the createModel step.
        final failAtInstall = rng.nextBool();
        final err = errors[rng.nextInt(errors.length)];
        if (failAtInstall) {
          gemma.fakeManager.setModelPathError = err;
        } else {
          gemma.createModelError = err;
        }

        final service = _newService(gemma);
        final path = _supportedPath(rng);

        Object? thrown;
        try {
          await service.loadModel(path);
        } catch (e) {
          thrown = e;
        }

        if (thrown == null) {
          fail('Property 9 counterexample: load of supported path "$path" with '
              'injected engine error did not throw');
        }
        expect(thrown, isA<AIServiceException>(),
            reason: 'load failure for "$path" should surface an '
                'AIServiceException, got ${thrown.runtimeType}');
        expect((thrown as AIServiceException).errorCode, 'AI_MODEL_LOAD_FAILED',
            reason: 'load failure for "$path" should be a model-load-failed error');
        // 3.7 / 3.9: the model must be cleared.
        expect(service.isModelLoaded, isFalse,
            reason: 'isModelLoaded must be false after a failed load of "$path"');

        // 3.10 corollary: with no model loaded, chat reports "no model loaded".
        await expectLater(
          service.chat('hello').toList(),
          throwsA(isA<AIServiceException>().having(
              (e) => e.errorCode, 'errorCode', 'AI_MODEL_NOT_LOADED')),
          reason: 'chat after failed load should report no model loaded',
        );
      }
    });

    // -----------------------------------------------------------------------
    // 3.7 / 3.9 / 10.1: a supported-format load whose engine init exceeds the
    // 30-second timeout clears the model and throws. Driven with fake time so
    // the property runs cheaply.
    // -----------------------------------------------------------------------
    test('30-second init timeout clears the model and throws', () {
      final rng = Random(424242);
      for (var i = 0; i < _iterations; i++) {
        final gemma = _newGemma()..createModelHangs = true;
        final service = _newService(gemma);
        final path = _supportedPath(rng);

        fakeAsync((async) {
          Object? thrown;
          var completed = false;
          service.loadModel(path).then(
            (_) {
              completed = true;
            },
            onError: (Object e) {
              thrown = e;
            },
          );

          // Before the timeout elapses the load is still pending.
          async.elapse(const Duration(seconds: 29));
          expect(completed, isFalse);
          expect(thrown, isNull,
              reason: 'load of "$path" should not fail before 30s');

          // Cross the 30-second boundary: the timeout must fire.
          async.elapse(const Duration(seconds: 2));
          async.flushMicrotasks();

          expect(thrown, isA<AIServiceException>(),
              reason: 'init timeout for "$path" should throw an AIServiceException');
          expect((thrown as AIServiceException).errorCode, 'AI_MODEL_LOAD_FAILED');
          expect(service.isModelLoaded, isFalse,
              reason: 'isModelLoaded must be false after an init timeout for "$path"');
        });
      }
    });

    // -----------------------------------------------------------------------
    // 3.8: an unsupported file format raises an unsupported-format error and
    // leaves a PREVIOUSLY loaded model loaded (engine state untouched).
    // -----------------------------------------------------------------------
    test('unsupported format keeps a previously loaded model loaded', () async {
      final rng = Random(13579);

      for (var i = 0; i < _iterations; i++) {
        final gemma = _newGemma();
        final service = _newService(gemma);

        // First, load a real (supported) model successfully.
        final goodPath = _supportedPath(rng);
        await service.loadModel(goodPath);
        expect(service.isModelLoaded, isTrue,
            reason: 'precondition: "$goodPath" should load successfully');
        final installCallsAfterLoad = gemma.fakeManager.setModelPathCalls;
        final createCallsAfterLoad = gemma.createModelCalls;

        // Now attempt to load an unsupported format.
        final badPath = _unsupportedPath(rng);
        Object? thrown;
        try {
          await service.loadModel(badPath);
        } catch (e) {
          thrown = e;
        }

        expect(thrown, isA<ValidationException>(),
            reason: 'unsupported path "$badPath" should raise ValidationException');
        expect((thrown as ValidationException).errorCode,
            'VALIDATION_UNSUPPORTED_FORMAT',
            reason: 'unsupported path "$badPath" should be an unsupported-format error');

        // 3.8: the previously loaded model stays loaded and usable.
        expect(service.isModelLoaded, isTrue,
            reason: 'previous model must stay loaded after rejecting "$badPath"');
        // The engine was never touched by the rejected load.
        expect(gemma.fakeManager.setModelPathCalls, installCallsAfterLoad,
            reason: 'rejecting "$badPath" must not re-install via the engine');
        expect(gemma.createModelCalls, createCallsAfterLoad,
            reason: 'rejecting "$badPath" must not create a new engine model');
      }
    });

    // -----------------------------------------------------------------------
    // 3.8 (fresh state): an unsupported format on a service with no loaded
    // model raises the unsupported-format error and leaves it with no model.
    // -----------------------------------------------------------------------
    test('unsupported format on a fresh service raises and loads nothing',
        () async {
      final rng = Random(2468);
      for (var i = 0; i < _iterations; i++) {
        final gemma = _newGemma();
        final service = _newService(gemma);
        final badPath = _unsupportedPath(rng);

        Object? thrown;
        try {
          await service.loadModel(badPath);
        } catch (e) {
          thrown = e;
        }

        expect(thrown, isA<ValidationException>(),
            reason: 'unsupported path "$badPath" should raise ValidationException');
        expect((thrown as ValidationException).errorCode,
            'VALIDATION_UNSUPPORTED_FORMAT');
        expect(service.isModelLoaded, isFalse,
            reason: 'no model should be loaded after rejecting "$badPath"');
        expect(gemma.createModelCalls, 0,
            reason: 'engine must not be invoked for unsupported "$badPath"');
      }
    });

    // -----------------------------------------------------------------------
    // 3.10: chat while no LiteRT model is loaded raises a "no model loaded"
    // error, for any prompt / system prompt / sampling parameters.
    // -----------------------------------------------------------------------
    test('chat with no loaded model raises a no-model-loaded error', () async {
      final rng = Random(98765);
      for (var i = 0; i < _iterations; i++) {
        final service = _newService(_newGemma());
        final prompt = _word(rng, 30);
        final hasSystem = rng.nextBool();
        final systemPrompt = hasSystem ? _word(rng, 20) : null;
        final maxTokens = 1 + rng.nextInt(2048);
        final temperature = rng.nextDouble() * 2.0;

        await expectLater(
          service
              .chat(
                prompt,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                temperature: temperature,
              )
              .toList(),
          throwsA(isA<AIServiceException>().having(
              (e) => e.errorCode, 'errorCode', 'AI_MODEL_NOT_LOADED')),
          reason: 'chat with no model loaded must report no model loaded '
              '(prompt="$prompt", systemPrompt=$systemPrompt)',
        );
        expect(service.isModelLoaded, isFalse);
      }
    });

    // -----------------------------------------------------------------------
    // A couple of concrete, deterministic examples for at-a-glance documentation.
    // -----------------------------------------------------------------------
    test('example: engine throwing on createModel clears the model', () async {
      final gemma = _newGemma()..createModelError = Exception('init failed');
      final service = _newService(gemma);
      await expectLater(
        service.loadModel('/models/gemma3-1b.task'),
        throwsA(isA<AIServiceException>()),
      );
      expect(service.isModelLoaded, isFalse);
    });

    test('example: .gguf file is rejected as unsupported format', () async {
      final service = _newService(_newGemma());
      await expectLater(
        service.loadModel('/models/qwen2.5-0.5b.gguf'),
        throwsA(isA<ValidationException>()),
      );
      expect(service.isModelLoaded, isFalse);
    });
  });
}
