import 'package:aura_mobile/data/datasources/database_helper.dart';
import 'package:aura_mobile/data/models/flashcard_deck_model.dart';
import 'package:aura_mobile/data/models/flashcard_model.dart';
import 'package:aura_mobile/data/models/quiz_session_model.dart';
import 'package:aura_mobile/data/models/quiz_answer_model.dart';
import 'package:aura_mobile/data/models/exam_schedule_model.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/domain/entities/quiz.dart';
import 'package:aura_mobile/domain/entities/exam_schedule.dart';
import 'package:aura_mobile/domain/repositories/study_repository.dart';
import 'package:sqflite/sqflite.dart';

class StudyRepositoryImpl implements StudyRepository {
  final DatabaseHelper _databaseHelper;

  StudyRepositoryImpl(this._databaseHelper);

  // ── Deck CRUD ──────────────────────────────────────────────────────────────

  @override
  Future<void> saveDeck(FlashcardDeck deck) async {
    final db = await _databaseHelper.database;
    await db.insert(
      'flashcard_decks',
      FlashcardDeckModel.fromEntity(deck).toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<FlashcardDeck>> getAllDecks() async {
    final db = await _databaseHelper.database;
    final maps = await db.query('flashcard_decks', orderBy: 'updatedAt DESC');
    return maps.map((m) => FlashcardDeckModel.fromJson(m)).toList();
  }

  @override
  Future<FlashcardDeck?> getDeckById(String id) async {
    final db = await _databaseHelper.database;
    final maps = await db.query('flashcard_decks', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return FlashcardDeckModel.fromJson(maps.first);
  }

  @override
  Future<void> updateDeck(FlashcardDeck deck) async {
    final db = await _databaseHelper.database;
    await db.update(
      'flashcard_decks',
      FlashcardDeckModel.fromEntity(deck).toJson(),
      where: 'id = ?',
      whereArgs: [deck.id],
    );
  }

  @override
  Future<void> deleteDeck(String id) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      // Delete quiz answers for sessions in this deck
      final sessions = await txn.query('quiz_sessions', where: 'deckId = ?', whereArgs: [id]);
      for (final session in sessions) {
        await txn.delete('quiz_answers', where: 'sessionId = ?', whereArgs: [session['id']]);
      }
      await txn.delete('quiz_sessions', where: 'deckId = ?', whereArgs: [id]);
      await txn.delete('flashcards', where: 'deckId = ?', whereArgs: [id]);
      await txn.delete('flashcard_decks', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ── Flashcard CRUD ─────────────────────────────────────────────────────────

  @override
  Future<void> saveFlashcard(Flashcard card) async {
    final db = await _databaseHelper.database;
    await db.insert(
      'flashcards',
      FlashcardModel.fromEntity(card).toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> saveFlashcards(List<Flashcard> cards) async {
    final db = await _databaseHelper.database;
    final batch = db.batch();
    for (var card in cards) {
      batch.insert(
        'flashcards',
        FlashcardModel.fromEntity(card).toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<List<Flashcard>> getFlashcardsByDeck(String deckId) async {
    final db = await _databaseHelper.database;
    final maps = await db.query(
      'flashcards',
      where: 'deckId = ?',
      whereArgs: [deckId],
      orderBy: 'createdAt ASC',
    );
    return maps.map((m) => FlashcardModel.fromJson(m)).toList();
  }

  @override
  Future<List<Flashcard>> getDueFlashcards(String deckId) async {
    final db = await _databaseHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final maps = await db.query(
      'flashcards',
      where: 'deckId = ? AND (nextReviewDate IS NULL OR nextReviewDate <= ?)',
      whereArgs: [deckId, now],
      orderBy: 'nextReviewDate ASC',
    );
    return maps.map((m) => FlashcardModel.fromJson(m)).toList();
  }

  @override
  Future<void> updateFlashcard(Flashcard card) async {
    final db = await _databaseHelper.database;
    await db.update(
      'flashcards',
      FlashcardModel.fromEntity(card).toJson(),
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  @override
  Future<void> deleteFlashcard(String id) async {
    final db = await _databaseHelper.database;
    await db.delete('flashcards', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<int> getCardCount(String deckId) async {
    final db = await _databaseHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM flashcards WHERE deckId = ?',
      [deckId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ── Quiz CRUD ──────────────────────────────────────────────────────────────

  @override
  Future<void> saveQuizSession(QuizSession session) async {
    final db = await _databaseHelper.database;
    await db.insert(
      'quiz_sessions',
      QuizSessionModel.fromEntity(session).toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> updateQuizSession(QuizSession session) async {
    final db = await _databaseHelper.database;
    await db.update(
      'quiz_sessions',
      QuizSessionModel.fromEntity(session).toJson(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  @override
  Future<void> saveQuizAnswer(QuizAnswer answer) async {
    final db = await _databaseHelper.database;
    await db.insert(
      'quiz_answers',
      QuizAnswerModel.fromEntity(answer).toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<QuizSession>> getQuizSessionsByDeck(String deckId) async {
    final db = await _databaseHelper.database;
    final maps = await db.query(
      'quiz_sessions',
      where: 'deckId = ?',
      whereArgs: [deckId],
      orderBy: 'startedAt DESC',
    );
    return maps.map((m) => QuizSessionModel.fromJson(m)).toList();
  }

  @override
  Future<List<QuizAnswer>> getAnswersBySession(String sessionId) async {
    final db = await _databaseHelper.database;
    final maps = await db.query(
      'quiz_answers',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'answeredAt ASC',
    );
    return maps.map((m) => QuizAnswerModel.fromJson(m)).toList();
  }

  @override
  Future<List<QuizAnswer>> getAnswersByFlashcard(String flashcardId) async {
    final db = await _databaseHelper.database;
    final maps = await db.query(
      'quiz_answers',
      where: 'flashcardId = ?',
      whereArgs: [flashcardId],
      orderBy: 'answeredAt DESC',
    );
    return maps.map((m) => QuizAnswerModel.fromJson(m)).toList();
  }

  // ── Exam Schedule CRUD ─────────────────────────────────────────────────────

  @override
  Future<void> saveExamSchedule(ExamSchedule schedule) async {
    final db = await _databaseHelper.database;
    await db.insert(
      'exam_schedules',
      ExamScheduleModel.fromEntity(schedule).toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<ExamSchedule>> getAllExamSchedules() async {
    final db = await _databaseHelper.database;
    final maps = await db.query('exam_schedules', orderBy: 'examDate ASC');
    return maps.map((m) => ExamScheduleModel.fromJson(m)).toList();
  }

  @override
  Future<List<ExamSchedule>> getUpcomingExams() async {
    final db = await _databaseHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final maps = await db.query(
      'exam_schedules',
      where: 'examDate >= ?',
      whereArgs: [now],
      orderBy: 'examDate ASC',
    );
    return maps.map((m) => ExamScheduleModel.fromJson(m)).toList();
  }

  @override
  Future<void> deleteExamSchedule(String id) async {
    final db = await _databaseHelper.database;
    await db.delete('exam_schedules', where: 'id = ?', whereArgs: [id]);
  }
}
