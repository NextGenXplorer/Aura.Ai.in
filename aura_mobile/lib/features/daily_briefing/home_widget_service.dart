import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/core/services/connector_services.dart';

/// Service that pushes data to the Android Home Screen Widget.
/// Called periodically (every hour via WorkManager) and on app open.
///
/// Data flow:
///   Flutter → SharedPreferences (HomeWidgetPreferences) → Android Widget reads them
///
/// The widget itself also fetches news natively (fallback when app isn't open).
class HomeWidgetService {
  static const String _appGroupId = 'com.aura.mobile.aura_mobile';

  static const String _widgetPackage = 'com.aura.mobile.aura_mobile.widget';

  /// Fully-qualified provider class names.
  ///
  /// home_widget resolves a plain `androidName` as
  /// `<applicationId>.<androidName>`. These providers live in the `.widget`
  /// subpackage, so a plain name threw ClassNotFoundException and no refresh
  /// broadcast was ever sent. Always pass the qualified name.
  static const String _qualifiedAndroidWidgetName =
      '$_widgetPackage.AuraBriefingWidget';
  static const String _studyWidgetName = '$_widgetPackage.AuraStudyWidget';
  static const String _quickActionsWidgetName =
      '$_widgetPackage.AuraQuickActionsWidget';

  static const List<String> _allWidgets = [
    _qualifiedAndroidWidgetName,
    _studyWidgetName,
    _quickActionsWidgetName,
  ];

  /// Initialize home_widget configuration.
  static Future<void> initialize() async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
    } catch (e) {
      debugPrint('HomeWidgetService: Initialize failed: $e');
    }
  }

  /// Update widget data: fetch news + weather + quote, save to shared prefs, trigger widget refresh.
  /// Call this on app open, and from WorkManager background task.
  static Future<void> updateWidgetData() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = connectivityResult.any(
        (r) => r != ConnectivityResult.none,
      );

      if (isOnline) {
        // Fetch news headlines
        await _fetchAndSaveNews();

        // Fetch weather
        await _fetchAndSaveWeather();
      }

      // Save quote (offline, rotates daily)
      await _saveQuote();

      // Trigger widget UI refresh
      await _triggerWidgetUpdate();
    } catch (e) {
      debugPrint('HomeWidgetService: Update failed: $e');
    }
  }

  /// Fetch Google News RSS and save top headlines to widget storage.
  static Future<void> _fetchAndSaveNews() async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final response = await dio.get(
        'https://news.google.com/rss?hl=en-IN&gl=IN&ceid=IN:en',
      );
      final content = response.data as String;

      // Parse RSS XML for titles and sources
      final itemPattern = RegExp(r'<item>(.*?)</item>', dotAll: true);
      final titlePattern = RegExp(
        r'<title><!\[CDATA\[(.*?)\]\]></title>|<title>(.*?)</title>',
      );
      final sourcePattern = RegExp(r'<source[^>]*>(.*?)</source>');
      final linkPattern = RegExp(r'<link>(.*?)</link>');

      // 15, not 3: the widget's list scrolls, so more headlines are useful.
      final items = itemPattern.allMatches(content).take(15).toList();
      final headlines = <Map<String, String>>[];

      for (final item in items) {
        final itemContent = item.group(1) ?? '';
        final titleMatch = titlePattern.firstMatch(itemContent);
        final sourceMatch = sourcePattern.firstMatch(itemContent);
        final linkMatch = linkPattern.firstMatch(itemContent);

        final title = titleMatch != null
            ? (titleMatch.group(1)?.isNotEmpty == true
                  ? titleMatch.group(1)!
                  : titleMatch.group(2) ?? '')
            : '';
        final source = sourceMatch?.group(1) ?? '';

        if (title.isNotEmpty && !title.contains('Google News')) {
          headlines.add({
            'title': _decodeEntities(title.trim()),
            'source': _decodeEntities(source.trim()),
            // Tapping a row in the widget opens this link in the browser.
            'link': linkMatch?.group(1)?.trim() ?? '',
          });
        }
      }

      if (headlines.isEmpty) return;

      // The widget's headline list is backed by a single JSON array, so it is
      // no longer capped at the three flat keys the old layout could show.
      await HomeWidget.saveWidgetData<String>(
        'widget_headlines_json',
        jsonEncode(headlines),
      );

      // Keep the first flat slot in sync so a widget instance placed before
      // this change still renders until it is recreated.
      await HomeWidget.saveWidgetData(
        'widget_headline_1',
        headlines[0]['title'],
      );
      await HomeWidget.saveWidgetData(
        'widget_headline_1_source',
        headlines[0]['source'],
      );

      // Must be stored as an int: the native provider reads this key with
      // getLong(), so a String value threw ClassCastException and broke the
      // staleness check.
      await HomeWidget.saveWidgetData<int>(
        'widget_last_fetch',
        DateTime.now().millisecondsSinceEpoch,
      );
      debugPrint('HomeWidgetService: Saved ${headlines.length} headlines');
    } catch (e) {
      debugPrint('HomeWidgetService: News fetch failed: $e');
    }
  }

  /// Fetch weather and save to widget storage.
  static Future<void> _fetchAndSaveWeather() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final city = prefs.getString('user_city') ?? 'New Delhi';

      final weatherService = WeatherService();
      final data = await weatherService.getWeather(city);

      // WeatherService returns flat keys (temperature/condition); the condition
      // string already carries its own emoji.
      if (!data.containsKey('error') && data['temperature'] != null) {
        final weatherText =
            '${data['temperature']}°C • ${data['condition'] ?? ''}'.trim();
        await HomeWidget.saveWidgetData('widget_weather', weatherText);
      }
    } catch (e) {
      debugPrint('HomeWidgetService: Weather fetch failed: $e');
    }
  }

  /// RSS titles arrive HTML-escaped; a raw `&#39;` in the widget looks broken.
  static String _decodeEntities(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');

  /// Save a daily rotating quote.
  static Future<void> _saveQuote() async {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final quote = _quotes[dayOfYear % _quotes.length];
    await HomeWidget.saveWidgetData('widget_quote', quote);
  }

  /// Pushes the current study numbers to the study widget.
  ///
  /// Called whenever study data changes (a card reviewed, a deck or exam added)
  /// so the widget follows the app instead of waiting for the 30 minute OS
  /// update tick.
  static Future<void> updateStudyData({
    required int dueCards,
    required int streakDays,
    required int deckCount,
    String? nextExamName,
    int? nextExamDays,
  }) async {
    try {
      await HomeWidget.saveWidgetData<int>('widget_study_due', dueCards);
      await HomeWidget.saveWidgetData<int>('widget_study_streak', streakDays);
      await HomeWidget.saveWidgetData<int>('widget_study_decks', deckCount);
      // An empty name plus -1 days is how the native side detects "no exam".
      await HomeWidget.saveWidgetData<String>(
        'widget_study_exam_name',
        nextExamName ?? '',
      );
      await HomeWidget.saveWidgetData<int>(
        'widget_study_exam_days',
        nextExamDays ?? -1,
      );
      await HomeWidget.updateWidget(qualifiedAndroidName: _studyWidgetName);
    } catch (e) {
      debugPrint('HomeWidgetService: Study widget update failed: $e');
    }
  }

  /// Whether any AURA widget is currently placed on the home screen.
  static Future<bool> isWidgetPlaced() async {
    try {
      final installed = await HomeWidget.getInstalledWidgets();
      return installed.any((w) {
        final name = w.androidClassName ?? '';
        return name.startsWith(_widgetPackage);
      });
    } catch (e) {
      debugPrint('HomeWidgetService: Install check failed: $e');
      return false;
    }
  }

  /// Asks Android to show the "add widget" dialog for the briefing widget.
  ///
  /// Returns false when the launcher does not support pinning, in which case
  /// the user has to add it from the launcher's widget picker manually.
  static Future<bool> requestPinToHomeScreen() async {
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      if (supported != true) return false;
      await HomeWidget.requestPinWidget(
        qualifiedAndroidName: _qualifiedAndroidWidgetName,
      );
      return true;
    } catch (e) {
      debugPrint('HomeWidgetService: Pin request failed: $e');
      return false;
    }
  }

  /// Re-fetches data and pushes it to the widget. Exposed for a manual
  /// "refresh widget" action.
  static Future<void> refreshNow() => updateWidgetData();

  /// Trigger every native widget to re-read data and refresh its UI.
  ///
  /// Each provider is updated independently so one failing (for example a
  /// provider with no placed instance) cannot stop the others.
  static Future<void> _triggerWidgetUpdate() async {
    for (final widget in _allWidgets) {
      try {
        await HomeWidget.updateWidget(qualifiedAndroidName: widget);
      } catch (e) {
        debugPrint('HomeWidgetService: Update trigger failed for $widget: $e');
      }
    }
  }

  static const List<String> _quotes = [
    '💡 "The best time to start is now."',
    '🌟 "Small steps lead to big results."',
    '🔥 "Push yourself. No one else will."',
    '🎯 "Focus on progress, not perfection."',
    '💪 "Discipline beats motivation."',
    '🧠 "Learn something new every day."',
    '⭐ "Your only limit is your mind."',
    '🚀 "Dream big, work hard."',
    '🌈 "Difficult roads lead to beautiful destinations."',
    '📚 "Knowledge is the ultimate power."',
    '💎 "Consistency is the key to success."',
    '🌱 "Growth requires discomfort."',
    '⚡ "Action cures fear."',
    '🎓 "Never stop learning."',
    '✨ "Make today count."',
  ];
}
