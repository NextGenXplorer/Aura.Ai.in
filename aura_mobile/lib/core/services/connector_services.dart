import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:disk_space_2/disk_space_2.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// WEATHER SERVICE (Open-Meteo — free, no API key)
// ═══════════════════════════════════════════════════════════════════════════════

final weatherServiceProvider = Provider((ref) => WeatherService());

class WeatherService {
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  /// Get current weather for a city name.
  /// Uses Open-Meteo geocoding + weather API (100% free, no key).
  Future<Map<String, dynamic>> getWeather(String city) async {
    try {
      // 1. Geocode city name to lat/lon
      final geoResponse = await _dio.get(
        'https://geocoding-api.open-meteo.com/v1/search',
        queryParameters: {'name': city, 'count': 1},
      );

      final results = geoResponse.data['results'] as List?;
      if (results == null || results.isEmpty) {
        return {'error': 'City "$city" not found'};
      }

      final lat = results[0]['latitude'];
      final lon = results[0]['longitude'];
      final cityName = results[0]['name'];
      final country = results[0]['country'] ?? '';

      // 2. Get weather data
      final weatherResponse = await _dio.get(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': lat,
          'longitude': lon,
          'current': 'temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,apparent_temperature',
          'daily': 'temperature_2m_max,temperature_2m_min,weather_code',
          'forecast_days': 3,
          'timezone': 'auto',
        },
      );

      final current = weatherResponse.data['current'];
      final daily = weatherResponse.data['daily'];

      return {
        'city': cityName,
        'country': country,
        'temperature': current['temperature_2m'],
        'feelsLike': current['apparent_temperature'],
        'humidity': current['relative_humidity_2m'],
        'windSpeed': current['wind_speed_10m'],
        'weatherCode': current['weather_code'],
        'condition': _weatherCodeToText(current['weather_code']),
        'forecast': List.generate(3, (i) {
          return {
            'day': i == 0 ? 'Today' : i == 1 ? 'Tomorrow' : 'Day after',
            'high': daily['temperature_2m_max'][i],
            'low': daily['temperature_2m_min'][i],
            'condition': _weatherCodeToText(daily['weather_code'][i]),
          };
        }),
      };
    } catch (e) {
      debugPrint('WeatherService error: $e');
      return {'error': 'Failed to fetch weather: $e'};
    }
  }

  /// Format weather data into a readable string for the AI.
  String formatWeatherResponse(Map<String, dynamic> data) {
    if (data.containsKey('error')) return '❌ ${data['error']}';

    final buffer = StringBuffer();
    buffer.writeln('🌤️ **Weather in ${data['city']}, ${data['country']}**\n');
    buffer.writeln('**Now:** ${data['temperature']}°C (feels like ${data['feelsLike']}°C)');
    buffer.writeln('**Condition:** ${data['condition']}');
    buffer.writeln('**Humidity:** ${data['humidity']}%');
    buffer.writeln('**Wind:** ${data['windSpeed']} km/h\n');

    buffer.writeln('**3-Day Forecast:**');
    for (final day in (data['forecast'] as List)) {
      buffer.writeln('• ${day['day']}: ${day['high']}°C / ${day['low']}°C — ${day['condition']}');
    }

    return buffer.toString();
  }

  String _weatherCodeToText(int code) {
    if (code == 0) return 'Clear sky ☀️';
    if (code <= 3) return 'Partly cloudy ⛅';
    if (code <= 49) return 'Foggy 🌫️';
    if (code <= 59) return 'Drizzle 🌦️';
    if (code <= 69) return 'Rain 🌧️';
    if (code <= 79) return 'Snow ❄️';
    if (code <= 82) return 'Heavy rain 🌧️';
    if (code <= 86) return 'Heavy snow ❄️';
    if (code >= 95) return 'Thunderstorm ⛈️';
    return 'Unknown';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIKIPEDIA SERVICE (Free REST API, no key)
// ═══════════════════════════════════════════════════════════════════════════════

final wikipediaServiceProvider = Provider((ref) => WikipediaService());

class WikipediaService {
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  /// Get a summary of a Wikipedia article on a topic.
  Future<Map<String, dynamic>> getSummary(String topic) async {
    try {
      final encoded = Uri.encodeComponent(topic);
      final response = await _dio.get(
        'https://en.wikipedia.org/api/rest_v1/page/summary/$encoded',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        return {
          'title': data['title'] ?? topic,
          'summary': data['extract'] ?? 'No summary available.',
          'url': data['content_urls']?['desktop']?['page'] ?? '',
          'thumbnail': data['thumbnail']?['source'],
        };
      }
      return {'error': 'No Wikipedia article found for "$topic"'};
    } catch (e) {
      debugPrint('WikipediaService error: $e');
      return {'error': 'Failed to fetch from Wikipedia: $e'};
    }
  }

  /// Format Wikipedia data for chat display.
  String formatWikiResponse(Map<String, dynamic> data) {
    if (data.containsKey('error')) return '❌ ${data['error']}';

    final buffer = StringBuffer();
    buffer.writeln('📖 **${data['title']}** (Wikipedia)\n');
    buffer.writeln(data['summary']);
    if ((data['url'] as String).isNotEmpty) {
      buffer.writeln('\n[Read more on Wikipedia](${data['url']})');
    }
    return buffer.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEWS SERVICE (RSS feeds — free, no key)
// ═══════════════════════════════════════════════════════════════════════════════

final newsServiceProvider = Provider((ref) => NewsService());

class NewsService {
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  /// Get latest news headlines. Uses Google News RSS (free, no key).
  Future<List<Map<String, String>>> getHeadlines({String? query}) async {
    try {
      final url = query != null && query.isNotEmpty
          ? 'https://news.google.com/rss/search?q=${Uri.encodeComponent(query)}'
          : 'https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx1YlY4U0FtVnVHZ0pKVGlnQVAB';

      final response = await _dio.get(url);
      final xmlStr = response.data as String;

      // Simple XML parsing for RSS items
      final items = <Map<String, String>>[];
      final itemMatches = RegExp(r'<item>([\s\S]*?)</item>').allMatches(xmlStr);

      for (final match in itemMatches.take(10)) {
        final itemXml = match.group(1)!;
        final title = RegExp(r'<title>(.*?)</title>').firstMatch(itemXml)?.group(1) ?? '';
        final link = RegExp(r'<link>(.*?)</link>').firstMatch(itemXml)?.group(1) ?? '';
        final pubDate = RegExp(r'<pubDate>(.*?)</pubDate>').firstMatch(itemXml)?.group(1) ?? '';
        final source = RegExp(r'<source.*?>(.*?)</source>').firstMatch(itemXml)?.group(1) ?? '';

        if (title.isNotEmpty) {
          items.add({
            'title': _decodeHtmlEntities(title),
            'link': link,
            'date': pubDate,
            'source': source,
          });
        }
      }

      return items;
    } catch (e) {
      debugPrint('NewsService error: $e');
      return [];
    }
  }

  /// Format news for chat display.
  String formatNewsResponse(List<Map<String, String>> articles, {String? query}) {
    if (articles.isEmpty) return '❌ No news found${query != null ? ' for "$query"' : ''}.';

    final buffer = StringBuffer();
    buffer.writeln('📰 **${query != null ? 'News about "$query"' : 'Top Headlines'}**\n');

    for (int i = 0; i < articles.length && i < 7; i++) {
      final article = articles[i];
      buffer.writeln('${i + 1}. **${article['title']}**');
      if (article['source']!.isNotEmpty) buffer.writeln('   _${article['source']}_');
      buffer.writeln('');
    }

    return buffer.toString();
  }

  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// YOUTUBE SEARCH (Deep link — free)
// ═══════════════════════════════════════════════════════════════════════════════

final youtubeServiceProvider = Provider((ref) => YouTubeService());

class YouTubeService {
  /// Open YouTube search for a query.
  Future<void> searchOnYouTube(String query) async {
    final encoded = Uri.encodeComponent(query);
    final url = Uri.parse('https://www.youtube.com/results?search_query=$encoded');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// Open a specific YouTube video URL.
  Future<void> openVideo(String videoUrl) async {
    await launchUrl(Uri.parse(videoUrl), mode: LaunchMode.externalApplication);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOCATION / MAPS (Google Maps deep link — free)
// ═══════════════════════════════════════════════════════════════════════════════

final locationServiceProvider = Provider((ref) => LocationService());

class LocationService {
  /// Open Google Maps with directions to a destination.
  Future<void> navigateTo(String destination) async {
    final encoded = Uri.encodeComponent(destination);
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$encoded');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// Search for nearby places (restaurants, hospitals, etc.)
  Future<void> searchNearby(String query) async {
    final encoded = Uri.encodeComponent(query);
    final url = Uri.parse('https://www.google.com/maps/search/$encoded');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// Open a specific location on the map.
  Future<void> showOnMap(String place) async {
    final encoded = Uri.encodeComponent(place);
    final url = Uri.parse('geo:0,0?q=$encoded');
    try {
      await launchUrl(url);
    } catch (_) {
      // Fallback to Google Maps web
      await launchUrl(
        Uri.parse('https://www.google.com/maps/search/$encoded'),
        mode: LaunchMode.externalApplication,
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BATTERY / SYSTEM INFO (Android native — free)
// ═══════════════════════════════════════════════════════════════════════════════

final systemInfoServiceProvider = Provider((ref) => SystemInfoService());

class SystemInfoService {
  static const _batteryChannel = MethodChannel('com.aura.ai/battery');

  /// Get comprehensive system information.
  Future<Map<String, dynamic>> getSystemInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    double? freeSpace;
    try {
      freeSpace = await DiskSpace.getFreeDiskSpace;
    } catch (_) {}

    int batteryLevel = -1;
    try {
      batteryLevel = await _batteryChannel.invokeMethod('getBatteryLevel') ?? -1;
    } catch (_) {
      // Battery channel may not be implemented
    }

    return {
      'device': androidInfo.model,
      'brand': androidInfo.brand,
      'androidVersion': androidInfo.version.release,
      'sdkVersion': androidInfo.version.sdkInt,
      'totalRAM': androidInfo.systemFeatures.isNotEmpty ? 'Available' : 'Unknown',
      'freeStorage': freeSpace != null ? '${freeSpace.toStringAsFixed(1)} MB' : 'Unknown',
      'batteryLevel': batteryLevel >= 0 ? '$batteryLevel%' : 'Unknown',
      'securityPatch': androidInfo.version.securityPatch ?? 'Unknown',
      'fingerprint': androidInfo.fingerprint,
    };
  }

  /// Format system info for chat display.
  String formatSystemInfo(Map<String, dynamic> info) {
    final buffer = StringBuffer();
    buffer.writeln('📱 **Device Information**\n');
    buffer.writeln('**Device:** ${info['brand']} ${info['device']}');
    buffer.writeln('**Android:** ${info['androidVersion']} (SDK ${info['sdkVersion']})');
    buffer.writeln('**Battery:** ${info['batteryLevel']}');
    buffer.writeln('**Free Storage:** ${info['freeStorage']}');
    buffer.writeln('**Security Patch:** ${info['securityPatch']}');
    return buffer.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRANSLATION SERVICE (on-device via model — free)
// ═══════════════════════════════════════════════════════════════════════════════

final translationServiceProvider = Provider((ref) => TranslationService());

class TranslationService {
  /// Supported language names for display.
  static const supportedLanguages = [
    'English', 'Hindi', 'Spanish', 'French', 'German', 'Chinese',
    'Japanese', 'Korean', 'Arabic', 'Portuguese', 'Russian', 'Italian',
    'Tamil', 'Telugu', 'Kannada', 'Malayalam', 'Bengali', 'Marathi',
  ];

  /// Build a translation prompt for the LLM.
  /// The on-device model handles translation directly.
  String buildTranslationPrompt(String text, String targetLanguage) {
    return 'Translate the following text to $targetLanguage. '
        'Output ONLY the translation, nothing else.\n\n'
        'Text: $text\n\n'
        'Translation:';
  }

  /// Detect likely language of input text (basic heuristic).
  String detectLanguage(String text) {
    // Basic script detection
    if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return 'Hindi';
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return 'Tamil';
    if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(text)) return 'Telugu';
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return 'Kannada';
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(text)) return 'Malayalam';
    if (RegExp(r'[\u0980-\u09FF]').hasMatch(text)) return 'Bengali';
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(text)) return 'Chinese';
    if (RegExp(r'[\u3040-\u309F\u30A0-\u30FF]').hasMatch(text)) return 'Japanese';
    if (RegExp(r'[\uAC00-\uD7AF]').hasMatch(text)) return 'Korean';
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) return 'Arabic';
    if (RegExp(r'[\u0400-\u04FF]').hasMatch(text)) return 'Russian';
    return 'English';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// QR CODE SERVICE (scan + generate — free, local)
// ═══════════════════════════════════════════════════════════════════════════════

final qrCodeServiceProvider = Provider((ref) => QRCodeService());

class QRCodeService {
  /// Generate a QR code data URL for the given text/URL.
  /// Uses a simple API to generate QR image (can also be done offline with a package).
  String getQRCodeUrl(String data) {
    final encoded = Uri.encodeComponent(data);
    return 'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$encoded';
  }

  /// Format QR code response for chat (shows the QR as an inline image).
  String formatQRResponse(String data) {
    final url = getQRCodeUrl(data);
    return '📱 **QR Code Generated**\n\n'
        '![]($url)\n\n'
        'Content: `$data`';
  }
}
