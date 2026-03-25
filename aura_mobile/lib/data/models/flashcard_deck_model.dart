import 'package:aura_mobile/domain/entities/flashcard.dart';

class FlashcardDeckModel extends FlashcardDeck {
  const FlashcardDeckModel({
    required super.id,
    required super.name,
    super.sourceDocumentId,
    super.description,
    required super.createdAt,
    required super.updatedAt,
  });

  factory FlashcardDeckModel.fromJson(Map<String, dynamic> json) {
    return FlashcardDeckModel(
      id: json['id'],
      name: json['name'],
      sourceDocumentId: json['sourceDocumentId'],
      description: json['description'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'sourceDocumentId': sourceDocumentId,
      'description': description,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory FlashcardDeckModel.fromEntity(FlashcardDeck deck) {
    return FlashcardDeckModel(
      id: deck.id,
      name: deck.name,
      sourceDocumentId: deck.sourceDocumentId,
      description: deck.description,
      createdAt: deck.createdAt,
      updatedAt: deck.updatedAt,
    );
  }
}
