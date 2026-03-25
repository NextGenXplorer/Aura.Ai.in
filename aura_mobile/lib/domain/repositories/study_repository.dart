import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/domain/entities/quiz.dart';
import 'package:aura_mobile/domain/entities/exam_schedule.dart';

abstract class StudyRepository {
  // Deck CRUD
  Future<void> saveDeck(FlashcardDeck deck);
  Future<List<FlashcardDeck>> getAllDecks();
  Future<FlashcardDeck?> getDeckById(String id);
  Future<void> deleteDeck(String id);
  Future<void> updateDeck(FlashcardDeck deck);

  // Flashcard CRUD
  Future<void> saveFlashcard(Flashcard card);
  Future<void> saveFlashcards(List<Flashcard> cards);
  Future<List<Flashcard>> getFlashcardsByDeck(String deckId);
  Future<List<Flashcard>> getDueFlashcards(String deckId);
  Future<void> updateFlashcard(Flashcard card);
  Future<void> deleteFlashcard(String id);
  Future<int> getCardCount(String deckId);

  // Quiz CRUD
  Future<void> saveQuizSession(QuizSession session);
  Future<void> updateQuizSession(QuizSession session);
  Future<void> saveQuizAnswer(QuizAnswer answer);
  Future<List<QuizSession>> getQuizSessionsByDeck(String deckId);
  Future<List<QuizAnswer>> getAnswersBySession(String sessionId);
  Future<List<QuizAnswer>> getAnswersByFlashcard(String flashcardId);

  // Exam Schedule CRUD
  Future<void> saveExamSchedule(ExamSchedule schedule);
  Future<List<ExamSchedule>> getAllExamSchedules();
  Future<List<ExamSchedule>> getUpcomingExams();
  Future<void> deleteExamSchedule(String id);
}
