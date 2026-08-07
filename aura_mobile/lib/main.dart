import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/core/services/background_service.dart';
import 'package:aura_mobile/presentation/pages/chat_screen.dart';
import 'package:aura_mobile/presentation/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/core/services/notification_service.dart';
import 'package:aura_mobile/core/services/app_usage_tracker.dart';
import 'package:aura_mobile/core/services/daily_summary_scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/core/services/download_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:aura_mobile/presentation/widgets/voice_assistant_overlay.dart';
import 'package:aura_mobile/presentation/widgets/clipboard_bubble_overlay.dart';
import 'package:aura_mobile/core/services/app_navigator.dart';
import 'package:aura_mobile/core/services/assistant_ai_bridge.dart';
import 'package:aura_mobile/core/services/clipboard_ai_service.dart';
import 'package:aura_mobile/core/services/utility_model_manager.dart';
import 'package:aura_mobile/features/smart_summarizer/share_receiver_service.dart';
import 'package:aura_mobile/features/screen_reader/screen_context_service.dart';
import 'package:aura_mobile/features/daily_briefing/home_widget_service.dart';
import 'package:aura_mobile/core/services/widget_route_service.dart';
import 'package:aura_mobile/brain/aura_brain_controller.dart';
import 'package:aura_mobile/brain/aura_brain_entrypoint.dart' as brain;
import 'package:aura_mobile/presentation/pages/model_selector_screen.dart';

// The navigator handle now lives in AppNavigator so non-UI layers (chat
// navigation markers, Aura Brain setup) can reach it without importing main.dart.
export 'package:aura_mobile/core/services/app_navigator.dart'
    show auraNavigatorKey;

@pragma('vm:entry-point')
void auraBrainMain() => brain.auraBrainMain();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Requirement for flutter_foreground_task to receive data in the main isolate
  FlutterForegroundTask.initCommunicationPort();

  // Initialize non-critical services after rendering the UI to avoid hangs
  _initServicesAsync();

  // Check Onboarding Status
  final prefs = await SharedPreferences.getInstance();
  final isOnboarded = prefs.getBool('is_onboarded') ?? false;

  runApp(
    ProviderScope(
      child: AuraApp(initialRoute: isOnboarded ? '/chat' : '/onboarding'),
    ),
  );
}

/// Helper to initialize background services without blocking the main UI thread/splash screen
Future<void> _initServicesAsync() async {
  // Initialize Workmanager
  try {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  } catch (e) {
    debugPrint("Workmanager initialization failed: $e");
  }

  // Initialize Local Notifications for Main Isolate
  try {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_notification');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  } catch (e) {
    debugPrint("Local Notifications failed: $e");
  }

  // Initialize download service for model downloads
  try {
    await DownloadService().initialize();
  } catch (e) {
    debugPrint("DownloadService initialization failed: $e");
  }

  // Initialize notification system
  try {
    final notificationService = NotificationService();
    await notificationService.requestPermissions();
    await notificationService.initialize();
  } catch (e) {
    debugPrint("NotificationService failed: $e");
  }

  // Initialize app usage tracking
  try {
    final appUsageTracker = AppUsageTracker();
    await appUsageTracker.trackAppOpen();
  } catch (e) {
    debugPrint("AppUsageTracker failed: $e");
  }

  // Initialize daily summary scheduler
  try {
    await DailySummaryScheduler.initialize();
  } catch (e) {
    debugPrint("DailySummaryScheduler failed: $e");
  }

  // Initialize Share Receiver (Smart Summarizer)
  try {
    ShareReceiverService.initialize();
  } catch (e) {
    debugPrint("ShareReceiverService failed: $e");
  }

  // Initialize Screen Context Service (Screen Reader AI)
  try {
    ScreenContextService.initialize();
  } catch (e) {
    debugPrint("ScreenContextService failed: $e");
  }

  // Route home screen widget taps into the app. Initialised before the data
  // push so a tap that cold-started the app is not dropped.
  try {
    await WidgetRouteService.initialize();
  } catch (e) {
    debugPrint("WidgetRouteService failed: $e");
  }

  // Initialize Home Widget service and push data to widget
  try {
    await HomeWidgetService.initialize();
    // Don't await — let it run in background without blocking UI
    HomeWidgetService.updateWidgetData();
    // Register periodic background task to refresh widget every hour
    // 15 minutes is the floor WorkManager allows for periodic work. Combined
    // with the in-widget refresh button and the push on app open, that is as
    // close to live as an Android home screen widget can get without an
    // exact-alarm loop, which would cost noticeable battery.
    // `replace` (not `keep`) so installs that registered the old hourly task
    // actually pick up the shorter period.
    await Workmanager().registerPeriodicTask(
      'widgetRefreshTask',
      'widgetRefreshTask',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  } catch (e) {
    debugPrint("HomeWidgetService failed: $e");
  }
}

class AuraApp extends ConsumerWidget {
  final String initialRoute;
  const AuraApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly initialize the AI bridge so it registers the MethodChannel handler
    ref.read(assistantAiBridgeProvider);

    // Clipboard AI is lazy by default, so nothing ever registered its channel
    // handler. Reading it here activates the floating bubble, the "Ask Aura"
    // text-selection path and clipboard-copy automation triggers.
    ref.read(clipboardAiServiceProvider);

    final brainController = ref.read(auraBrainControllerProvider);
    brainController.onOpenSetup = () {
      auraNavigatorKey.currentState?.pushNamed('/modelSetup');
    };

    // Check utility model availability on app start
    ref.read(utilityModelManagerProvider.notifier).checkAvailability();

    return MaterialApp(
      navigatorKey: auraNavigatorKey,
      title: 'AURA Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(
          0xFFF7F4EF,
        ), // Light warm paper background
        primaryColor: const Color(0xFFB3862B), // Deep warm gold/amber
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFB3862B),
          secondary: Color(0xFFD1A153),
          surface: Color(0xFFEFECE6), // Warm grey clay base
          background: Color(0xFFF7F4EF),
        ),
        textTheme: GoogleFonts.outfitTextTheme(
          Theme.of(context).textTheme.apply(
            bodyColor: const Color(0xFF191816), // Deep warm ink text
            displayColor: const Color(0xFF191816),
          ),
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: VoiceAssistantOverlay(
            child: ClipboardBubbleOverlay(child: child ?? const SizedBox()),
          ),
        );
      },
      initialRoute: initialRoute,
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/chat': (context) => const ChatScreen(),
        '/modelSetup': (context) => const ModelSelectorScreen(),
      },
    );
  }
}
