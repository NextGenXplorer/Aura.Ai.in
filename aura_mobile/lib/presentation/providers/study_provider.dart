import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/domain/entities/quiz.dart';
import 'package:aura_mobile/domain/entities/exam_schedule.dart';
import 'package:aura_mobile/domain/services/study_service.dart';
import 'package:aura_mobile/features/daily_briefing/home_widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final studyProvider = StateNotifierProvider<StudyNotifier, StudyState>((ref) {
  return StudyNotifier(ref.read(studyServiceProvider));
});

class StudyState {
  final List<FlashcardDeck> decks;
  final List<ExamSchedule> upcomingExams;
  final bool isLoading;
  final String? error;
  final FlashcardDeck? activeDeck;
  final List<Flashcard> currentCards;
  final List<Flashcard> reviewQueue;
  final DeckStats? activeStats;

  // Quiz state
  final QuizSession? activeQuiz;
  final List<QuizQuestion> quizQuestions;
  final int currentQuizIndex;
  final int quizCorrect;
  final int quizWrong;

  const StudyState({
    this.decks = const [],
    this.upcomingExams = const [],
    this.isLoading = false,
    this.error,
    this.activeDeck,
    this.currentCards = const [],
    this.reviewQueue = const [],
    this.activeStats,
    this.activeQuiz,
    this.quizQuestions = const [],
    this.currentQuizIndex = 0,
    this.quizCorrect = 0,
    this.quizWrong = 0,
  });

  StudyState copyWith({
    List<FlashcardDeck>? decks,
    List<ExamSchedule>? upcomingExams,
    bool? isLoading,
    String? error,
    FlashcardDeck? activeDeck,
    List<Flashcard>? currentCards,
    List<Flashcard>? reviewQueue,
    DeckStats? activeStats,
    QuizSession? activeQuiz,
    List<QuizQuestion>? quizQuestions,
    int? currentQuizIndex,
    int? quizCorrect,
    int? quizWrong,
  }) {
    return StudyState(
      decks: decks ?? this.decks,
      upcomingExams: upcomingExams ?? this.upcomingExams,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      activeDeck: activeDeck ?? this.activeDeck,
      currentCards: currentCards ?? this.currentCards,
      reviewQueue: reviewQueue ?? this.reviewQueue,
      activeStats: activeStats ?? this.activeStats,
      activeQuiz: activeQuiz ?? this.activeQuiz,
      quizQuestions: quizQuestions ?? this.quizQuestions,
      currentQuizIndex: currentQuizIndex ?? this.currentQuizIndex,
      quizCorrect: quizCorrect ?? this.quizCorrect,
      quizWrong: quizWrong ?? this.quizWrong,
    );
  }
}

class StudyNotifier extends StateNotifier<StudyState> {
  final StudyService _studyService;

  StudyNotifier(this._studyService) : super(const StudyState());

  /// Load all decks and upcoming exams
  Future<void> loadDashboard() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final decks = await _studyService.getAllDecks();
      final exams = await _studyService.getUpcomingExams();
      state = state.copyWith(
        decks: decks,
        upcomingExams: exams,
        isLoading: false,
      );
      _syncHomeWidget();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Pushes the current study numbers to the home screen widget.
  ///
  /// Fire-and-forget: the widget is a nicety and must never delay or fail a
  /// study action.
  void _syncHomeWidget() {
    Future(() async {
      try {
        final decks = state.decks;

        // Due counts are stored per deck, so the dashboard total is a sum. Deck
        // counts are small, and this runs off the UI path.
        var due = 0;
        for (final deck in decks) {
          due += (await _studyService.getDueCards(deck.id)).length;
        }

        final prefs = await SharedPreferences.getInstance();
        final streak = prefs.getInt('proactive_study_streak') ?? 0;

        final exams = state.upcomingExams;
        final nextExam = exams.isEmpty ? null : exams.first;

        await HomeWidgetService.updateStudyData(
          dueCards: due,
          streakDays: streak,
          deckCount: decks.length,
          nextExamName: nextExam?.name,
          nextExamDays: nextExam?.daysRemaining,
        );
      } catch (e) {
        debugPrint('STUDY: widget sync failed: $e');
      }
    });
  }

  /// Create a deck from document text
  Future<FlashcardDeck?> createDeckFromText(String text, {String? name}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final deck = await _studyService.createDeckFromDocumentText(
        text,
        name: name,
      );
      await loadDashboard();
      return deck;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  /// Create an empty deck
  Future<FlashcardDeck?> createEmptyDeck(
    String name, {
    String? description,
  }) async {
    try {
      final deck = await _studyService.createEmptyDeck(
        name,
        description: description,
      );
      await loadDashboard();
      return deck;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Select a deck and load its cards + stats
  Future<void> selectDeck(FlashcardDeck deck) async {
    state = state.copyWith(isLoading: true, activeDeck: deck);
    try {
      final cards = await _studyService.getFlashcardsByDeck(deck.id);
      final dueCards = await _studyService.getDueCards(deck.id);
      final stats = await _studyService.getDeckStats(deck.id);
      state = state.copyWith(
        currentCards: cards,
        reviewQueue: dueCards,
        activeStats: stats,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Add a card to the active deck
  Future<void> addCard(String front, String back, {String? topic}) async {
    if (state.activeDeck == null) return;
    try {
      await _studyService.addCard(
        state.activeDeck!.id,
        front,
        back,
        topic: topic,
      );
      await selectDeck(state.activeDeck!);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Delete a deck
  Future<void> deleteDeck(String deckId) async {
    try {
      await _studyService.deleteDeck(deckId);
      await loadDashboard();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Review a card with SM-2 rating
  Future<void> reviewCard(String cardId, String rating) async {
    try {
      await _studyService.reviewCard(cardId, rating);
      // Remove from review queue
      final updatedQueue = state.reviewQueue
          .where((c) => c.id != cardId)
          .toList();
      state = state.copyWith(reviewQueue: updatedQueue);
      _syncHomeWidget();
    } catch (e) {
      debugPrint('STUDY: Review error: $e');
    }
  }

  // ── Quiz Methods ─────────────────────────────────────────────────────────

  /// Start a quiz for the active deck
  Future<void> startQuiz({String type = 'mixed', int count = 10}) async {
    if (state.activeDeck == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final questions = await _studyService.generateQuiz(
        state.activeDeck!.id,
        type: type,
        count: count,
      );
      if (questions.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'Not enough cards for a quiz',
        );
        return;
      }
      final session = await _studyService.createQuizSession(
        state.activeDeck!.id,
        type,
        questions.length,
      );
      state = state.copyWith(
        activeQuiz: session,
        quizQuestions: questions,
        currentQuizIndex: 0,
        quizCorrect: 0,
        quizWrong: 0,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Answer the current quiz question
  Future<void> answerQuizQuestion(
    String answer, {
    required int timeTakenMs,
  }) async {
    if (state.activeQuiz == null ||
        state.currentQuizIndex >= state.quizQuestions.length)
      return;

    final question = state.quizQuestions[state.currentQuizIndex];
    final isCorrect = question.type == 'multiple_choice'
        ? answer.trim().toLowerCase() ==
              question.correctAnswer.trim().toLowerCase()
        : _fuzzyMatch(answer, question.correctAnswer);

    if (question.flashcard != null) {
      await _studyService.recordQuizAnswer(
        sessionId: state.activeQuiz!.id,
        card: question.flashcard!,
        userAnswer: answer,
        isCorrect: isCorrect,
        timeTakenMs: timeTakenMs,
      );
    }

    final newCorrect = state.quizCorrect + (isCorrect ? 1 : 0);
    final newWrong = state.quizWrong + (isCorrect ? 0 : 1);
    final nextIndex = state.currentQuizIndex + 1;

    state = state.copyWith(
      currentQuizIndex: nextIndex,
      quizCorrect: newCorrect,
      quizWrong: newWrong,
    );

    // Auto-complete if last question
    if (nextIndex >= state.quizQuestions.length) {
      await completeQuiz();
    }
  }

  /// Complete the active quiz
  Future<void> completeQuiz() async {
    if (state.activeQuiz == null) return;
    try {
      await _studyService.completeQuizSession(
        state.activeQuiz!,
        correct: state.quizCorrect,
        wrong: state.quizWrong,
      );
    } catch (e) {
      debugPrint('STUDY: Quiz completion error: $e');
    }
  }

  /// Clear quiz state
  void clearQuiz() {
    state = state.copyWith(
      activeQuiz: null,
      quizQuestions: const [],
      currentQuizIndex: 0,
      quizCorrect: 0,
      quizWrong: 0,
    );
  }

  /// Fuzzy matching for fill-in-the-blank answers.
  /// Considers the answer correct if:
  /// - Exact match (case-insensitive)
  /// - User's answer contains 60%+ of the key words from the correct answer
  /// - Correct answer contains the user's answer as a substring
  bool _fuzzyMatch(String userAnswer, String correctAnswer) {
    final userLower = userAnswer.trim().toLowerCase();
    final correctLower = correctAnswer.trim().toLowerCase();

    // 1. Exact match
    if (userLower == correctLower) return true;

    // 2. One contains the other
    if (correctLower.contains(userLower) && userLower.length >= 3) return true;
    if (userLower.contains(correctLower)) return true;

    // 3. Keyword matching — extract meaningful words (3+ chars, not stopwords)
    final stopWords = {
      'the',
      'a',
      'an',
      'is',
      'are',
      'was',
      'were',
      'of',
      'in',
      'to',
      'for',
      'and',
      'or',
      'but',
      'that',
      'this',
      'with',
      'from',
      'by',
      'on',
      'at',
      'it',
      'its',
      'as',
    };

    List<String> extractKeywords(String text) {
      return text
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 3 && !stopWords.contains(w))
          .toList();
    }

    final correctKeywords = extractKeywords(correctLower);
    final userKeywords = extractKeywords(userLower);

    if (correctKeywords.isEmpty) return false;

    // Count how many correct keywords appear in user's answer
    int matched = 0;
    for (final keyword in correctKeywords) {
      if (userKeywords.any(
        (uk) => uk == keyword || keyword.contains(uk) || uk.contains(keyword),
      )) {
        matched++;
      }
    }

    final matchRatio = matched / correctKeywords.length;
    return matchRatio >= 0.6; // 60% keyword match = correct
  }

  // ── Exam Methods ─────────────────────────────────────────────────────────

  Future<void> scheduleExam(
    String name,
    DateTime date, {
    String? deckId,
  }) async {
    try {
      await _studyService.scheduleExam(name, date, deckId: deckId);
      await loadDashboard();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteExam(String id) async {
    try {
      await _studyService.deleteExam(id);
      await loadDashboard();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}
