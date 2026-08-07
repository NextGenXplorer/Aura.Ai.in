import 'package:aura_mobile/features/screen_reader/screen_context_service.dart'
    as reader;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final screenContextServiceProvider = Provider((ref) {
  return ScreenContextService();
});

/// Thin accessor used by the automation engine's `readScreen` step.
///
/// The accessibility MethodChannel handler lives in exactly one place
/// ([reader.ScreenContextService], initialised from `main.dart`). Previously
/// this class registered a second handler on the same channel, so whichever
/// object was constructed last silently swallowed the other's push events.
class ScreenContextService {
  /// Whether the accessibility service is currently enabled.
  Future<bool> isAccessibilityEnabled() =>
      reader.ScreenContextService.checkServiceStatus();

  /// Opens system accessibility settings so the user can enable the service.
  Future<void> openAccessibilitySettings() =>
      reader.ScreenContextService.openAccessibilitySettings();

  /// Returns the text currently visible on screen, or an empty string when the
  /// accessibility service is off or the screen has no readable text.
  Future<String> getScreenContent() async {
    final context = await reader.ScreenContextService.captureCurrentScreen();
    return context?.screenText ?? '';
  }
}
