import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';

// Feature: multi-engine-ai-models — integration test for flutter_gemma delegation
//
// Requirement 3.2: "THE LiteRtService SHALL perform inference for LiteRT models
// by delegating to the flutter_gemma package."
//
// This is an integration-style test (not a property test). It injects a mock
// FlutterGemmaPlugin into LiteRtService and verifies that the full loadModel +
// chat round-trip actually routes through the flutter_gemma package surface:
//   - loadModel -> modelManager.setModelPath + plugin.createModel
//   - chat      -> model.createSession + session.addQueryChunk +
//                  session.getResponseAsync (+ session.close on completion)
//
// The fakes record every call (and their arguments) so the test asserts the
// delegation happened, in order, with the expected values — rather than relying
// on any real native engine.

void main() {
  group(
      'LiteRtService delegates inference to the flutter_gemma package '
      '(Requirement 3.2)', () {
    test('loadModel routes through modelManager.setModelPath and createModel',
        () async {
      final manager = _RecordingModelManager();
      final session = _RecordingSession(const ['ignored']);
      final model = _RecordingModel(session);
      final plugin = _RecordingPlugin(manager, model);
      final service = LiteRtService(gemma: plugin);

      await service.initialize();
      await service.loadModel('/models/gemma3-1b.task');

      // Delegation to the package's model manager: the local file was installed.
      expect(manager.setModelPathCalls, ['/models/gemma3-1b.task'],
          reason: 'loadModel must install the model file via '
              'flutter_gemma ModelFileManager.setModelPath');

      // Delegation to the package's model factory.
      expect(plugin.createModelCalls, 1,
          reason: 'loadModel must create the inference model via '
              'flutter_gemma FlutterGemmaPlugin.createModel');
      expect(plugin.lastModelType, ModelType.gemmaIt);
      expect(plugin.lastFileType, ModelFileType.task);

      // The service now considers a model loaded.
      expect(service.isModelLoaded, isTrue);
    });

    test(
        'chat routes through createSession, addQueryChunk and getResponseAsync',
        () async {
      final manager = _RecordingModelManager();
      final session = _RecordingSession(const ['Hello', ', ', 'world']);
      final model = _RecordingModel(session);
      final plugin = _RecordingPlugin(manager, model);
      final service = LiteRtService(gemma: plugin);

      await service.initialize();
      await service.loadModel('/models/gemma3-1b.task');

      final tokens = await service
          .chat('How are you?', systemPrompt: 'Be brief', temperature: 0.3)
          .toList();

      // Output is exactly what the package's session streamed back.
      expect(tokens, ['Hello', ', ', 'world']);

      // Delegation to the package: a session was opened with the temperature.
      expect(model.createSessionCalls, 1,
          reason: 'chat must open a session via InferenceModel.createSession');
      expect(model.lastTemperature, 0.3);

      // Delegation to the package: the prompt was fed via addQueryChunk, and
      // the text handed to the package is the Gemma-formatted prompt the
      // service produces.
      expect(session.addQueryChunkCalls, 1,
          reason: 'chat must feed the prompt via '
              'InferenceModelSession.addQueryChunk');
      final expectedPrompt = LiteRtService.formatGemmaPrompt(
        'How are you?',
        systemPrompt: 'Be brief',
      );
      expect(session.lastQueryText, expectedPrompt,
          reason: 'the formatted Gemma prompt must be the text delegated to '
              'flutter_gemma');

      // Delegation to the package: the response stream was consumed.
      expect(session.getResponseAsyncCalls, 1,
          reason: 'chat must read tokens via '
              'InferenceModelSession.getResponseAsync');

      // The session opened for the turn is closed once generation completes.
      expect(session.closeCalls, 1,
          reason: 'chat must close the session once generation completes');
    });

    test('a full load + chat invokes the package surface in the right order',
        () async {
      final manager = _RecordingModelManager();
      final session = _RecordingSession(const ['ok']);
      final model = _RecordingModel(session);
      final plugin = _RecordingPlugin(manager, model);
      final service = LiteRtService(gemma: plugin);

      await service.initialize();
      await service.loadModel('/models/gemma4-e2b.task');
      await service.chat('hi').toList();

      expect(
        plugin.callLog,
        [
          'setModelPath(/models/gemma4-e2b.task)',
          'createModel',
          'createSession',
          'addQueryChunk',
          'getResponseAsync',
          'close',
        ],
        reason: 'LiteRtService must drive the flutter_gemma package through the '
            'load -> session -> query -> response -> close sequence',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Recording fakes for the flutter_gemma surface LiteRtService depends on.
// A shared [callLog] (owned by the plugin) records the cross-object call order.
// ---------------------------------------------------------------------------

class _RecordingPlugin implements FlutterGemmaPlugin {
  _RecordingPlugin(this._manager, this._model) {
    _manager.callLog = callLog;
    _model.callLog = callLog;
  }

  final _RecordingModelManager _manager;
  final _RecordingModel _model;

  /// Ordered log of every package call across plugin/model/session.
  final List<String> callLog = [];

  int createModelCalls = 0;
  ModelType? lastModelType;
  ModelFileType? lastFileType;

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
    createModelCalls++;
    lastModelType = modelType;
    lastFileType = fileType;
    callLog.add('createModel');
    return _model;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected call to _RecordingPlugin.${invocation.memberName}');
}

class _RecordingModelManager implements ModelFileManager {
  List<String> callLog = [];
  final List<String> setModelPathCalls = [];

  @override
  // ignore: deprecated_member_use
  Future<void> setModelPath(String path, {String? loraPath}) async {
    setModelPathCalls.add(path);
    callLog.add('setModelPath($path)');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected call to _RecordingModelManager.${invocation.memberName}');
}

class _RecordingModel implements InferenceModel {
  _RecordingModel(this._session);

  final _RecordingSession _session;
  List<String> callLog = [];

  int createSessionCalls = 0;
  double? lastTemperature;

  @override
  Future<InferenceModelSession> createSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality,
    bool? enableAudioModality,
  }) async {
    createSessionCalls++;
    lastTemperature = temperature;
    callLog.add('createSession');
    _session.callLog = callLog;
    return _session;
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected call to _RecordingModel.${invocation.memberName}');
}

class _RecordingSession implements InferenceModelSession {
  _RecordingSession(this._tokens);

  final List<String> _tokens;
  List<String> callLog = [];

  int addQueryChunkCalls = 0;
  String? lastQueryText;
  int getResponseAsyncCalls = 0;
  int closeCalls = 0;

  @override
  Future<void> addQueryChunk(Message message) async {
    addQueryChunkCalls++;
    lastQueryText = message.text;
    callLog.add('addQueryChunk');
  }

  @override
  Stream<String> getResponseAsync() async* {
    getResponseAsyncCalls++;
    callLog.add('getResponseAsync');
    for (final token in _tokens) {
      yield token;
    }
  }

  @override
  Future<void> close() async {
    closeCalls++;
    callLog.add('close');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'Unexpected call to _RecordingSession.${invocation.memberName}');
}
