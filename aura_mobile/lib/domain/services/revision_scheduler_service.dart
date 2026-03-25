/// Smart revision scheduling — pure logic, no AI needed.
/// Generates optimal revision dates working backward from exam date
/// using expanding intervals based on cognitive science.
class RevisionSchedulerService {
  /// Generate revision schedule dates based on days until exam.
  ///
  /// Uses expanding intervals: 1, 3, 7, 14, 30 days before exam.
  /// Only returns dates that are in the future.
  static List<DateTime> generateRevisionSchedule(DateTime examDate) {
    final now = DateTime.now();
    final intervals = [1, 3, 7, 14, 30, 60];

    return intervals
        .map((d) => DateTime(
              examDate.year,
              examDate.month,
              examDate.day - d,
            ))
        .where((d) => d.isAfter(now))
        .toList()
      ..sort();
  }

  /// Get a study intensity recommendation based on days until exam.
  static StudyIntensity getStudyIntensity(int daysRemaining) {
    if (daysRemaining <= 1) {
      return StudyIntensity(
        label: 'Final Review',
        cardsPerSession: 50,
        sessionsPerDay: 3,
        description: 'Light review of weak topics only. Trust your preparation.',
      );
    } else if (daysRemaining <= 3) {
      return StudyIntensity(
        label: 'Intensive',
        cardsPerSession: 40,
        sessionsPerDay: 3,
        description: 'Focus on weak topics. Review all flagged cards.',
      );
    } else if (daysRemaining <= 7) {
      return StudyIntensity(
        label: 'Active',
        cardsPerSession: 30,
        sessionsPerDay: 2,
        description: 'Regular review sessions. Mix weak and strong topics.',
      );
    } else if (daysRemaining <= 14) {
      return StudyIntensity(
        label: 'Steady',
        cardsPerSession: 20,
        sessionsPerDay: 2,
        description: 'Balanced study. Focus on understanding concepts.',
      );
    } else if (daysRemaining <= 30) {
      return StudyIntensity(
        label: 'Building',
        cardsPerSession: 15,
        sessionsPerDay: 1,
        description: 'Create flashcards and start initial learning.',
      );
    } else {
      return StudyIntensity(
        label: 'Planning',
        cardsPerSession: 10,
        sessionsPerDay: 1,
        description: 'Gather materials and create your study deck.',
      );
    }
  }

  /// Get motivational message based on progress
  static String getMotivation(int daysRemaining, double masteryPercent) {
    if (masteryPercent >= 90) {
      return 'You\'re crushing it! Keep reviewing to maintain your edge.';
    } else if (masteryPercent >= 70) {
      return 'Great progress! Focus on your weak areas now.';
    } else if (masteryPercent >= 50) {
      return 'Halfway there! Consistency is key. Keep going!';
    } else if (daysRemaining > 14) {
      return 'Plenty of time! Start with the basics and build up.';
    } else if (daysRemaining > 3) {
      return 'Time to focus! Short, frequent sessions work best.';
    } else {
      return 'Review what you know best. You\'ve got this!';
    }
  }
}

class StudyIntensity {
  final String label;
  final int cardsPerSession;
  final int sessionsPerDay;
  final String description;

  const StudyIntensity({
    required this.label,
    required this.cardsPerSession,
    required this.sessionsPerDay,
    required this.description,
  });
}
