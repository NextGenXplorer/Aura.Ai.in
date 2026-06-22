import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';

// Feature: multi-engine-ai-models, Property 8: LiteRT response streaming round-trip
//
// "For any sequence of response tokens produced by the underlying session, the
//  LiteRtService chat stream yields those tokens in order such that their
//  concatenation equals the source text, and the stream terminates (closes)
//  when generation completes."
//
// Validates: Requirements 3.5
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. The
// property runs >= 100 generated cases. The underlying `flutter_gemma`
// session is replaced with a fake that emits a known token sequence so the
// round-trip is observed through LiteRtService.chat without the native engine.

const int _iterations = 200;

/// A grab-bag of "interesting" token fragments the generator can sample from,
/// alongside random alphanumeric chunks. Includes empty strings, whitespace,
/// unicode, and strings that look like stop markers — the LiteRT path must
/// relay tokens verbatim (no cleaning), so even marker-like tokens round-trip.
const List<String> _interestingFragments = [
  '',
  ' ',
  '\n',
  '\t',
  'Hello',
  'world',
  '你好',
  '🚀',
  '<|im_end|>', // GGUF marker — must NOT be stripped by the LiteRT engine
  '<start_of_turn>',
  '<end_of_turn>',
  '.',
  ',',
  '42',
];

const String _alphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ';

String _randomChunk(Random rng) {
  // Half the time return a curated fragment, otherwise a random chunk.
  if (rng.nextBool()) {
    return _interestingFragments[rng.nextInt(_interestingFragments.length)];
  }
  final len = rng.nextInt(8);
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.write(_alphabet[rng.nextInt(_alphabet.length)]);
  }
  return sb.toString();
}

/// Generates a random token sequence (possibly empty) to be emitted by the
/// fake session.
List<String> _generateTokens(Random rng) {
  final count = rng.nextInt(12); // 0..11 tokens, including the empty stream
  return List.generate(count, (_) => _randomChunk(rng));
}

void main() {
  group('Property 8: LiteRT response streaming round-trip (multi-engine-ai-models)',
      () {
    test('chat relays the session tokens in order, intact, and closes the stream',
        () async {
      final rng = Random(20240711);

      for (var i = 0; i < _iterations; i++) {
        final sourceTokens = _generateTokens(rng);

        final session = _FakeSession(sourceTokens);
        final model = _FakeModel(session);
        final plugin = _FakePlugin(model);
        final service = LiteRtService(gemma: plugin);

        await service.initialize();
        await service.loadModel('/models/gemma3-1b.task');

        List<String> relayed;
        try {
          relayed = await service.chat('prompt $i').toList();
        } catch (e) {
          fail('Property 8 counterexample (chat threw $e)\n'
              '  sourceTokens = $sourceTokens');
        }

        // (a) Order + content preserved token-by-token.
        expect(relayed, equals(sourceTokens),
            reason: 'Property 8 counterexample (token sequence mismatch)\n'
                '  sourceTokens = $sourceTokens\n'
                '  relayed      = $relayed');

        // (b) Concatenation of relayed text equals the source text.
        expect(relayed.join(), equals(sourceTokens.join()),
            reason: 'Property 8 counterexample (concatenation mismatch)\n'
                '  sourceTokens = $sourceTokens\n'
                '  relayed      = $relayed');

        // (c) The stream terminated on completion. `toList()` returning proves
        //     the relayed stream closed; the service must also have closed the
        //     underlying session exactly once when generation completed.
        expect(session.closeCount, 1,
            reason: 'Property 8 counterexample (session not closed once on '
                'completion)\n  closeCount = ${session.closeCount}');
        expect(session.responseConsumed, isTrue,
            reason: 'Property 8 counterexample (underlying response not '
                'consumed)');
      }
    });

    // A concrete, deterministic example documenting the intended behavior.
    test('example: a fixed token sequence round-trips verbatim', () async {
      final session = _FakeSession(['The ', 'quick ', 'brown ', 'fox']);
      final service =
          LiteRtService(gemma: _FakePlugin(_FakeModel(session)));
      await service.initialize();
      await service.loadModel('/models/gemma3-1b.task');

      final out = await service.chat('hi').toList();

      expect(out, ['The ', 'quick ', 'brown ', 'fox']);
      expect(out.join(), 'The quick brown fox');
      expect(session.closeCount, 1);
    });

    test('example: an empty token stream yields nothing and still closes',
        () async {
      final session = _FakeSession(const []);
      final service =
          LiteRtService(gemma: _FakePlugin(_FakeModel(session)));
      await service.initialize();
      await service.loadModel('/models/gemma3-1b.task');

      final out = await service.chat('hi').toList();

      expect(out, isEmpty);
      expect(session.closeCount, 1);
    });
  });
}

// --- Fakes for the flutter_gemma surface LiteRtService depends on. ---------

/// Fake plugin: returns a fixed [InferenceModel] from [createModel] and a
/// no-op model manager so [LiteRtService.loadModel] succeeds in tests.
class _FakePlugin implements FlutterGemmaPlugin {
  _FakePlugin(this._model);

  final InferenceModel _model;
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
  }) async =>
      _model;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected call to _FakePlugin.${invocation.memberName}');
}

/// Fake model manager: [setModelPath] is a no-op; everything else is unused.
class _FakeModelManager implements ModelFileManager {
  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected call to _FakeModelManager.${invocation.memberName}');
}

/// Fake inference model: hands out a single fixed session and records closure.
class _FakeModel implements InferenceModel {
  _FakeModel(this._session);

  final _FakeSession _session;

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
      _session;

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected call to _FakeModel.${invocation.memberName}');
}

/// Fake session that emits [_tokens] from [getResponseAsync] in order and
/// records how many times it was closed and whether its response was consumed.
class _FakeSession implements InferenceModelSession {
  _FakeSession(this._tokens);

  final List<String> _tokens;
  int closeCount = 0;
  bool responseConsumed = false;

  @override
  Future<void> addQueryChunk(Message message) async {}

  @override
  Stream<String> getResponseAsync() async* {
    for (final token in _tokens) {
      yield token;
    }
    // Marks that the source stream ran to completion (generation finished).
    responseConsumed = true;
  }

  @override
  Future<void> close() async {
    closeCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected call to _FakeSession.${invocation.memberName}');
}
