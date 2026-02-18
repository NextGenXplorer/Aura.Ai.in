import 'package:aura_mobile/core/services/duckduckgo_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final scraperServiceProvider = Provider((ref) => ScraperService(ref.read(duckDuckGoServiceProvider)));

class ScraperService {
  final DuckDuckGoService _duckDuckGo;

  ScraperService(this._duckDuckGo);

  Future<SearchResult> scrape(String message) async {
    // Extract URL from message
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+)', caseSensitive: false);
    final match = urlRegex.firstMatch(message);
    
    if (match != null) {
      final url = match.group(0)!;
      print('SCRAPER_SERVICE: Extracting content from: $url');
      return await _duckDuckGo.scrapeUrl(url);
    }
    
    throw Exception('No URL found in message to scrape');
  }
}
