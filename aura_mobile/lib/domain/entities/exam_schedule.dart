import 'package:equatable/equatable.dart';

class ExamSchedule extends Equatable {
  final String id;
  final String name;
  final String? deckId;
  final DateTime examDate;
  final String? notes;
  final DateTime createdAt;

  const ExamSchedule({
    required this.id,
    required this.name,
    this.deckId,
    required this.examDate,
    this.notes,
    required this.createdAt,
  });

  ExamSchedule copyWith({
    String? id,
    String? name,
    String? deckId,
    DateTime? examDate,
    String? notes,
    DateTime? createdAt,
  }) {
    return ExamSchedule(
      id: id ?? this.id,
      name: name ?? this.name,
      deckId: deckId ?? this.deckId,
      examDate: examDate ?? this.examDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  int get daysRemaining {
    final now = DateTime.now();
    final diff = examDate.difference(now).inDays;
    return diff < 0 ? 0 : diff;
  }

  bool get isPast => examDate.isBefore(DateTime.now());

  @override
  List<Object?> get props => [id, name, deckId, examDate, notes, createdAt];
}
