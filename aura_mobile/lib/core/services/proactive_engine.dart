import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/core/services/notification_service.dart';

/// Proactive AI Engine — makes the app feel ALIVE.
/// Generates smart nudges based on time, usage patterns, study data, and context.
/// 100% rule-based, no LLM needed, works offline.
class ProactiveEngine {
  static const String _keyLastNudge = 'proactive_last_nudge';
  static const String _keyNudgeCount = 'proactive_nudge_count';
  static const String _keyStudyStreak = 'proactive_study_streak';
  static const String _keyLastStudyDate = 'proactive_last_study';
  static const String _keyAppOpensToday = 'proactive_app_opens_today';
  static const String _keyLastOpenDate = 'proactive_last_open_date';

  /// Generate a context-aware nudge based on current state.
  /// Returns null if no nudge is appropriate right now.
  static Future<ProactiveNudge?> generateNudge({
    int dueCards = 0,
    int upcomingExams = 0,
    int closestExamDays = 999,
    int totalDecks = 0,
    double lastQuizScore = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final hour = now.hour;

    // Rate limiting: max 1 nudge per 2 hours
    final lastNudgeMs = prefs.getInt(_keyLastNudge) ?? 0;
    final lastNudge = DateTime.fromMillisecondsSinceEpoch(lastNudgeMs);
    if (now.difference(lastNudge).inHours < 2 && lastNudgeMs > 0) {
      return null;
    }

    // Track study streak
    final todayStr = '${now.year}-${now.month}-${now.day}';
    final lastOpenDate = prefs.getString(_keyLastOpenDate) ?? '';
    if (lastOpenDate != todayStr) {
      await prefs.setString(_keyLastOpenDate, todayStr);
      await prefs.setInt(_keyAppOpensToday, 1);
    } else {
      final opens = prefs.getInt(_keyAppOpensToday) ?? 0;
      await prefs.setInt(_keyAppOpensToday, opens + 1);
    }

    ProactiveNudge? nudge;

    // ── Morning Brief (6 AM - 10 AM) ────────────────────────────────────
    if (hour >= 6 && hour < 10) {
      nudge = _morningBrief(dueCards, upcomingExams, closestExamDays, totalDecks);
    }
    // ── Afternoon Check-in (12 PM - 3 PM) ───────────────────────────────
    else if (hour >= 12 && hour < 15) {
      nudge = _afternoonCheckin(dueCards, closestExamDays);
    }
    // ── Evening Summary (7 PM - 10 PM) ──────────────────────────────────
    else if (hour >= 19 && hour < 22) {
      nudge = _eveningSummary(dueCards, lastQuizScore, closestExamDays);
    }
    // ── Study Nudge (any time, if urgent) ────────────────────────────────
    else if (closestExamDays <= 3 && closestExamDays > 0) {
      nudge = ProactiveNudge(
        title: 'Exam in $closestExamDays days!',
        message: 'Time for an intensive review. You have $dueCards cards waiting.',
        type: NudgeType.urgent,
        action: NudgeAction.openStudy,
        icon: '🚨',
      );
    }

    if (nudge != null) {
      await prefs.setInt(_keyLastNudge, now.millisecondsSinceEpoch);
      final count = prefs.getInt(_keyNudgeCount) ?? 0;
      await prefs.setInt(_keyNudgeCount, count + 1);
    }

    return nudge;
  }

  static ProactiveNudge? _morningBrief(int dueCards, int upcomingExams, int closestExamDays, int totalDecks) {
    if (totalDecks == 0) {
      return ProactiveNudge(
        title: 'Good morning!',
        message: 'Ready to start studying? Create your first deck to get started.',
        type: NudgeType.suggestion,
        action: NudgeAction.openStudy,
        icon: '🌅',
      );
    }

    if (closestExamDays <= 7 && closestExamDays > 0) {
      return ProactiveNudge(
        title: 'Good morning! Exam in $closestExamDays days',
        message: '$dueCards cards are due for review. Start your day strong!',
        type: NudgeType.important,
        action: NudgeAction.startReview,
        icon: '📚',
      );
    }

    if (dueCards > 0) {
      return ProactiveNudge(
        title: 'Good morning!',
        message: 'You have $dueCards cards ready for review. A 5-minute session can make a big difference!',
        type: NudgeType.gentle,
        action: NudgeAction.startReview,
        icon: '☀️',
      );
    }

    return ProactiveNudge(
      title: 'Good morning!',
      message: 'All caught up on reviews. Keep building your knowledge — scan some notes or take a quiz!',
      type: NudgeType.celebration,
      action: NudgeAction.openChat,
      icon: '🎯',
    );
  }

  static ProactiveNudge? _afternoonCheckin(int dueCards, int closestExamDays) {
    if (dueCards > 10) {
      return ProactiveNudge(
        title: 'Quick study break?',
        message: '$dueCards cards are piling up. Even reviewing 5 cards helps!',
        type: NudgeType.suggestion,
        action: NudgeAction.startReview,
        icon: '💡',
      );
    }

    if (closestExamDays <= 5 && closestExamDays > 0) {
      return ProactiveNudge(
        title: 'Exam prep reminder',
        message: '$closestExamDays days left. Take a quick quiz to test yourself!',
        type: NudgeType.important,
        action: NudgeAction.startQuiz,
        icon: '🧠',
      );
    }

    return null; // No nudge needed
  }

  static ProactiveNudge? _eveningSummary(int dueCards, double lastQuizScore, int closestExamDays) {
    if (lastQuizScore > 0 && lastQuizScore >= 80) {
      return ProactiveNudge(
        title: 'Great day of studying!',
        message: 'You scored ${lastQuizScore.toStringAsFixed(0)}% on your last quiz. Keep this momentum going!',
        type: NudgeType.celebration,
        action: NudgeAction.openStudy,
        icon: '🌟',
      );
    }

    if (dueCards > 0) {
      return ProactiveNudge(
        title: 'End your day with a quick review',
        message: 'Reviewing before sleep improves memory retention. $dueCards cards waiting.',
        type: NudgeType.gentle,
        action: NudgeAction.startReview,
        icon: '🌙',
      );
    }

    return ProactiveNudge(
      title: 'Nice work today!',
      message: 'You\'re all caught up. Rest well — your brain consolidates learning during sleep!',
      type: NudgeType.celebration,
      action: NudgeAction.dismiss,
      icon: '✅',
    );
  }

  /// Track that the user studied today (for streak calculation)
  static Future<void> trackStudySession() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month}-${now.day}';
    final lastStudy = prefs.getString(_keyLastStudyDate) ?? '';

    if (lastStudy != todayStr) {
      await prefs.setString(_keyLastStudyDate, todayStr);

      // Check if yesterday was studied (streak)
      final yesterday = now.subtract(const Duration(days: 1));
      final yesterdayStr = '${yesterday.year}-${yesterday.month}-${yesterday.day}';

      if (lastStudy == yesterdayStr) {
        final streak = prefs.getInt(_keyStudyStreak) ?? 0;
        await prefs.setInt(_keyStudyStreak, streak + 1);
      } else {
        await prefs.setInt(_keyStudyStreak, 1); // Reset streak
      }
    }
  }

  /// Get current study streak
  static Future<int> getStudyStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyStudyStreak) ?? 0;
  }

  /// Schedule a proactive notification for later
  static Future<void> scheduleSmartNotification({
    required int dueCards,
    required int closestExamDays,
  }) async {
    try {
      final notificationService = NotificationService();
      final now = DateTime.now();

      // Schedule morning nudge at 8 AM if not already past
      if (now.hour < 8) {
        final morning = DateTime(now.year, now.month, now.day, 8, 0);
        final title = closestExamDays <= 7
            ? '📚 Exam in $closestExamDays days!'
            : '☀️ Good morning!';
        final body = dueCards > 0
            ? '$dueCards cards ready for review. Start your day strong!'
            : 'All caught up! Scan some notes or take a quiz.';

        await notificationService.scheduleNotification(
          id: 9000,
          title: title,
          body: body,
          scheduledTime: morning,
        );
      }

      // Schedule evening nudge at 8 PM
      if (now.hour < 20) {
        final evening = DateTime(now.year, now.month, now.day, 20, 0);
        await notificationService.scheduleNotification(
          id: 9001,
          title: '🌙 Evening review',
          body: 'Quick review before bed boosts memory retention!',
          scheduledTime: evening,
        );
      }
    } catch (e) {
      debugPrint('ProactiveEngine: Failed to schedule notification: $e');
    }
  }
}

// ── Data Classes ──────────────────────────────────────────────────────────────

class ProactiveNudge {
  final String title;
  final String message;
  final NudgeType type;
  final NudgeAction action;
  final String icon;

  const ProactiveNudge({
    required this.title,
    required this.message,
    required this.type,
    required this.action,
    required this.icon,
  });
}

enum NudgeType {
  gentle,      // Low priority, dismissible
  suggestion,  // Medium priority, helpful
  important,   // High priority, should act
  urgent,      // Critical, exam-related
  celebration, // Positive reinforcement
}

enum NudgeAction {
  openChat,
  openStudy,
  startReview,
  startQuiz,
  openScan,
  dismiss,
}
