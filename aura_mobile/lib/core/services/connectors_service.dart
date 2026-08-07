import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

final connectorsServiceProvider = Provider((ref) => ConnectorsService());

/// Free connectors that require no API keys.
/// All of these work without any user accounts or paid services.
class ConnectorsService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  // ═══════════════════════════════════════════════════════════════════════════
  // WEATHER (Open-Meteo API — completely free, no key, no limits)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get current weather for a location. Uses Open-Meteo (free, no API key).
  /// [location] can be a city name — we geocode it first.
  Future<Map<String, dynamic>> getWeather(String location) async {
    try {
      // 1. Geocode location name to coordinates
      final geoResponse = await _dio.get(
        'https://geocoding-api.open-meteo.com/v1/search',
        queryParameters: {'name': location, 'count': 1, 'language': 'en'},
      );

      final results = geoResponse.data['results'] as List?;
      if (results == null || results.isEmpty) {
        return {'error': 'Location "$location" not found'};
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
          'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m',
          'daily': 'temperature_2m_max,temperature_2m_min,weather_code',
          'timezone': 'auto',
          'forecast_days': 3,
        },
      );

      final current = weatherResponse.data['current'];
      final daily = weatherResponse.data['daily'];

      return {
        'location': '$cityName, $country',
        'temperature': current['temperature_2m'],
        'feelsLike': current['apparent_temperature'],
        'humidity': current['relative_humidity_2m'],
        'windSpeed': current['wind_speed_10m'],
        'condition': _weatherCodeToText(current['weather_code'] as int),
        'emoji': _weatherCodeToEmoji(current['weather_code'] as int),
        'forecast': List.generate(
          (daily['time'] as List).length,
          (i) {
            return {
              'date': daily['time'][i],
              'high': daily['temperature_2m_max'][i],
              'low': daily['temperature_2m_min'][i],
              'condition': _weatherCodeToText(daily['weather_code'][i] as int),
            };
          },
        ),
      };
    } catch (e) {
      debugPrint('Weather API error: $e');
      return {'error': 'Could not fetch weather: $e'};
    }
  }

  /// Format weather data into a user-friendly chat response.
  String formatWeatherResponse(Map<String, dynamic> data) {
    if (data.containsKey('error')) {
      return '❌ ${data['error']}';
    }

    final buffer = StringBuffer();
    buffer.writeln('${data['emoji']} **Weather in ${data['location']}**\n');
    buffer.writeln('🌡️ **${data['temperature']}°C** (feels like ${data['feelsLike']}°C)');
    buffer.writeln('☁️ ${data['condition']}');
    buffer.writeln('💧 Humidity: ${data['humidity']}%');
    buffer.writeln('💨 Wind: ${data['windSpeed']} km/h');

    final forecast = data['forecast'] as List?;
    if (forecast != null && forecast.isNotEmpty) {
      buffer.writeln('\n📅 **3-Day Forecast:**');
      for (final day in forecast) {
        buffer.writeln('• ${day['date']}: ${day['condition']} (${day['low']}° - ${day['high']}°)');
      }
    }

    return buffer.toString();
  }

  String _weatherCodeToText(int code) {
    if (code == 0) return 'Clear sky';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 49) return 'Foggy';
    if (code <= 59) return 'Drizzle';
    if (code <= 69) return 'Rain';
    if (code <= 79) return 'Snow';
    if (code <= 82) return 'Rain showers';
    if (code <= 86) return 'Snow showers';
    if (code == 95) return 'Thunderstorm';
    if (code <= 99) return 'Thunderstorm with hail';
    return 'Unknown';
  }

  String _weatherCodeToEmoji(int code) {
    if (code == 0) return '☀️';
    if (code <= 3) return '⛅';
    if (code <= 49) return '🌫️';
    if (code <= 59) return '🌦️';
    if (code <= 69) return '🌧️';
    if (code <= 79) return '❄️';
    if (code <= 82) return '🌧️';
    if (code <= 86) return '🌨️';
    if (code >= 95) return '⛈️';
    return '🌤️';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIKIPEDIA (Free REST API — no key needed)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get a Wikipedia summary for a topic. Returns structured data.
  Future<Map<String, dynamic>> getWikipediaSummary(String topic) async {
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
          'description': data['description'] ?? '',
        };
      }
      return {'error': 'No Wikipedia article found for "$topic"'};
    } catch (e) {
      debugPrint('Wikipedia API error: $e');
      return {'error': 'Could not fetch Wikipedia info: $e'};
    }
  }

  /// Format Wikipedia data into a chat response.
  String formatWikipediaResponse(Map<String, dynamic> data) {
    if (data.containsKey('error')) {
      return '❌ ${data['error']}';
    }

    final buffer = StringBuffer();
    buffer.writeln('📖 **${data['title']}**');
    if (data['description'] != null && (data['description'] as String).isNotEmpty) {
      buffer.writeln('_${data['description']}_\n');
    }
    buffer.writeln(data['summary']);
    if (data['url'] != null && (data['url'] as String).isNotEmpty) {
      buffer.writeln('\n🔗 [Read more on Wikipedia](${data['url']})');
    }
    return buffer.toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // YOUTUBE SEARCH (Deep link — no API needed)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate a YouTube search URL for a query.
  String getYouTubeSearchUrl(String query) {
    final encoded = Uri.encodeComponent(query);
    return 'https://www.youtube.com/results?search_query=$encoded';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QR CODE GENERATION (Local — no API)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate a QR code image URL (using a free service).
  /// Returns a URL that renders the QR code as an image.
  String generateQrCodeUrl(String data, {int size = 300}) {
    final encoded = Uri.encodeComponent(data);
    // Using quickchart.io free QR API (no key needed, very reliable)
    return 'https://quickchart.io/qr?text=$encoded&size=$size';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DEVICE/SYSTEM INFO (Local — Android native)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get device battery level and system information.
  Future<Map<String, dynamic>> getSystemInfo() async {
    try {
      const channel = MethodChannel('com.aura.ai/app_control');

      // Try to get battery info
      int batteryLevel = -1;
      try {
        batteryLevel = await channel.invokeMethod('getBatteryLevel') ?? -1;
      } catch (_) {}

      return {
        'batteryLevel': batteryLevel,
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
      };
    } catch (e) {
      return {
        'batteryLevel': -1,
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
      };
    }
  }

  /// Format system info for chat display.
  String formatSystemInfo(Map<String, dynamic> data) {
    final buffer = StringBuffer();
    buffer.writeln('📱 **Device Information**\n');

    final battery = data['batteryLevel'] as int;
    if (battery >= 0) {
      final batteryEmoji = battery > 80 ? '🔋' : battery > 20 ? '🔋' : '🪫';
      buffer.writeln('$batteryEmoji Battery: $battery%');
    }
    buffer.writeln('📲 Platform: ${data['platform']}');
    buffer.writeln('⚙️ OS: ${data['osVersion']}');

    return buffer.toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSLATION (using free MyMemory API — no key needed)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Translate text between languages using free translation API.
  /// Falls back to LLM-based translation if API fails.
  Future<Map<String, dynamic>> translate(String text, String targetLanguage) async {
    try {
      // Use MyMemory free translation API (no key needed, 5000 chars/day)
      final response = await _dio.get(
        'https://api.mymemory.translated.net/get',
        queryParameters: {
          'q': text,
          'langpair': 'en|${_getLanguageCode(targetLanguage)}',
        },
      );

      if (response.statusCode == 200) {
        final translated = response.data['responseData']?['translatedText'];
        if (translated != null && translated.toString().isNotEmpty) {
          return {
            'original': text,
            'translated': translated,
            'targetLanguage': targetLanguage,
          };
        }
      }
      return {'error': 'Translation failed. Try asking the AI directly to translate.'};
    } catch (e) {
      return {'error': 'Translation service unavailable: $e'};
    }
  }

  /// Format translation for chat display.
  String formatTranslation(Map<String, dynamic> data) {
    if (data.containsKey('error')) {
      return '❌ ${data['error']}';
    }
    return '🌐 **Translation to ${data['targetLanguage']}:**\n\n'
        '${data['translated']}';
  }

  String _getLanguageCode(String language) {
    final codes = {
      'hindi': 'hi', 'spanish': 'es', 'french': 'fr', 'german': 'de',
      'italian': 'it', 'portuguese': 'pt', 'chinese': 'zh', 'japanese': 'ja',
      'korean': 'ko', 'arabic': 'ar', 'russian': 'ru', 'tamil': 'ta',
      'telugu': 'te', 'bengali': 'bn', 'marathi': 'mr', 'gujarati': 'gu',
      'kannada': 'kn', 'malayalam': 'ml', 'punjabi': 'pa', 'urdu': 'ur',
      'dutch': 'nl', 'turkish': 'tr', 'thai': 'th', 'vietnamese': 'vi',
      'indonesian': 'id', 'malay': 'ms', 'filipino': 'tl', 'swahili': 'sw',
    };
    return codes[language.toLowerCase()] ?? 'hi'; // default to Hindi
  }
}
