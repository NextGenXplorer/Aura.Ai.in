import 'dart:convert';

import 'package:dio/dio.dart';

/// A free, online text-to-image generation service.
///
/// On-device image generation models (Stable Diffusion etc.) are far too heavy
/// for phones, so AURA uses free online APIs instead. The primary provider is
/// **Pollinations.ai**, whose classic endpoint is URL-based, completely free,
/// and requires no API key or signup — the generated image *is* the URL, so it
/// can be rendered directly in a chat bubble via a standard markdown image.
///
/// The service is provider-based so additional free providers can be added as
/// fallbacks without changing callers.
enum ImageProvider {
  /// Pollinations.ai classic endpoint — free, no key, URL-based.
  pollinations,
}

/// Image styles/models the user can pick. All are available on Pollinations'
/// free, no-key endpoint. FLUX is the highest quality; Turbo is fastest; Sana
/// is the lightweight model the anonymous tier always exposes (reliable
/// fallback).
enum ImageModel {
  /// FLUX — best overall quality (Pollinations default).
  flux,

  /// Turbo — faster generation, lower quality.
  turbo,

  /// Sana — lightweight, always available on the free anonymous tier.
  sana,
}

class ImageGenerationService {
  ImageGenerationService();

  /// Pollinations classic image endpoint base (free, no key, no signup).
  static const String _pollinationsBase = 'https://image.pollinations.ai/prompt';

  /// Pollinations free text endpoint (no key) — used for AI meme captions and
  /// other short creative text.
  static const String _pollinationsTextBase = 'https://text.pollinations.ai';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Generates short creative text (e.g. a meme caption) from [prompt] using
  /// Pollinations' free, no-key text endpoint. Returns the trimmed text, or an
  /// empty string on failure.
  Future<String> generateText(String prompt) async {
    try {
      final url = '$_pollinationsTextBase/${Uri.encodeComponent(prompt.trim())}';
      final resp = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      return (resp.data ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  /// Generates a classic two-line meme caption for [topic]. Returns a record of
  /// (top, bottom) lines; falls back to ('', '') on failure so the caller can
  /// let the user type their own.
  Future<({String top, String bottom})> generateMemeCaption(String topic) async {
    final raw = await generateText(
      'Write a short, funny internet meme caption about "$topic". '
      'Reply with EXACTLY two short lines: the first line is the top text, '
      'the second line is the bottom text. No quotes, no extra words, '
      'all caps preferred.',
    );
    if (raw.isEmpty) return (top: '', bottom: '');
    final lines = raw
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'^[\s"\-*\d.]+'), '').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final top = lines.isNotEmpty ? lines.first : '';
    final bottom = lines.length > 1 ? lines[1] : '';
    return (top: top.toUpperCase(), bottom: bottom.toUpperCase());
  }

  /// Builds a direct image URL for [prompt] that renders the generated image
  /// when fetched. Because Pollinations is URL-based, no network call is made
  /// here — the returned URL is embedded (e.g. in a markdown image) and the
  /// image is generated on demand when the client loads it.
  ///
  /// [width]/[height] set the output size, [model] selects the generation
  /// model, and [seed] (when provided) makes the result reproducible.
  String buildImageUrl(
    String prompt, {
    int width = 1024,
    int height = 1024,
    ImageModel model = ImageModel.flux,
    int? seed,
    bool enhance = true,
    ImageProvider provider = ImageProvider.pollinations,
  }) {
    switch (provider) {
      case ImageProvider.pollinations:
        return _buildPollinationsUrl(
          prompt,
          width: width,
          height: height,
          model: model,
          seed: seed,
          enhance: enhance,
        );
    }
  }

  String _buildPollinationsUrl(
    String prompt, {
    required int width,
    required int height,
    required ImageModel model,
    int? seed,
    bool enhance = true,
  }) {
    // Path-encode the prompt (spaces and punctuation must be percent-encoded).
    final encodedPrompt = Uri.encodeComponent(prompt.trim());
    final params = <String, String>{
      'width': '$width',
      'height': '$height',
      'model': _pollinationsModel(model),
      // Remove the Pollinations watermark; prompt enhancement is optional.
      'nologo': 'true',
      if (enhance) 'enhance': 'true',
      if (seed != null) 'seed': '$seed',
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$_pollinationsBase/$encodedPrompt?$query';
  }

  String _pollinationsModel(ImageModel model) {
    switch (model) {
      case ImageModel.flux:
        return 'flux';
      case ImageModel.turbo:
        return 'turbo';
      case ImageModel.sana:
        return 'sana';
    }
  }

  /// Returns a chat-ready markdown snippet that renders the generated image
  /// inline (the chat bubble's MarkdownBody fetches network images), with a
  /// short caption naming the prompt.
  String buildChatImageMarkdown(
    String prompt, {
    int width = 1024,
    int height = 1024,
    ImageModel model = ImageModel.flux,
    int? seed,
  }) {
    final url = buildImageUrl(
      prompt,
      width: width,
      height: height,
      model: model,
      seed: seed,
    );
    final safePrompt = prompt.trim();
    return '![${_escapeAlt(safePrompt)}]($url)\n\n*Generated image for: "$safePrompt"*';
  }

  /// Escapes characters that would break markdown image alt text.
  String _escapeAlt(String s) => s.replaceAll(']', ' ').replaceAll('[', ' ');

  /// Detects whether [message] is an image-generation request and, if so,
  /// extracts the image subject/prompt. Returns `null` when it is not an
  /// image-generation request.
  ///
  /// Recognizes phrasings like "draw a cat", "generate an image of a sunset",
  /// "create a picture of ...", "make an image of ...", "imagine ...".
  static String? extractImagePrompt(String message) {
    final text = message.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();

    // Trigger verbs/phrases that indicate image generation.
    final patterns = <RegExp>[
      RegExp(r'^(?:please\s+)?(?:can you\s+)?(?:draw|sketch|paint)\s+(?:me\s+)?(?:a|an|the)?\s*(.+)',
          caseSensitive: false),
      RegExp(
          r'(?:generate|create|make|render|produce|design)\s+(?:me\s+)?(?:a|an)?\s*(?:image|picture|photo|drawing|illustration|art|wallpaper|logo)\s+(?:of|showing|with|for)?\s*(.+)',
          caseSensitive: false),
      RegExp(r'(?:image|picture|photo)\s+of\s+(.+)', caseSensitive: false),
      RegExp(r'^imagine\s+(.+)', caseSensitive: false),
    ];

    // Quick keyword gate to avoid false positives on normal chat.
    final hasImageWord = lower.contains('image') ||
        lower.contains('picture') ||
        lower.contains('photo') ||
        lower.contains('draw') ||
        lower.contains('sketch') ||
        lower.contains('paint') ||
        lower.contains('illustration') ||
        lower.contains('wallpaper') ||
        lower.contains('logo') ||
        lower.startsWith('imagine ');
    if (!hasImageWord) return null;

    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) {
        final subject = (m.group(1) ?? '').trim();
        if (subject.isNotEmpty && subject.length >= 2) {
          return subject;
        }
      }
    }
    return null;
  }

  /// JSON description of the generate_image tool for tool-calling models.
  static Map<String, Object?> get toolSchema => <String, Object?>{
        'name': 'generate_image',
        'description':
            'Generate an image from a text description using a free online image model.',
        'parameters': {
          'prompt': 'A detailed description of the image to generate (required).',
        },
      };

  /// Encodes [data] as compact JSON (helper for callers/logging).
  static String encode(Object? data) => jsonEncode(data);
}
