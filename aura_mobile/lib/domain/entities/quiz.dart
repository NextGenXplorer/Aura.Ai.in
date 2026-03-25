import 'package:equatable/equatable.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';

class QuizSession extends Equatable {
  final String id;
  final String deckId;
  final String quizType; // 'multiple_choice', 'fill_blank', 'mixed'
  final int totalQuestions;
  final int correctAnswers;
  final int wrongAnswers;
  final DateTime startedAt;
  final DateTime? completedAt;

  const QuizSession({
    required this.id,
    required this.deckId,
    required this.quizType,
    this.totalQuestions = 0,
    this.correctAnswers = 0,
    this.wrongAnswers = 0,
    required this.startedAt,
    this.completedAt,
  });

  QuizSession copyWith({
    String? id,
    String? deckId,
    String? quizType,
    int? totalQuestions,
    int? correctAnswers,
    int? wrongAnswers,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return QuizSession(
      id: id ?? this.id,
      deckId: deckId ?? this.deckId,
      quizType: quizType ?? this.quizType,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      wrongAnswers: wrongAnswers ?? this.wrongAnswers,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  double get scorePercentage =>
      totalQuestions > 0 ? (correctAnswers / totalQuestions) * 100 : 0;

  @override
  List<Object?> get props => [
        id, deckId, quizType, totalQuestions,
        correctAnswers, wrongAnswers, startedAt, completedAt,
      ];
}

class QuizAnswer extends Equatable {
  final String id;
  final String sessionId;
  final String flashcardId;
  final String userAnswer;
  final bool isCorrect;
  final int timeTakenMs;
  final DateTime answeredAt;

  const QuizAnswer({
    required this.id,
    required this.sessionId,
    required this.flashcardId,
    required this.userAnswer,
    required this.isCorrect,
    this.timeTakenMs = 0,
    required this.answeredAt,
  });

  @override
  List<Object?> get props => [
        id, sessionId, flashcardId, userAnswer,
        isCorrect, timeTakenMs, answeredAt,
      ];
}

/// Represents a single quiz question for the UI
class QuizQuestion {
  final Flashcard? flashcard; // null = not linked
  final String flashcardId;
  final String question;
  final String correctAnswer;
  final List<String>? options; // null = fill-in-the-blank
  final String type; // 'multiple_choice' or 'fill_blank'

  QuizQuestion({
    this.flashcard,
    required this.flashcardId,
    required this.question,
    required this.correctAnswer,
    this.options,
    required this.type,
  });
}
