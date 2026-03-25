import 'package:aura_mobile/domain/entities/quiz.dart';

class QuizAnswerModel extends QuizAnswer {
  const QuizAnswerModel({
    required super.id,
    required super.sessionId,
    required super.flashcardId,
    required super.userAnswer,
    required super.isCorrect,
    super.timeTakenMs,
    required super.answeredAt,
  });

  factory QuizAnswerModel.fromJson(Map<String, dynamic> json) {
    return QuizAnswerModel(
      id: json['id'],
      sessionId: json['sessionId'],
      flashcardId: json['flashcardId'],
      userAnswer: json['userAnswer'],
      isCorrect: json['isCorrect'] == 1,
      timeTakenMs: json['timeTakenMs'] ?? 0,
      answeredAt: DateTime.fromMillisecondsSinceEpoch(json['answeredAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'flashcardId': flashcardId,
      'userAnswer': userAnswer,
      'isCorrect': isCorrect ? 1 : 0,
      'timeTakenMs': timeTakenMs,
      'answeredAt': answeredAt.millisecondsSinceEpoch,
    };
  }

  factory QuizAnswerModel.fromEntity(QuizAnswer answer) {
    return QuizAnswerModel(
      id: answer.id,
      sessionId: answer.sessionId,
      flashcardId: answer.flashcardId,
      userAnswer: answer.userAnswer,
      isCorrect: answer.isCorrect,
      timeTakenMs: answer.timeTakenMs,
      answeredAt: answer.answeredAt,
    );
  }
}
