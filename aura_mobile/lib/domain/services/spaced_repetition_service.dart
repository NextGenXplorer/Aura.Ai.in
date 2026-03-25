import 'dart:math';

/// SM-2 Spaced Repetition Algorithm
/// Pure math — no AI, no providers, works on any device.
class SpacedRepetitionService {
  /// Calculate the next review state based on user's quality rating.
  ///
  /// [quality] is rated 0-5:
  ///   0 = complete blackout
  ///   1 = incorrect, but recognized on seeing answer
  ///   2 = incorrect, but answer seemed easy to recall
  ///   3 = correct with serious difficulty
  ///   4 = correct after hesitation
  ///   5 = perfect recall
  static SpacedRepetitionResult calculate({
    required int quality,
    required double easeFactor,
    required int interval,
    required int repetitions,
  }) {
    // Clamp quality to valid range
    quality = quality.clamp(0, 5);

    double newEaseFactor = easeFactor;
    int newInterval;
    int newRepetitions;

    if (quality >= 3) {
      // Correct response
      if (repetitions == 0) {
        newInterval = 1;
      } else if (repetitions == 1) {
        newInterval = 6;
      } else {
        newInterval = (interval * easeFactor).round();
      }
      newRepetitions = repetitions + 1;
    } else {
      // Incorrect response — reset
      newRepetitions = 0;
      newInterval = 1;
    }

    // Update ease factor using SM-2 formula
    newEaseFactor = easeFactor +
        (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    newEaseFactor = max(1.3, newEaseFactor); // Minimum 1.3

    // Calculate next review date
    final nextReviewDate = DateTime.now().add(Duration(days: newInterval));

    return SpacedRepetitionResult(
      easeFactor: newEaseFactor,
      interval: newInterval,
      repetitions: newRepetitions,
      nextReviewDate: nextReviewDate,
    );
  }

  /// Convert UI button press to SM-2 quality rating.
  /// Maps: Again=1, Hard=2, Good=4, Easy=5
  static int buttonToQuality(String button) {
    switch (button.toLowerCase()) {
      case 'again':
        return 1;
      case 'hard':
        return 2;
      case 'good':
        return 4;
      case 'easy':
        return 5;
      default:
        return 3;
    }
  }

  /// Get a human-readable interval string
  static String intervalToString(int days) {
    if (days == 0) return 'Now';
    if (days == 1) return '1 day';
    if (days < 7) return '$days days';
    if (days < 30) return '${(days / 7).round()} weeks';
    if (days < 365) return '${(days / 30).round()} months';
    return '${(days / 365).round()} years';
  }
}

class SpacedRepetitionResult {
  final double easeFactor;
  final int interval;
  final int repetitions;
  final DateTime nextReviewDate;

  const SpacedRepetitionResult({
    required this.easeFactor,
    required this.interval,
    required this.repetitions,
    required this.nextReviewDate,
  });
}
