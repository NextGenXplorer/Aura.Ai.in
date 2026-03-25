import 'package:equatable/equatable.dart';

class FlashcardDeck extends Equatable {
  final String id;
  final String name;
  final String? sourceDocumentId;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FlashcardDeck({
    required this.id,
    required this.name,
    this.sourceDocumentId,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  FlashcardDeck copyWith({
    String? id,
    String? name,
    String? sourceDocumentId,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FlashcardDeck(
      id: id ?? this.id,
      name: name ?? this.name,
      sourceDocumentId: sourceDocumentId ?? this.sourceDocumentId,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, name, sourceDocumentId, description, createdAt, updatedAt];
}

class Flashcard extends Equatable {
  final String id;
  final String deckId;
  final String front;
  final String back;
  final String? topic;
  final int difficulty; // 1=easy, 2=medium, 3=hard

  // SM-2 spaced repetition fields
  final double easeFactor;
  final int interval; // days until next review
  final int repetitions; // consecutive correct answers
  final DateTime? nextReviewDate;
  final DateTime createdAt;

  const Flashcard({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    this.topic,
    this.difficulty = 2,
    this.easeFactor = 2.5,
    this.interval = 0,
    this.repetitions = 0,
    this.nextReviewDate,
    required this.createdAt,
  });

  Flashcard copyWith({
    String? id,
    String? deckId,
    String? front,
    String? back,
    String? topic,
    int? difficulty,
    double? easeFactor,
    int? interval,
    int? repetitions,
    DateTime? nextReviewDate,
    DateTime? createdAt,
  }) {
    return Flashcard(
      id: id ?? this.id,
      deckId: deckId ?? this.deckId,
      front: front ?? this.front,
      back: back ?? this.back,
      topic: topic ?? this.topic,
      difficulty: difficulty ?? this.difficulty,
      easeFactor: easeFactor ?? this.easeFactor,
      interval: interval ?? this.interval,
      repetitions: repetitions ?? this.repetitions,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id, deckId, front, back, topic, difficulty,
        easeFactor, interval, repetitions, nextReviewDate, createdAt,
      ];
}
