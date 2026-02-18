import 'package:aura_mobile/core/services/duckduckgo_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final scraperServiceProvider = Provider((ref) => ScraperService(ref.read(duckDuckGoServiceProvider)));

class ScraperService {
  final DuckDuckGoService _duckDuckGo;

  ScraperService(this._duckDuckGo);

  Future<SearchResult> scrape(String message) async {
    // Extract URL from message (Relaxed regex to match IntentDetectionService)
    final urlRegex = RegExp(
      r'((https?:\/\/)|(www\.)|([-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-z]{2,6}))[^\s]*',
      caseSensitive: false
    );
    final match = urlRegex.firstMatch(message);
    
    if (match != null) {
      final url = match.group(0)!;
      print('SCRAPER_SERVICE: Extracting content from: $url');
      return await _duckDuckGo.scrapeUrl(url);
    }
    
    // If no URL found, try treating the whole message as a URL if it looks like one
    if (message.contains('.') && !message.contains(' ')) {
       print('SCRAPER_SERVICE: Attempting to scrape: $message');
       return await _duckDuckGo.scrapeUrl(message);
    }
    
    throw Exception('No URL found in message to scrape');
  }
}
