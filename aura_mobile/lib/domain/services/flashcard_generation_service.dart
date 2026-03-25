import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';

/// Hybrid flashcard generation: LLM-powered when model is loaded,
/// rule-based fallback when offline or model unavailable.
class FlashcardGenerationService {
  static const _uuid = Uuid();

  /// Extract flashcards from raw text.
  /// Uses LLM when available for high-quality Q&A pairs,
  /// falls back to regex patterns otherwise.
  Future<List<Flashcard>> extractFromText(
    String text, {
    required String deckId,
    String? topic,
    LLMService? llmService,
  }) async {
    // Try LLM-powered generation first
    if (llmService != null && llmService.isModelLoaded) {
      try {
        final aiCards = await _generateWithLLM(text, deckId, topic, llmService);
        if (aiCards.isNotEmpty) {
          debugPrint('FLASHCARD_GEN: AI generated ${aiCards.length} cards');
          return aiCards;
        }
      } catch (e) {
        debugPrint('FLASHCARD_GEN: AI generation failed, falling back to regex: $e');
      }
    }

    // Fallback: rule-based extraction
    final cards = _extractWithRules(text, deckId, topic);
    debugPrint('FLASHCARD_GEN: Rule-based extracted ${cards.length} cards from ${text.length} chars');
    return cards;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LLM-POWERED GENERATION
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<Flashcard>> _generateWithLLM(
    String text,
    String deckId,
    String? topic,
    LLMService llmService,
  ) async {
    // Truncate very long text to fit context window (especially for 0.5B models)
    final isSmall = llmService.modelTier.isSmall;
    final maxChars = isSmall ? 800 : 2000;
    final truncatedText = text.length > maxChars ? text.substring(0, maxChars) : text;
    final cardCount = isSmall ? 5 : 8;

    final prompt = isSmall
        ? 'Read this text and create $cardCount flashcards.\n\n'
          'Text: "$truncatedText"\n\n'
          'Write each flashcard as:\n'
          'Q: (question)\n'
          'A: (short answer)\n\n'
          'Example:\n'
          'Q: What is photosynthesis?\n'
          'A: The process by which plants convert sunlight into energy.\n\n'
          'Now create $cardCount flashcards:'
        : 'Read the following text and generate $cardCount high-quality study flashcards from it.\n\n'
          'TEXT:\n"$truncatedText"\n\n'
          'RULES:\n'
          '- Each flashcard must test a key concept, definition, or fact from the text\n'
          '- Questions should be clear and specific\n'
          '- Answers should be concise (1-2 sentences max)\n'
          '- Do NOT make up information not in the text\n\n'
          'FORMAT (exactly like this):\n'
          'Q: What is the main function of mitochondria?\n'
          'A: To produce ATP (energy) for the cell through cellular respiration.\n\n'
          'Generate $cardCount flashcards:';

    final systemPrompt = isSmall
        ? 'Create flashcards. Use only Q: and A: format.'
        : 'You are a study assistant. Generate flashcards strictly from the provided text. '
          'Use only the Q:/A: format. Do not add information not in the text.';

    final buffer = StringBuffer();
    await for (final token in llmService.chat(
      prompt,
      systemPrompt: systemPrompt,
      maxTokens: isSmall ? 300 : 600,
      temperature: 0.3,
    )) {
      buffer.write(token);
    }

    return _parseLLMOutput(buffer.toString(), deckId, topic);
  }

  /// Parse LLM output in Q:/A: format into Flashcard objects.
  List<Flashcard> _parseLLMOutput(String output, String deckId, String? topic) {
    final cards = <Flashcard>[];
    final seen = <String>{};

    // Match Q: ... A: ... pairs (handles multiline)
    final qaPattern = RegExp(
      r'Q:\s*(.+?)(?:\n|\r\n?)A:\s*(.+?)(?=(?:\n|\r\n?)Q:|\n\n|$)',
      dotAll: true,
    );

    for (final match in qaPattern.allMatches(output)) {
      var question = match.group(1)?.trim() ?? '';
      var answer = match.group(2)?.trim() ?? '';

      // Clean up
      question = question.replaceAll(RegExp(r'\n+'), ' ').trim();
      answer = answer.replaceAll(RegExp(r'\n+'), ' ').trim();

      // Validate
      if (question.length < 5 || answer.length < 3) continue;
      if (question.length > 200) question = '${question.substring(0, 200)}...';
      if (answer.length > 300) answer = '${answer.substring(0, 300)}...';

      final key = question.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);

      cards.add(_createCard(
        deckId: deckId,
        front: question,
        back: answer,
        topic: topic,
        difficulty: 2,
      ));
    }

    return cards;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RULE-BASED FALLBACK
  // ══════════════════════════════════════════════════════════════════════════

  List<Flashcard> _extractWithRules(String text, String deckId, String? topic) {
    final cards = <Flashcard>[];
    final seen = <String>{};

    cards.addAll(_extractDefinitions(text, deckId, topic, seen));
    cards.addAll(_extractQAPairs(text, deckId, topic, seen));
    cards.addAll(_extractHeadingContent(text, deckId, topic, seen));
    cards.addAll(_extractListItems(text, deckId, topic, seen));
    cards.addAll(_extractKeyTerms(text, deckId, topic, seen));

    return cards;
  }

  /// Strategy 1: Definition patterns
  List<Flashcard> _extractDefinitions(String text, String deckId, String? topic, Set<String> seen) {
    final cards = <Flashcard>[];
    final patterns = [
      RegExp(r'([A-Z][^.!?]{3,50})\s+(?:is\s+defined\s+as|is\s+the\s+process\s+of|refers\s+to|means|is\s+known\s+as)\s+([^.!?]+[.!?])', caseSensitive: false),
      RegExp(r'^([A-Z][A-Za-z\s]{2,40})\s+is\s+((?:a|an|the)\s+[^.!?]{10,}[.!?])', multiLine: true),
      RegExp(r'^([A-Z][A-Za-z\s]{2,40}):\s+([^.!?]{15,}[.!?]?)', multiLine: true),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final term = match.group(1)?.trim() ?? '';
        final definition = match.group(2)?.trim() ?? '';
        if (term.length >= 3 && definition.length >= 10 && !seen.contains(term.toLowerCase())) {
          seen.add(term.toLowerCase());
          cards.add(_createCard(
            deckId: deckId,
            front: 'What is $term?',
            back: definition,
            topic: topic ?? _inferTopic(term),
            difficulty: 2,
          ));
        }
      }
    }
    return cards;
  }

  /// Strategy 2: Question-Answer pairs
  List<Flashcard> _extractQAPairs(String text, String deckId, String? topic, Set<String> seen) {
    final cards = <Flashcard>[];
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i];
      if (line.endsWith('?') && line.length >= 10) {
        final answer = lines[i + 1];
        if (answer.length >= 5 && !answer.endsWith('?')) {
          final key = line.toLowerCase();
          if (!seen.contains(key)) {
            seen.add(key);
            cards.add(_createCard(
              deckId: deckId,
              front: line,
              back: answer,
              topic: topic,
              difficulty: 2,
            ));
          }
        }
      }
    }
    return cards;
  }

  /// Strategy 3: Heading + content extraction
  List<Flashcard> _extractHeadingContent(String text, String deckId, String? topic, Set<String> seen) {
    final cards = <Flashcard>[];
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i];
      if (_isHeading(line)) {
        final contentLines = <String>[];
        for (int j = i + 1; j < lines.length && j < i + 6; j++) {
          if (_isHeading(lines[j])) break;
          contentLines.add(lines[j]);
        }
        final content = contentLines.join(' ').trim();
        if (content.length >= 20) {
          final heading = line.replaceAll(RegExp(r'[:#*]+$'), '').trim();
          final key = heading.toLowerCase();
          if (!seen.contains(key) && heading.length >= 3) {
            seen.add(key);
            cards.add(_createCard(
              deckId: deckId,
              front: 'Explain: $heading',
              back: content.length > 300 ? '${content.substring(0, 300)}...' : content,
              topic: topic ?? heading,
              difficulty: 2,
            ));
          }
        }
      }
    }
    return cards;
  }

  /// Strategy 4: Bullet points and numbered lists
  List<Flashcard> _extractListItems(String text, String deckId, String? topic, Set<String> seen) {
    final cards = <Flashcard>[];
    final listPattern = RegExp(r'^\s*(?:[-*•]\s+|\d+[.)]\s+)(.+)', multiLine: true);
    final lines = text.split('\n');
    String? currentHeading;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (_isHeading(line)) {
        currentHeading = line.replaceAll(RegExp(r'[:#*]+$'), '').trim();
        continue;
      }

      final match = listPattern.firstMatch(lines[i]);
      if (match != null && currentHeading != null) {
        final item = match.group(1)?.trim() ?? '';
        if (item.contains(' - ') || item.contains(': ')) {
          final parts = item.contains(' - ')
              ? item.split(' - ')
              : item.split(': ');
          if (parts.length >= 2 && parts[0].length >= 3 && parts[1].length >= 5) {
            final key = parts[0].trim().toLowerCase();
            if (!seen.contains(key)) {
              seen.add(key);
              cards.add(_createCard(
                deckId: deckId,
                front: 'What is ${parts[0].trim()}?',
                back: parts.sublist(1).join(': ').trim(),
                topic: topic ?? currentHeading,
                difficulty: 1,
              ));
            }
          }
        }
      }
    }
    return cards;
  }

  /// Strategy 5: Key term extraction
  List<Flashcard> _extractKeyTerms(String text, String deckId, String? topic, Set<String> seen) {
    final cards = <Flashcard>[];
    final quotePattern = RegExp(r'"([A-Za-z\s]{3,30})"\s+(?:is|means|refers\s+to|describes)\s+([^.!?]+[.!?])');
    for (final match in quotePattern.allMatches(text)) {
      final term = match.group(1)?.trim() ?? '';
      final definition = match.group(2)?.trim() ?? '';
      final key = term.toLowerCase();
      if (!seen.contains(key) && definition.length >= 10) {
        seen.add(key);
        cards.add(_createCard(
          deckId: deckId,
          front: 'Define: $term',
          back: definition,
          topic: topic,
          difficulty: 2,
        ));
      }
    }
    return cards;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool _isHeading(String line) {
    if (line.length > 80 || line.length < 3) return false;
    if (line == line.toUpperCase() && RegExp(r'[A-Z]').hasMatch(line)) return true;
    if (line.endsWith(':') && line.length < 60) return true;
    if (line.startsWith('#')) return true;
    if (RegExp(r'^\d+[.)]\s+[A-Z]').hasMatch(line) && line.length < 60) return true;
    return false;
  }

  String? _inferTopic(String term) {
    if (term.length < 3) return null;
    final words = term.split(' ');
    return words.length > 1 ? words.first : term;
  }

  Flashcard _createCard({
    required String deckId,
    required String front,
    required String back,
    String? topic,
    int difficulty = 2,
  }) {
    return Flashcard(
      id: _uuid.v4(),
      deckId: deckId,
      front: front,
      back: back,
      topic: topic,
      difficulty: difficulty,
      createdAt: DateTime.now(),
    );
  }
}
