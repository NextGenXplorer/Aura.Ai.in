import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'aura_mobile.db');

    return await openDatabase(
      path,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE memories(
        id TEXT PRIMARY KEY,
        content TEXT,
        category TEXT,
        timestamp INTEGER,
        embedding TEXT,
        eventDate INTEGER,
        eventTime TEXT,
        reminderScheduled INTEGER DEFAULT 0
      )
    ''');
    
    // New Schema for Documents (Split into documents and chunks)
    await db.execute('''
      CREATE TABLE documents(
        id TEXT PRIMARY KEY,
        filename TEXT,
        path TEXT,
        uploadDate INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE document_chunks(
        id TEXT PRIMARY KEY,
        documentId TEXT,
        content TEXT,
        chunkIndex INTEGER,
        embedding TEXT,
        FOREIGN KEY(documentId) REFERENCES documents(id) ON DELETE CASCADE
      )
    ''');

    // Study Buddy tables
    await _createStudyTables(db);

    // Automation rules table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS automation_rules(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        triggerType TEXT NOT NULL,
        scheduledTime INTEGER,
        repeatIntervalMinutes INTEGER,
        condition TEXT,
        checkIntervalMinutes INTEGER DEFAULT 60,
        actionInstruction TEXT NOT NULL,
        actionJson TEXT,
        isEnabled INTEGER DEFAULT 1,
        lastExecutedAt INTEGER,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createStudyTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS flashcard_decks(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sourceDocumentId TEXT,
        description TEXT,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        FOREIGN KEY(sourceDocumentId) REFERENCES documents(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS flashcards(
        id TEXT PRIMARY KEY,
        deckId TEXT NOT NULL,
        front TEXT NOT NULL,
        back TEXT NOT NULL,
        topic TEXT,
        difficulty INTEGER DEFAULT 2,
        easeFactor REAL DEFAULT 2.5,
        interval INTEGER DEFAULT 0,
        repetitions INTEGER DEFAULT 0,
        nextReviewDate INTEGER,
        createdAt INTEGER NOT NULL,
        FOREIGN KEY(deckId) REFERENCES flashcard_decks(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quiz_sessions(
        id TEXT PRIMARY KEY,
        deckId TEXT NOT NULL,
        quizType TEXT NOT NULL,
        totalQuestions INTEGER DEFAULT 0,
        correctAnswers INTEGER DEFAULT 0,
        wrongAnswers INTEGER DEFAULT 0,
        startedAt INTEGER NOT NULL,
        completedAt INTEGER,
        FOREIGN KEY(deckId) REFERENCES flashcard_decks(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quiz_answers(
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        flashcardId TEXT NOT NULL,
        userAnswer TEXT NOT NULL,
        isCorrect INTEGER DEFAULT 0,
        timeTakenMs INTEGER DEFAULT 0,
        answeredAt INTEGER NOT NULL,
        FOREIGN KEY(sessionId) REFERENCES quiz_sessions(id) ON DELETE CASCADE,
        FOREIGN KEY(flashcardId) REFERENCES flashcards(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS exam_schedules(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        deckId TEXT,
        examDate INTEGER NOT NULL,
        notes TEXT,
        createdAt INTEGER NOT NULL,
        FOREIGN KEY(deckId) REFERENCES flashcard_decks(id) ON DELETE SET NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns for notification support
      await db.execute('ALTER TABLE memories ADD COLUMN eventDate INTEGER');
      await db.execute('ALTER TABLE memories ADD COLUMN eventTime TEXT');
      await db.execute('ALTER TABLE memories ADD COLUMN reminderScheduled INTEGER DEFAULT 0');
    }

    if (oldVersion < 3) {
      // Migration to normalized document schema
      // Drop old table if exists (since schema changed drastically)
      await db.execute('DROP TABLE IF EXISTS documents');
      
      await db.execute('''
        CREATE TABLE documents(
          id TEXT PRIMARY KEY,
          filename TEXT,
          path TEXT,
          uploadDate INTEGER
        )
      ''');

      await db.execute('''
        CREATE TABLE document_chunks(
          id TEXT PRIMARY KEY,
          documentId TEXT,
          content TEXT,
          chunkIndex INTEGER,
          embedding TEXT,
          FOREIGN KEY(documentId) REFERENCES documents(id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 4) {
      await _createStudyTables(db);
    }

    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS automation_rules(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          triggerType TEXT NOT NULL,
          scheduledTime INTEGER,
          repeatIntervalMinutes INTEGER,
          condition TEXT,
          checkIntervalMinutes INTEGER DEFAULT 60,
          actionInstruction TEXT NOT NULL,
          isEnabled INTEGER DEFAULT 1,
          lastExecutedAt INTEGER,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        )
      ''');
    }

    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE automation_rules ADD COLUMN actionJson TEXT');
      } catch (e) {
        // Safe guard in case column already exists
      }
    }
  }
}
