import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:aura_mobile/core/services/connector_services.dart';
import 'package:aura_mobile/data/datasources/database_helper.dart';
import 'package:aura_mobile/data/repositories/memory_repository_impl.dart';

/// Data class representing a single briefing card in the Daily Briefing screen.
class BriefingCard {
  final String title;
  final String content;
  final BriefingCardType type;
  final String? actionRoute;
  final String icon;

  const BriefingCard({
    required this.title,
    required this.content,
    required this.type,
    this.actionRoute,
    required this.icon,
  });
}

enum BriefingCardType {
  greeting,
  weather,
  memories,
  studyReminder,
  quote,
  tip,
  notifications,
}

/// Generates the Daily Briefing data — hybrid online/offline.
/// Weather requires internet; everything else works offline.
class DailyBriefingService {
  static const String _keyLastBriefingDate = 'daily_briefing_last_date';
  static const String _keyDailyQuoteIndex = 'daily_quote_index';

  /// Generate all briefing cards for the current moment.
  Future<List<BriefingCard>> generateBriefing() async {
    final cards = <BriefingCard>[];
    final now = DateTime.now();
    final hour = now.hour;

    // 1. Greeting card (always first, offline)
    cards.add(_buildGreetingCard(hour));

    // 2. Weather card (online only, fail silently)
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = connectivityResult.any(
        (r) => r != ConnectivityResult.none,
      );
      if (isOnline) {
        final weatherCard = await _buildWeatherCard();
        if (weatherCard != null) cards.add(weatherCard);
      }
    } catch (e) {
      debugPrint('DailyBriefing: Weather fetch failed: $e');
    }

    // 3. Memories/Events for today (offline)
    try {
      final memoryCard = await _buildMemoryCard(now);
      if (memoryCard != null) cards.add(memoryCard);
    } catch (e) {
      debugPrint('DailyBriefing: Memory fetch failed: $e');
    }

    // 4. Study reminder (offline)
    try {
      final studyCard = await _buildStudyCard();
      if (studyCard != null) cards.add(studyCard);
    } catch (e) {
      debugPrint('DailyBriefing: Study card failed: $e');
    }

    // 5. AI Quote of the day (offline, rotates daily)
    cards.add(await _buildQuoteCard());

    // 6. Productivity tip (offline)
    cards.add(_buildTipCard(hour));

    // Mark briefing as shown today
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyLastBriefingDate,
      '${now.year}-${now.month}-${now.day}',
    );

    return cards;
  }

  /// Check if briefing was already shown today
  Future<bool> wasBriefingShownToday() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDate = prefs.getString(_keyLastBriefingDate) ?? '';
    final now = DateTime.now();
    return lastDate == '${now.year}-${now.month}-${now.day}';
  }

  BriefingCard _buildGreetingCard(int hour) {
    String greeting;
    String emoji;
    if (hour < 6) {
      greeting = 'Up early! The quiet hours are golden for focus.';
      emoji = '🌙';
    } else if (hour < 12) {
      greeting = 'Good morning! A fresh day, full of possibilities.';
      emoji = '☀️';
    } else if (hour < 17) {
      greeting = 'Good afternoon! How\'s your day going so far?';
      emoji = '🌤️';
    } else if (hour < 21) {
      greeting = 'Good evening! Time to wind down and reflect.';
      emoji = '🌅';
    } else {
      greeting = 'Night owl mode! Remember to rest soon.';
      emoji = '🌙';
    }

    return BriefingCard(
      title: '$emoji Your Daily Briefing',
      content: greeting,
      type: BriefingCardType.greeting,
      icon: '📋',
    );
  }

  Future<BriefingCard?> _buildWeatherCard() async {
    try {
      final weatherService = WeatherService();
      // Use a default city; in production, get from user's saved location
      final prefs = await SharedPreferences.getInstance();
      final city = prefs.getString('user_city') ?? 'New Delhi';
      final data = await weatherService.getWeather(city);

      // WeatherService returns flat keys and a ready-made condition string.
      if (!data.containsKey('error') && data['temperature'] != null) {
        final temp = data['temperature'];
        final condition = data['condition']?.toString() ?? '';
        final feelsLike = data['feelsLike'];
        final cityName = data['city']?.toString() ?? city;

        return BriefingCard(
          title: '🌡️ Weather in $cityName',
          content: feelsLike == null
              ? '$temp°C — $condition'
              : '$temp°C (feels like $feelsLike°C) — $condition',
          type: BriefingCardType.weather,
          icon: '🌤️',
        );
      }
    } catch (e) {
      debugPrint('DailyBriefing: Weather card error: $e');
    }
    return null;
  }

  Future<BriefingCard?> _buildMemoryCard(DateTime now) async {
    try {
      final repository = MemoryRepositoryImpl(DatabaseHelper());
      final allMemories = await repository.getMemories();

      // Find memories/events for today
      final todayMemories = allMemories.where((m) {
        if (m.eventDate != null) {
          return m.eventDate!.year == now.year &&
              m.eventDate!.month == now.month &&
              m.eventDate!.day == now.day;
        }
        return false;
      }).toList();

      // Also find recent memories (last 7 days) for context
      final recentCount = allMemories.where((m) {
        final diff = now.difference(m.timestamp).inDays;
        return diff >= 0 && diff <= 7;
      }).length;

      if (todayMemories.isNotEmpty) {
        final preview = todayMemories
            .take(3)
            .map(
              (m) =>
                  '• ${m.content.length > 50 ? m.content.substring(0, 50) : m.content}',
            )
            .join('\n');
        return BriefingCard(
          title: '📅 Today\'s Events (${todayMemories.length})',
          content: preview,
          type: BriefingCardType.memories,
          actionRoute: 'memories',
          icon: '📅',
        );
      } else if (recentCount > 0) {
        return BriefingCard(
          title: '🧠 Your Memory Vault',
          content:
              '$recentCount memories saved this week. Your AI remembers everything.',
          type: BriefingCardType.memories,
          actionRoute: 'memories',
          icon: '🧠',
        );
      }
    } catch (e) {
      debugPrint('DailyBriefing: Memory card error: $e');
    }
    return null;
  }

  Future<BriefingCard?> _buildStudyCard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final streak = prefs.getInt('proactive_study_streak') ?? 0;
      final lastStudy = prefs.getString('proactive_last_study') ?? '';

      if (streak > 0) {
        return BriefingCard(
          title: '📚 Study Streak: $streak days',
          content:
              'Keep the momentum going! Review your flashcards to maintain your streak.',
          type: BriefingCardType.studyReminder,
          actionRoute: 'study_dashboard',
          icon: '📚',
        );
      } else if (lastStudy.isEmpty) {
        return BriefingCard(
          title: '📚 Start Your Learning Journey',
          content:
              'Create flashcards from any topic. AURA makes studying effortless.',
          type: BriefingCardType.studyReminder,
          actionRoute: 'study_dashboard',
          icon: '📚',
        );
      }
    } catch (e) {
      debugPrint('DailyBriefing: Study card error: $e');
    }
    return null;
  }

  Future<BriefingCard> _buildQuoteCard() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_keyDailyQuoteIndex) ?? 0;
    final quote = _quotes[idx % _quotes.length];

    // Rotate for tomorrow
    await prefs.setInt(_keyDailyQuoteIndex, idx + 1);

    return BriefingCard(
      title: '💡 Thought of the Day',
      content: quote,
      type: BriefingCardType.quote,
      icon: '💡',
    );
  }

  BriefingCard _buildTipCard(int hour) {
    String tip;
    if (hour < 10) {
      tip =
          'Morning tip: Start with your hardest task. Your brain is sharpest now.';
    } else if (hour < 14) {
      tip = 'Midday tip: Take a 5-min break every 25 min (Pomodoro technique).';
    } else if (hour < 18) {
      tip =
          'Afternoon tip: Review what you learned today — spacing boosts retention 2x.';
    } else {
      tip =
          'Evening tip: Write down 3 things you accomplished today. Gratitude fuels growth.';
    }

    return BriefingCard(
      title: '🎯 Productivity',
      content: tip,
      type: BriefingCardType.tip,
      icon: '🎯',
    );
  }

  static const List<String> _quotes = [
    '"The only way to do great work is to love what you do." — Steve Jobs',
    '"In the middle of difficulty lies opportunity." — Albert Einstein',
    '"It does not matter how slowly you go as long as you do not stop." — Confucius',
    '"The future belongs to those who believe in the beauty of their dreams." — Eleanor Roosevelt',
    '"Success is not final, failure is not fatal: it is the courage to continue that counts." — Winston Churchill',
    '"The best time to plant a tree was 20 years ago. The second best time is now." — Chinese Proverb',
    '"Your limitation—it\'s only your imagination."',
    '"Push yourself, because no one else is going to do it for you."',
    '"Great things never come from comfort zones."',
    '"Dream it. Wish it. Do it."',
    '"Don\'t stop when you\'re tired. Stop when you\'re done."',
    '"Wake up with determination. Go to bed with satisfaction."',
    '"Do something today that your future self will thank you for."',
    '"Little things make big days."',
    '"It\'s going to be hard, but hard does not mean impossible."',
    '"The mind is everything. What you think you become." — Buddha',
    '"An investment in knowledge pays the best interest." — Benjamin Franklin',
    '"Education is not the filling of a pail, but the lighting of a fire." — W.B. Yeats',
    '"Tell me and I forget. Teach me and I remember. Involve me and I learn." — Benjamin Franklin',
    '"The beautiful thing about learning is that nobody can take it away from you." — B.B. King',
    '"What we know is a drop, what we don\'t know is an ocean." — Isaac Newton',
    '"Live as if you were to die tomorrow. Learn as if you were to live forever." — Mahatma Gandhi',
    '"The only true wisdom is in knowing you know nothing." — Socrates',
    '"Intellectual growth should commence at birth and cease only at death." — Albert Einstein',
    '"Knowledge is power. Information is liberating." — Kofi Annan',
    '"The more that you read, the more things you will know." — Dr. Seuss',
    '"Learning never exhausts the mind." — Leonardo da Vinci',
    '"Strive not to be a success, but rather to be of value." — Albert Einstein',
    '"The expert in anything was once a beginner." — Helen Hayes',
    '"A journey of a thousand miles begins with a single step." — Lao Tzu',
  ];
}
