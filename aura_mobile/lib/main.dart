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
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'dart:isolate';
import 'dart:ui';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Workmanager
  await Workmanager().initialize(
    callbackDispatcher, 
    isInDebugMode: true // If enabled it will post a notification whenever the task is running
  );
  
  // Initialize Local Notifications for Main Isolate (for listening/interaction if needed)
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Initialize RunAnywhere to sync downloads
  try {
    await RunAnywhere().initialize();
  } catch (e) {
    print("RunAnywhere initialization failed: $e");
  }

  // Initialize notification system
  final notificationService = NotificationService();
  await notificationService.requestPermissions();
  await notificationService.initialize();
  
  // Initialize app usage tracking
  final appUsageTracker = AppUsageTracker();
  await appUsageTracker.trackAppOpen();
  
  // Initialize daily summary scheduler
  await DailySummaryScheduler.initialize();
  
  // Check Onboarding Status
  final prefs = await SharedPreferences.getInstance();
  final isOnboarded = prefs.getBool('is_onboarded') ?? false;
  
  runApp(
    ProviderScope(
      child: AuraApp(initialRoute: isOnboarded ? '/chat' : '/onboarding'),
    ),
  );
}

class AuraApp extends StatelessWidget {
  final String initialRoute;
  const AuraApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AURA Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0a0a0c), // Obsidian
        primaryColor: const Color(0xFFc69c3a), // Gold
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFc69c3a),
          secondary: Color(0xFFe6cf8e),
          surface: Color(0xFF1a1a20),
          background: Color(0xFF0a0a0c),
        ),
        textTheme: GoogleFonts.outfitTextTheme(
          Theme.of(context).textTheme.apply(
            bodyColor: const Color(0xFFEDEDED),
            displayColor: Colors.white,
          ),
        ),
        useMaterial3: true,
      ),
      initialRoute: initialRoute,
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/chat': (context) => const ChatScreen(),
      },
    );
  }
}
