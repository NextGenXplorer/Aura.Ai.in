import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/domain/entities/quiz.dart';
import 'package:aura_mobile/domain/entities/exam_schedule.dart';
import 'package:aura_mobile/domain/repositories/study_repository.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/flashcard_generation_service.dart';
import 'package:aura_mobile/domain/services/quiz_service.dart';
import 'package:aura_mobile/domain/services/spaced_repetition_service.dart';
import 'package:aura_mobile/domain/services/revision_scheduler_service.dart';
import 'package:aura_mobile/domain/services/document_service.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';
import 'package:aura_mobile/core/providers/study_providers.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';

final studyServiceProvider = Provider((ref) => StudyService(
      ref.read(studyRepositoryImplProvider),
      FlashcardGenerationService(),
      QuizService(ref.read(studyRepositoryImplProvider)),
      ref.read(documentServiceProvider),
      ref.read(llmServiceProvider),
    ));

class StudyService {
  final StudyRepository _repository;
  final FlashcardGenerationService _flashcardGen;
  final QuizService _quizService;
  // Reserved for future PDF-to-flashcard generation
  // ignore: unused_field
  final DocumentService _documentService;
  final LLMService _llmService;
  final ErrorHandlerService _errorHandler = ErrorHandlerService();
  static const _uuid = Uuid();

  StudyService(this._repository, this._flashcardGen, this._quizService, this._documentService, this._llmService);

  // ══════════════════════════════════════════════════════════════════════════
  // DECK MANAGEMENT
  // ══════════════════════════════════════════════════════════════════════════

  /// Create a deck from an uploaded document's text
  Future<FlashcardDeck> createDeckFromDocumentText(String text, {String? name, String? documentId}) async {
    try {
      final deckId = _uuid.v4();
      final deckName = name ?? 'Study Deck ${DateTime.now().day}/${DateTime.now().month}';

      final deck = FlashcardDeck(
        id: deckId,
        name: deckName,
        sourceDocumentId: documentId,
        description: 'Auto-generated from document',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _repository.saveDeck(deck);

      // Generate flashcards from text (AI-powered when model is loaded)
      final cards = await _flashcardGen.extractFromText(
        text,
        deckId: deckId,
        llmService: _llmService,
      );
      if (cards.isNotEmpty) {
        await _repository.saveFlashcards(cards);
      }

      debugPrint('STUDY: Created deck "$deckName" with ${cards.length} cards');
      return deck;
    } catch (e) {
      _errorHandler.logWarning('Failed to create deck from document: $e');
      rethrow;
    }
  }

  /// Create an empty deck for manual card creation
  Future<FlashcardDeck> createEmptyDeck(String name, {String? description}) async {
    final deck = FlashcardDeck(
      id: _uuid.v4(),
      name: name,
      description: description,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _repository.saveDeck(deck);
    return deck;
  }

  /// Add a single flashcard to a deck
  Future<Flashcard> addCard(String deckId, String front, String back, {String? topic}) async {
    final card = Flashcard(
      id: _uuid.v4(),
      deckId: deckId,
      front: front,
      back: back,
      topic: topic,
      createdAt: DateTime.now(),
    );
    await _repository.saveFlashcard(card);

    // Update deck timestamp
    final deck = await _repository.getDeckById(deckId);
    if (deck != null) {
      await _repository.updateDeck(deck.copyWith(updatedAt: DateTime.now()));
    }

    return card;
  }

  Future<List<FlashcardDeck>> getAllDecks() => _repository.getAllDecks();
  Future<FlashcardDeck?> getDeckById(String id) => _repository.getDeckById(id);
  Future<void> deleteDeck(String id) => _repository.deleteDeck(id);
  Future<List<Flashcard>> getFlashcardsByDeck(String deckId) => _repository.getFlashcardsByDeck(deckId);
  Future<int> getCardCount(String deckId) => _repository.getCardCount(deckId);

  // ══════════════════════════════════════════════════════════════════════════
  // SPACED REPETITION REVIEW
  // ══════════════════════════════════════════════════════════════════════════

  /// Get cards due for review in a deck
  Future<List<Flashcard>> getDueCards(String deckId) => _repository.getDueFlashcards(deckId);

  /// Review a card with SM-2 rating
  Future<Flashcard> reviewCard(String cardId, String rating) async {
    // Find the card across all decks
    Flashcard? card;
    final allDecks = await _repository.getAllDecks();
    for (final deck in allDecks) {
      final deckCards = await _repository.getFlashcardsByDeck(deck.id);
      card = deckCards.where((c) => c.id == cardId).firstOrNull;
      if (card != null) break;
    }

    if (card == null) throw Exception('Card not found: $cardId');

    final quality = SpacedRepetitionService.buttonToQuality(rating);
    final result = SpacedRepetitionService.calculate(
      quality: quality,
      easeFactor: card.easeFactor,
      interval: card.interval,
      repetitions: card.repetitions,
    );

    final updated = card.copyWith(
      easeFactor: result.easeFactor,
      interval: result.interval,
      repetitions: result.repetitions,
      nextReviewDate: result.nextReviewDate,
    );
    await _repository.updateFlashcard(updated);
    return updated;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // QUIZ
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<QuizQuestion>> generateQuiz(String deckId, {String type = 'mixed', int count = 10}) =>
      _quizService.generateQuiz(deckId, type: type, count: count);

  Future<QuizSession> createQuizSession(String deckId, String type, int totalQuestions) =>
      _quizService.createSession(deckId, type, totalQuestions);

  Future<void> recordQuizAnswer({
    required String sessionId,
    required Flashcard card,
    required String userAnswer,
    required bool isCorrect,
    required int timeTakenMs,
  }) =>
      _quizService.recordAnswer(
        sessionId: sessionId,
        card: card,
        userAnswer: userAnswer,
        isCorrect: isCorrect,
        timeTakenMs: timeTakenMs,
      );

  Future<QuizSession> completeQuizSession(QuizSession session, {required int correct, required int wrong}) =>
      _quizService.completeSession(session, correctAnswers: correct, wrongAnswers: wrong);

  Future<List<QuizSession>> getQuizHistory(String deckId) =>
      _repository.getQuizSessionsByDeck(deckId);

  // ══════════════════════════════════════════════════════════════════════════
  // EXAM SCHEDULING
  // ══════════════════════════════════════════════════════════════════════════

  Future<ExamSchedule> scheduleExam(String name, DateTime date, {String? deckId, String? notes}) async {
    final exam = ExamSchedule(
      id: _uuid.v4(),
      name: name,
      deckId: deckId,
      examDate: date,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await _repository.saveExamSchedule(exam);
    return exam;
  }

  Future<List<ExamSchedule>> getUpcomingExams() => _repository.getUpcomingExams();
  Future<List<ExamSchedule>> getAllExams() => _repository.getAllExamSchedules();
  Future<void> deleteExam(String id) => _repository.deleteExamSchedule(id);

  List<DateTime> getRevisionSchedule(DateTime examDate) =>
      RevisionSchedulerService.generateRevisionSchedule(examDate);

  StudyIntensity getStudyIntensity(int daysRemaining) =>
      RevisionSchedulerService.getStudyIntensity(daysRemaining);

  // ══════════════════════════════════════════════════════════════════════════
  // ANALYTICS
  // ══════════════════════════════════════════════════════════════════════════

  /// Get comprehensive stats for a deck
  Future<DeckStats> getDeckStats(String deckId) async {
    final cards = await _repository.getFlashcardsByDeck(deckId);
    final dueCards = await _repository.getDueFlashcards(deckId);
    final sessions = await _repository.getQuizSessionsByDeck(deckId);

    final mastered = cards.where((c) => c.repetitions >= 3 && c.easeFactor >= 2.5).length;
    final learning = cards.where((c) => c.repetitions > 0 && c.repetitions < 3).length;
    final newCards = cards.where((c) => c.repetitions == 0).length;

    double avgScore = 0;
    if (sessions.isNotEmpty) {
      avgScore = sessions
          .where((s) => s.completedAt != null)
          .map((s) => s.scorePercentage)
          .fold(0.0, (a, b) => a + b);
      final completed = sessions.where((s) => s.completedAt != null).length;
      if (completed > 0) avgScore /= completed;
    }

    return DeckStats(
      totalCards: cards.length,
      masteredCards: mastered,
      learningCards: learning,
      newCards: newCards,
      dueCards: dueCards.length,
      totalQuizzes: sessions.length,
      averageScore: avgScore,
      masteryPercentage: cards.isNotEmpty ? (mastered / cards.length) * 100 : 0,
    );
  }

  /// Get topic weakness map
  Future<Map<String, double>> getTopicWeaknesses(String deckId) =>
      _quizService.getTopicWeaknesses(deckId);
}

class DeckStats {
  final int totalCards;
  final int masteredCards;
  final int learningCards;
  final int newCards;
  final int dueCards;
  final int totalQuizzes;
  final double averageScore;
  final double masteryPercentage;

  const DeckStats({
    required this.totalCards,
    required this.masteredCards,
    required this.learningCards,
    required this.newCards,
    required this.dueCards,
    required this.totalQuizzes,
    required this.averageScore,
    required this.masteryPercentage,
  });
}
