import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/domain/entities/online_model.dart';
import 'package:dio/dio.dart';

import 'llm_service.dart';

/// OpenAI-compatible streaming adapter shared by OpenRouter, Groq and NVIDIA.
class OpenAICompatibleLLMService implements LLMService, CancellableLLMService {
  final Dio _dio;
  OnlineProvider? _provider;
  OnlineModel? _model;
  String? _apiKey;
  CancelToken? _cancelToken;
  bool _isGenerating = false;

  OpenAICompatibleLLMService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(minutes: 5),
              sendTimeout: const Duration(seconds: 30),
            ),
          );

  OnlineProvider? get activeProvider => _provider;
  OnlineModel? get activeModel => _model;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadModel(String modelPath) {
    throw UnsupportedError(
      'Online models must be configured by provider and model ID.',
    );
  }

  void configure({
    required OnlineProvider provider,
    required OnlineModel model,
    required String apiKey,
  }) {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError(
        'An API key is required for ${provider.displayName}.',
      );
    }
    _provider = provider;
    _model = model;
    _apiKey = apiKey.trim();
  }

  void clearConfiguration() {
    unawaited(cancelGeneration());
    _provider = null;
    _model = null;
    _apiKey = null;
  }

  Future<List<OnlineModel>> listModels({
    required OnlineProvider provider,
    required String apiKey,
  }) async {
    try {
      if (provider == OnlineProvider.openRouter) {
        await _dio.get<Map<String, dynamic>>(
          '${provider.baseUrl}/auth/key',
          options: Options(headers: _headers(provider, apiKey)),
        );
      }
      final response = await _dio.get<Map<String, dynamic>>(
        '${provider.baseUrl}/models',
        options: Options(headers: _headers(provider, apiKey)),
      );
      final raw = response.data?['data'];
      if (raw is! List) {
        throw _providerError(
          'The provider returned an invalid model catalog.',
          'Missing data array from ${provider.id} /models.',
          'AI_PROVIDER_INVALID_RESPONSE',
        );
      }
      final models =
          raw
              .whereType<Map>()
              .map(
                (entry) => OnlineModel.fromApi(
                  provider,
                  Map<String, dynamic>.from(entry),
                ),
              )
              .where((model) => model.id.isNotEmpty && model.isChatCapable)
              .toList()
            ..sort(
              (a, b) => b.recommendationScore.compareTo(a.recommendationScore),
            );
      return models;
    } on DioException catch (error) {
      throw _mapDioError(error, provider);
    }
  }

  Future<OnlineModel> validateConfiguration({
    required OnlineProvider provider,
    required OnlineModel model,
    required String apiKey,
  }) async {
    final models = await listModels(provider: provider, apiKey: apiKey);
    return models.firstWhere(
      (candidate) => candidate.id == model.id,
      orElse: () => throw _providerError(
        'This model is no longer available from ${provider.displayName}.',
        'Model ${model.id} was absent from the live provider catalog.',
        'AI_PROVIDER_MODEL_UNAVAILABLE',
      ),
    );
  }

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
    Uint8List? imageBytes,
  }) async* {
    final provider = _provider;
    final model = _model;
    final apiKey = _apiKey;
    if (provider == null || model == null || apiKey == null) {
      throw AIServiceException.modelNotLoaded();
    }
    if (_isGenerating) {
      throw StateError('The online model is already generating.');
    }
    if (imageBytes != null && !model.supportsVision) {
      throw _providerError(
        'The selected online model does not support images.',
        'Image input requested for non-vision model ${model.id}.',
        'AI_PROVIDER_VISION_UNSUPPORTED',
      );
    }

    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    _isGenerating = true;
    try {
      final response = await _dio.post<ResponseBody>(
        '${provider.baseUrl}/chat/completions',
        data: <String, dynamic>{
          'model': model.id,
          'messages': _messages(prompt, systemPrompt, imageBytes),
          'stream': true,
          'max_tokens': maxTokens,
          'temperature': temperature,
        },
        options: Options(
          headers: _headers(provider, apiKey),
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );
      final body = response.data;
      if (body == null) {
        throw _providerError(
          'The provider returned an empty response.',
          'Missing response body from ${provider.id}.',
          'AI_PROVIDER_EMPTY_RESPONSE',
        );
      }

      final contentType = response.headers.value(Headers.contentTypeHeader);
      if (contentType?.toLowerCase().contains('application/json') == true) {
        final raw = await body.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['error'] != null) {
          final error = decoded['error'];
          final providerCode = error is Map ? error['code']?.toString() : null;
          throw _providerError(
            '${provider.displayName} rejected the streamed request.',
            'Provider JSON error${providerCode == null ? '' : ' ($providerCode)'}.',
            'AI_PROVIDER_STREAM_ERROR',
          );
        }
        throw _providerError(
          'The provider returned an unsupported response.',
          'Expected text/event-stream but received $contentType.',
          'AI_PROVIDER_INVALID_STREAM',
        );
      }

      var sawContent = false;
      var completed = false;
      await for (final event in _decodeSse(body.stream.cast<List<int>>())) {
        if (cancelToken.isCancelled) {
          throw const GenerationCancelledException();
        }
        final payload = event.data.trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') {
          completed = true;
          break;
        }
        if (event.type == 'error') {
          throw _providerError(
            '${provider.displayName} rejected the streamed request.',
            'Provider emitted an SSE error event.',
            'AI_PROVIDER_STREAM_ERROR',
          );
        }

        final decoded = jsonDecode(payload);
        if (decoded is! Map) {
          throw const FormatException('SSE data was not a JSON object.');
        }
        final message = Map<String, dynamic>.from(decoded);
        if (message['error'] != null) {
          final rawError = message['error'];
          final providerCode = rawError is Map
              ? rawError['code']?.toString()
              : null;
          throw _providerError(
            '${provider.displayName} rejected the streamed request.',
            'Provider stream error${providerCode == null ? '' : ' ($providerCode)'}.',
            'AI_PROVIDER_STREAM_ERROR',
          );
        }

        final choices = message['choices'];
        if (choices is! List || choices.isEmpty || choices.first is! Map) {
          continue;
        }
        final choice = Map<String, dynamic>.from(choices.first as Map);
        if (choice['finish_reason'] != null) completed = true;
        final delta = choice['delta'];
        if (delta is Map) {
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            sawContent = true;
            yield content;
          }
        }
      }
      if (cancelToken.isCancelled) {
        throw const GenerationCancelledException();
      }
      if (!completed) {
        throw _providerError(
          'The provider ended the response unexpectedly.',
          'SSE stream ended without [DONE] or finish_reason.',
          'AI_PROVIDER_INCOMPLETE_STREAM',
        );
      }
      if (!sawContent) {
        throw _providerError(
          'The provider returned no response text.',
          'SSE stream completed without a content delta.',
          'AI_PROVIDER_EMPTY_RESPONSE',
        );
      }
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || cancelToken.isCancelled) {
        throw const GenerationCancelledException();
      }
      throw _mapDioError(error, provider);
    } on GenerationCancelledException {
      rethrow;
    } on AIServiceException {
      rethrow;
    } on FormatException catch (error) {
      throw _providerError(
        'The provider sent an unreadable streaming response.',
        'SSE JSON parsing failed: $error',
        'AI_PROVIDER_INVALID_STREAM',
      );
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
      _isGenerating = false;
    }
  }

  Stream<_SseEvent> _decodeSse(Stream<List<int>> bytes) async* {
    String? eventType;
    var dataLines = <String>[];

    await for (final line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (dataLines.isNotEmpty) {
          yield _SseEvent(type: eventType, data: dataLines.join('\n'));
        }
        eventType = null;
        dataLines = <String>[];
        continue;
      }
      if (line.startsWith(':')) continue;
      final separator = line.indexOf(':');
      final field = separator < 0 ? line : line.substring(0, separator);
      var value = separator < 0 ? '' : line.substring(separator + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      if (field == 'event') {
        eventType = value;
      } else if (field == 'data') {
        dataLines.add(value);
      }
    }

    if (dataLines.isNotEmpty) {
      yield _SseEvent(type: eventType, data: dataLines.join('\n'));
    }
  }

  List<Map<String, dynamic>> _messages(
    String prompt,
    String? systemPrompt,
    Uint8List? imageBytes,
  ) {
    final messages = <Map<String, dynamic>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      messages.add(<String, dynamic>{
        'role': 'system',
        'content': systemPrompt,
      });
    }
    if (imageBytes == null) {
      messages.add(<String, dynamic>{'role': 'user', 'content': prompt});
    } else {
      messages.add(<String, dynamic>{
        'role': 'user',
        'content': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'text': prompt},
          <String, dynamic>{
            'type': 'image_url',
            'image_url': <String, String>{
              'url': 'data:image/jpeg;base64,${base64Encode(imageBytes)}',
            },
          },
        ],
      });
    }
    return messages;
  }

  Map<String, String> _headers(OnlineProvider provider, String apiKey) {
    final headers = <String, String>{
      'Authorization': 'Bearer ${apiKey.trim()}',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream, application/json',
    };
    if (provider == OnlineProvider.openRouter) {
      headers['X-Title'] = 'Aura Mobile';
    }
    return headers;
  }

  AIServiceException _mapDioError(DioException error, OnlineProvider provider) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return _providerError(
        '${provider.displayName} rejected the API key.',
        'Authentication failed with HTTP $status.',
        'AI_PROVIDER_AUTH_FAILED',
      );
    }
    if (status == 429) {
      return _providerError(
        '${provider.displayName} rate limit reached.',
        'Provider returned HTTP 429.',
        'AI_PROVIDER_RATE_LIMITED',
      );
    }
    if (status == 404) {
      return _providerError(
        'The selected model is unavailable.',
        'Provider returned HTTP 404.',
        'AI_PROVIDER_MODEL_UNAVAILABLE',
      );
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return _providerError(
        'The online model request timed out.',
        'Dio timeout while contacting ${provider.id}.',
        'AI_PROVIDER_TIMEOUT',
      );
    }
    if (error.type == DioExceptionType.connectionError) {
      return _providerError(
        'Could not connect to ${provider.displayName}.',
        'Dio connection error for ${provider.id}.',
        'AI_PROVIDER_OFFLINE',
      );
    }
    return _providerError(
      '${provider.displayName} could not complete the request.',
      'Provider request failed with HTTP ${status ?? 'unknown'}.',
      'AI_PROVIDER_REQUEST_FAILED',
    );
  }

  AIServiceException _providerError(
    String message,
    String details,
    String code,
  ) {
    return AIServiceException(
      message: message,
      technicalDetails: details,
      recoverySuggestion:
          'Check the provider key, model availability, and current rate limits.',
      errorCode: code,
    );
  }

  @override
  Future<void> cancelGeneration() async {
    final token = _cancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled generation.');
    }
  }

  @override
  bool get isModelLoaded =>
      _provider != null && _model != null && _apiKey != null;

  @override
  bool get isGenerating => _isGenerating;

  @override
  ModelTier get modelTier => ModelTier.large;

  @override
  bool get supportsToolCalling => _model?.supportsToolCalling ?? false;

  @override
  bool get supportsVision => _model?.supportsVision ?? false;

  /// Provider-reported context length for the selected online model.
  @override
  int get contextTokens => _model?.contextLength ?? 4096;
}

class _SseEvent {
  final String? type;
  final String data;

  const _SseEvent({required this.type, required this.data});
}
