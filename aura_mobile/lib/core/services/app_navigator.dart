import 'package:aura_mobile/features/daily_briefing/daily_briefing_screen.dart';
import 'package:aura_mobile/presentation/pages/camera_scan_screen.dart';
import 'package:aura_mobile/presentation/pages/image_studio_screen.dart';
import 'package:aura_mobile/presentation/pages/study_dashboard_screen.dart';
import 'package:flutter/material.dart';

/// Single navigator handle shared by the app shell and by background-triggered
/// flows (Aura Brain setup, in-chat navigation markers).
final GlobalKey<NavigatorState> auraNavigatorKey = GlobalKey<NavigatorState>();

/// Opens an in-app destination requested by the orchestrator.
///
/// The orchestrator emits `__NAVIGATE__:<target>` markers for intents such as
/// "quiz me" or "scan this". Those markers used to be streamed straight into the
/// chat bubble as literal text because nothing consumed them; now the chat layer
/// strips the marker and calls this helper so the screen actually opens.
class AppNavigator {
  static const String marker = '__NAVIGATE__:';

  /// Returns true when [target] is recognised. If the navigator is not mounted
  /// yet (for example during startup), the request is retried after the first
  /// frame instead of leaking the marker into chat or silently losing it.
  static bool open(String target) {
    final normalized = target.trim();
    if (!_knownTargets.contains(normalized)) return false;

    final navigator = auraNavigatorKey.currentState;
    if (navigator != null) {
      _openWith(navigator, normalized);
      return true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mountedNavigator = auraNavigatorKey.currentState;
      if (mountedNavigator == null) {
        debugPrint(
          'AppNavigator: navigator unavailable for target "$normalized"',
        );
        return;
      }
      _openWith(mountedNavigator, normalized);
    });
    return true;
  }

  static const Set<String> _knownTargets = {
    'study_dashboard',
    'camera_scan',
    'model_setup',
    // Home screen widget destinations.
    'chat',
    'image_studio',
    'daily_briefing',
    // Reviewing or quizzing needs a chosen deck, so both land on the study
    // dashboard where the user picks one.
    'flashcard_review',
    'quiz',
  };

  static void _openWith(NavigatorState navigator, String target) {
    switch (target) {
      case 'study_dashboard':
      case 'flashcard_review':
      case 'quiz':
        navigator.push(
          MaterialPageRoute(builder: (_) => const StudyDashboardScreen()),
        );
        return;
      case 'camera_scan':
        navigator.push(
          MaterialPageRoute(builder: (_) => const CameraScanScreen()),
        );
        return;
      case 'image_studio':
        navigator.push(
          MaterialPageRoute(builder: (_) => const ImageStudioScreen()),
        );
        return;
      case 'daily_briefing':
        navigator.push(
          MaterialPageRoute(builder: (_) => const DailyBriefingScreen()),
        );
        return;
      case 'model_setup':
        navigator.pushNamed('/modelSetup');
        return;
      case 'chat':
        // Chat is the app shell, so drop any stacked screens instead of
        // pushing another route on top of it.
        navigator.popUntil((route) => route.isFirst);
        return;
    }
  }
}
