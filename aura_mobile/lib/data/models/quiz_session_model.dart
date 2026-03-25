import 'package:aura_mobile/domain/entities/quiz.dart';

class QuizSessionModel extends QuizSession {
  const QuizSessionModel({
    required super.id,
    required super.deckId,
    required super.quizType,
    super.totalQuestions,
    super.correctAnswers,
    super.wrongAnswers,
    required super.startedAt,
    super.completedAt,
  });

  factory QuizSessionModel.fromJson(Map<String, dynamic> json) {
    return QuizSessionModel(
      id: json['id'],
      deckId: json['deckId'],
      quizType: json['quizType'],
      totalQuestions: json['totalQuestions'] ?? 0,
      correctAnswers: json['correctAnswers'] ?? 0,
      wrongAnswers: json['wrongAnswers'] ?? 0,
      startedAt: DateTime.fromMillisecondsSinceEpoch(json['startedAt']),
      completedAt: json['completedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['completedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deckId': deckId,
      'quizType': quizType,
      'totalQuestions': totalQuestions,
      'correctAnswers': correctAnswers,
      'wrongAnswers': wrongAnswers,
      'startedAt': startedAt.millisecondsSinceEpoch,
      'completedAt': completedAt?.millisecondsSinceEpoch,
    };
  }

  factory QuizSessionModel.fromEntity(QuizSession session) {
    return QuizSessionModel(
      id: session.id,
      deckId: session.deckId,
      quizType: session.quizType,
      totalQuestions: session.totalQuestions,
      correctAnswers: session.correctAnswers,
      wrongAnswers: session.wrongAnswers,
      startedAt: session.startedAt,
      completedAt: session.completedAt,
    );
  }
}
