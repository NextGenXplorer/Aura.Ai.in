import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/domain/entities/quiz.dart';
import 'package:aura_mobile/domain/repositories/study_repository.dart';
import 'package:aura_mobile/domain/services/spaced_repetition_service.dart';

class QuizService {
  final StudyRepository _repository;
  static const _uuid = Uuid();
  final _random = Random();

  QuizService(this._repository);

  /// Generate quiz questions from a deck's flashcards
  Future<List<QuizQuestion>> generateQuiz(
    String deckId, {
    String type = 'mixed',
    int count = 10,
  }) async {
    final allCards = await _repository.getFlashcardsByDeck(deckId);
    if (allCards.isEmpty) return [];

    // Prioritize due cards first, then random
    final dueCards = await _repository.getDueFlashcards(deckId);
    final selectedCards = <Flashcard>[];

    // Add due cards first
    selectedCards.addAll(dueCards.take(count));

    // Fill remaining with random cards (avoid duplicates)
    if (selectedCards.length < count) {
      final remaining = allCards.where(
        (c) => !selectedCards.any((s) => s.id == c.id),
      ).toList()..shuffle(_random);
      selectedCards.addAll(remaining.take(count - selectedCards.length));
    }

    // Generate questions
    final questions = <QuizQuestion>[];
    for (final card in selectedCards) {
      final questionType = _resolveType(type);
      if (questionType == 'multiple_choice' && allCards.length >= 4) {
        questions.add(_createMultipleChoice(card, allCards));
      } else {
        questions.add(_createFillBlank(card));
      }
    }

    questions.shuffle(_random);
    return questions;
  }

  /// Create a new quiz session
  Future<QuizSession> createSession(String deckId, String quizType, int totalQuestions) async {
    final session = QuizSession(
      id: _uuid.v4(),
      deckId: deckId,
      quizType: quizType,
      totalQuestions: totalQuestions,
      startedAt: DateTime.now(),
    );
    await _repository.saveQuizSession(session);
    return session;
  }

  /// Record an answer and update SM-2 spaced repetition
  Future<void> recordAnswer({
    required String sessionId,
    required Flashcard card,
    required String userAnswer,
    required bool isCorrect,
    required int timeTakenMs,
  }) async {
    // Save the answer
    final answer = QuizAnswer(
      id: _uuid.v4(),
      sessionId: sessionId,
      flashcardId: card.id,
      userAnswer: userAnswer,
      isCorrect: isCorrect,
      timeTakenMs: timeTakenMs,
      answeredAt: DateTime.now(),
    );
    await _repository.saveQuizAnswer(answer);

    // Update SM-2 state
    final quality = isCorrect ? 4 : 1; // Good=4, Again=1
    final result = SpacedRepetitionService.calculate(
      quality: quality,
      easeFactor: card.easeFactor,
      interval: card.interval,
      repetitions: card.repetitions,
    );

    final updatedCard = card.copyWith(
      easeFactor: result.easeFactor,
      interval: result.interval,
      repetitions: result.repetitions,
      nextReviewDate: result.nextReviewDate,
    );
    await _repository.updateFlashcard(updatedCard);
  }

  /// Complete a quiz session with final scores
  Future<QuizSession> completeSession(
    QuizSession session, {
    required int correctAnswers,
    required int wrongAnswers,
  }) async {
    final completed = session.copyWith(
      correctAnswers: correctAnswers,
      wrongAnswers: wrongAnswers,
      completedAt: DateTime.now(),
    );
    await _repository.updateQuizSession(completed);
    return completed;
  }

  /// Get topic weakness analysis: topic -> accuracy percentage
  Future<Map<String, double>> getTopicWeaknesses(String deckId) async {
    final cards = await _repository.getFlashcardsByDeck(deckId);
    final topicStats = <String, List<bool>>{};

    for (final card in cards) {
      final topic = card.topic ?? 'General';
      final answers = await _repository.getAnswersByFlashcard(card.id);
      topicStats.putIfAbsent(topic, () => []);
      topicStats[topic]!.addAll(answers.map((a) => a.isCorrect));
    }

    final weaknesses = <String, double>{};
    topicStats.forEach((topic, results) {
      if (results.isNotEmpty) {
        final correct = results.where((r) => r).length;
        weaknesses[topic] = (correct / results.length) * 100;
      }
    });

    return weaknesses;
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  String _resolveType(String type) {
    if (type == 'mixed') {
      return _random.nextBool() ? 'multiple_choice' : 'fill_blank';
    }
    return type;
  }

  QuizQuestion _createMultipleChoice(Flashcard card, List<Flashcard> pool) {
    // Prefer distractors from same topic for harder, more realistic options
    final sameTopic = pool
        .where((c) => c.id != card.id && c.topic == card.topic)
        .toList()
      ..shuffle(_random);
    final otherCards = pool
        .where((c) => c.id != card.id && c.topic != card.topic)
        .toList()
      ..shuffle(_random);

    // Truncate long answers so options are readable
    String truncate(String s) => s.length > 100 ? '${s.substring(0, 100)}...' : s;

    final correctOption = truncate(card.back);
    final options = <String>[correctOption];

    // Add same-topic distractors first, then others
    for (final d in [...sameTopic, ...otherCards]) {
      final option = truncate(d.back);
      if (!options.contains(option) && option != correctOption) {
        options.add(option);
      }
      if (options.length >= 4) break;
    }

    // Pad if needed
    final fillers = ['None of the above', 'All of the above', 'Not enough information'];
    int fillerIdx = 0;
    while (options.length < 4 && fillerIdx < fillers.length) {
      if (!options.contains(fillers[fillerIdx])) {
        options.add(fillers[fillerIdx]);
      }
      fillerIdx++;
    }

    options.shuffle(_random);

    return QuizQuestion(
      flashcard: card,
      flashcardId: card.id,
      question: card.front,
      correctAnswer: correctOption,
      options: options,
      type: 'multiple_choice',
    );
  }

  QuizQuestion _createFillBlank(Flashcard card) {
    // For fill-in-blank, show a hint if the answer is very long
    // This makes it actually answerable
    String question = card.front;
    final answer = card.back;

    if (answer.length > 60) {
      // For long answers, add a hint showing the first letter and word count
      final words = answer.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final firstLetter = answer.isNotEmpty ? answer[0].toUpperCase() : '?';
      question = '$question\n(Hint: starts with "$firstLetter", ${words.length} words)';
    }

    return QuizQuestion(
      flashcard: card,
      flashcardId: card.id,
      question: question,
      correctAnswer: card.back,
      type: 'fill_blank',
    );
  }
}
