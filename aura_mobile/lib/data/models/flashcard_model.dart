import 'package:aura_mobile/domain/entities/flashcard.dart';

class FlashcardModel extends Flashcard {
  const FlashcardModel({
    required super.id,
    required super.deckId,
    required super.front,
    required super.back,
    super.topic,
    super.difficulty,
    super.easeFactor,
    super.interval,
    super.repetitions,
    super.nextReviewDate,
    required super.createdAt,
  });

  factory FlashcardModel.fromJson(Map<String, dynamic> json) {
    return FlashcardModel(
      id: json['id'],
      deckId: json['deckId'],
      front: json['front'],
      back: json['back'],
      topic: json['topic'],
      difficulty: json['difficulty'] ?? 2,
      easeFactor: (json['easeFactor'] ?? 2.5).toDouble(),
      interval: json['interval'] ?? 0,
      repetitions: json['repetitions'] ?? 0,
      nextReviewDate: json['nextReviewDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['nextReviewDate'])
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deckId': deckId,
      'front': front,
      'back': back,
      'topic': topic,
      'difficulty': difficulty,
      'easeFactor': easeFactor,
      'interval': interval,
      'repetitions': repetitions,
      'nextReviewDate': nextReviewDate?.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory FlashcardModel.fromEntity(Flashcard card) {
    return FlashcardModel(
      id: card.id,
      deckId: card.deckId,
      front: card.front,
      back: card.back,
      topic: card.topic,
      difficulty: card.difficulty,
      easeFactor: card.easeFactor,
      interval: card.interval,
      repetitions: card.repetitions,
      nextReviewDate: card.nextReviewDate,
      createdAt: card.createdAt,
    );
  }
}
