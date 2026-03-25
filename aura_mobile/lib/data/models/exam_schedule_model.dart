import 'package:aura_mobile/domain/entities/exam_schedule.dart';

class ExamScheduleModel extends ExamSchedule {
  const ExamScheduleModel({
    required super.id,
    required super.name,
    super.deckId,
    required super.examDate,
    super.notes,
    required super.createdAt,
  });

  factory ExamScheduleModel.fromJson(Map<String, dynamic> json) {
    return ExamScheduleModel(
      id: json['id'],
      name: json['name'],
      deckId: json['deckId'],
      examDate: DateTime.fromMillisecondsSinceEpoch(json['examDate']),
      notes: json['notes'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'deckId': deckId,
      'examDate': examDate.millisecondsSinceEpoch,
      'notes': notes,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory ExamScheduleModel.fromEntity(ExamSchedule schedule) {
    return ExamScheduleModel(
      id: schedule.id,
      name: schedule.name,
      deckId: schedule.deckId,
      examDate: schedule.examDate,
      notes: schedule.notes,
      createdAt: schedule.createdAt,
    );
  }
}
