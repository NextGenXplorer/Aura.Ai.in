enum OnlineProvider {
  openRouter,
  groq,
  nvidia;

  String get id => switch (this) {
    openRouter => 'openrouter',
    groq => 'groq',
    nvidia => 'nvidia',
  };

  String get displayName => switch (this) {
    openRouter => 'OpenRouter',
    groq => 'Groq',
    nvidia => 'NVIDIA NIM',
  };

  String get baseUrl => switch (this) {
    openRouter => 'https://openrouter.ai/api/v1',
    groq => 'https://api.groq.com/openai/v1',
    nvidia => 'https://integrate.api.nvidia.com/v1',
  };

  String get keyUrl => switch (this) {
    openRouter => 'https://openrouter.ai/keys',
    groq => 'https://console.groq.com/keys',
    nvidia => 'https://build.nvidia.com/',
  };

  String get availabilityNote => switch (this) {
    openRouter => 'Choose models marked :free. Limits can change by provider.',
    groq => 'Developer free-tier limits are account and model dependent.',
    nvidia => 'Hosted NIM evaluation access and credits can change.',
  };

  static OnlineProvider? fromId(String? id) {
    for (final provider in values) {
      if (provider.id == id) return provider;
    }
    return null;
  }
}

class OnlineModel {
  final OnlineProvider provider;
  final String id;
  final String name;
  final int contextLength;
  final bool isExplicitlyFree;
  final bool supportsVision;
  final bool supportsToolCalling;
  final bool isChatCapable;
  final String description;

  const OnlineModel({
    required this.provider,
    required this.id,
    required this.name,
    required this.contextLength,
    required this.isExplicitlyFree,
    required this.supportsVision,
    required this.supportsToolCalling,
    required this.isChatCapable,
    required this.description,
  });

  String get selectionId => 'online:${provider.id}:$id';

  String get contextLabel {
    if (contextLength >= 1000000) {
      return '${(contextLength / 1000000).toStringAsFixed(1)}M context';
    }
    return '${(contextLength / 1000).round()}K context';
  }

  int get recommendationScore {
    final lower = '$id $name'.toLowerCase();
    var score = (contextLength / 4096).round().clamp(0, 80);
    if (isExplicitlyFree) score += 35;
    if (supportsToolCalling) score += 15;
    if (supportsVision) score += 8;
    if (lower.contains('70b') || lower.contains('120b')) score += 18;
    if (lower.contains('32b') || lower.contains('30b')) score += 12;
    if (lower.contains('instruct') || lower.contains('versatile')) score += 8;
    return score;
  }

  factory OnlineModel.fromApi(
    OnlineProvider provider,
    Map<String, dynamic> json,
  ) {
    final id = (json['id'] ?? '').toString();
    final name = (json['name'] ?? id).toString();
    final architecture = json['architecture'];
    final inputModalities = architecture is Map
        ? _asStrings(architecture['input_modalities'])
        : const <String>[];
    final outputModalities = architecture is Map
        ? _asStrings(architecture['output_modalities'])
        : const <String>[];
    final capabilities = json['capabilities'] is Map
        ? Map<String, dynamic>.from(json['capabilities'] as Map)
        : const <String, dynamic>{};
    final pricing = json['pricing'];
    final promptPrice = pricing is Map ? pricing['prompt']?.toString() : null;
    final completionPrice = pricing is Map
        ? pricing['completion']?.toString()
        : null;
    // Zero token pricing does NOT mean free: generation models (image, audio,
    // video) bill per output artefact and report "0" for prompt/completion.
    // Only trust zero token pricing when no other priced dimension is charged.
    final hasOtherCharge = pricing is Map &&
        pricing.entries.any(
          (entry) =>
              entry.key != 'prompt' &&
              entry.key != 'completion' &&
              _isNonZeroPrice(entry.value),
        );
    final explicitlyFree = id.endsWith(':free') ||
        (promptPrice == '0' && completionPrice == '0' && !hasOtherCharge);
    final classification =
        '$id $name ${json['type'] ?? ''} ${json['task'] ?? ''}'.toLowerCase();
    final context =
        _asInt(json['context_length']) ??
        _asInt(json['context_window']) ??
        8192;
    final vision =
        inputModalities.contains('image') ||
        capabilities['vision'] == true ||
        capabilities['image_input'] == true;
    final nonChatPattern = RegExp(
      r'(embed|rerank|moderation|guard|safety|whisper|transcri|speech|tts|'
      r'audio|image[-_ ]?(generation|generator)|text[-_ ]?to[-_ ]?image|'
      r'stable[-_ ]?diffusion|flux)',
    );
    // Classify by declared output modalities, not by guessing from the name.
    // A chat model emits text and nothing else. Anything that also emits image,
    // audio, or video is a generation model: Aura's adapter consumes text deltas
    // only, so selecting one as the chat brain fails at request time. The name
    // regex below stays as a secondary guard for text-emitting non-chat models
    // (embeddings, rerankers, moderation) that modalities alone cannot reveal.
    final textOnlyOutput = outputModalities.isEmpty ||
        (outputModalities.contains('text') &&
            !outputModalities.any(_isGenerationModality));

    return OnlineModel(
      provider: provider,
      id: id,
      name: name,
      contextLength: context,
      isExplicitlyFree: explicitlyFree,
      supportsVision: vision,
      // Aura's current online adapter consumes text deltas only. Do not enter
      // executable tool handling until native tool schemas/results are wired.
      supportsToolCalling: false,
      isChatCapable:
          textOnlyOutput && !nonChatPattern.hasMatch(classification),
      description: (json['description'] ?? provider.availabilityNote)
          .toString(),
    );
  }

  /// Output modalities that make a model a generation model rather than a chat
  /// model, because Aura's online adapter can only consume text deltas.
  static bool _isGenerationModality(String modality) =>
      modality == 'image' || modality == 'audio' || modality == 'video';

  /// True when a pricing entry represents a real, non-zero charge.
  static bool _isNonZeroPrice(Object? value) {
    final parsed = double.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0;
  }

  static List<String> _asStrings(Object? value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString().toLowerCase()).toList();
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
