import 'package:aura_mobile/core/services/duckduckgo_service.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final webServiceProvider = Provider((ref) => WebService(
  ref.read(duckDuckGoServiceProvider),
));

class WebService {
  final DuckDuckGoService _duckDuckGo;
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  WebService(this._duckDuckGo);

  /// Search the web with error handling
  Future<List<SearchResult>> search(String message) async {
    try {
      // Extract and clean query
      String query = _extractSearchQuery(message);

      if (query.trim().isEmpty) {
        throw ValidationException.emptyInput('Search query');
      }

      _errorHandler.logInfo('Web search: $query');

      final results = await _duckDuckGo.search(query);

      if (results.isEmpty) {
        _errorHandler.logWarning('Web search returned no results for: $query');
      } else {
        _errorHandler.logInfo('Web search found ${results.length} results');
      }

      return results;
    } catch (e) {
      if (e is AuraException) {
        _errorHandler.handleError(e);
        rethrow;
      }

      _errorHandler.logWarning('Web search error: $e');
      throw NetworkException.searchFailed(message, e);
    }
  }

  /// Scrape a URL with error handling
  Future<SearchResult> scrapeUrl(String url) async {
    try {
      _errorHandler.logInfo('Scraping URL: $url');
      return await _duckDuckGo.scrapeUrl(url);
    } catch (e) {
      if (e is AuraException) {
        _errorHandler.handleError(e);
        rethrow;
      }

      _errorHandler.logWarning('URL scraping error: $e');
      throw NetworkException.scrapeFailed(url, e);
    }
  }

  /// Extract clean search query from message
  String _extractSearchQuery(String message) {
    String query = message.trim();

    // Remove common search prefixes
    final prefixes = [
      'search for ',
      'search ',
      'look up ',
      'find ',
      'what is ',
      'what are ',
      'who is ',
      'when is ',
      'where is ',
      'why is ',
      'how to ',
      'how do i ',
    ];

    final lowerQuery = query.toLowerCase();
    for (var prefix in prefixes) {
      if (lowerQuery.startsWith(prefix)) {
        query = query.substring(prefix.length).trim();
        break;
      }
    }

    return query;
  }
}
