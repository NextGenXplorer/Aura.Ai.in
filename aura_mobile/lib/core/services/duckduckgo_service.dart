import 'package:dio/dio.dart';
import 'package:html/parser.dart' as parser;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';

final duckDuckGoServiceProvider = Provider((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    },
  ));

  return DuckDuckGoService(dio);
});

class DuckDuckGoService {
  final Dio _dio;
  final ErrorHandlerService _errorHandler = ErrorHandlerService();
  final Connectivity _connectivity = Connectivity();

  DuckDuckGoService(this._dio);

  /// Search DuckDuckGo with robust error handling and retry logic
  Future<List<SearchResult>> search(String query) async {
    // Validation
    if (query.trim().isEmpty) {
      throw ValidationException.emptyInput('Search query');
    }

    // Check connectivity first
    await _checkConnectivity();

    try {
      return await _errorHandler.executeWithRetry(
        operation: () => _performSearch(query),
        operationName: 'DuckDuckGo search',
        maxAttempts: 3,
        onFinalError: (error) {
          _errorHandler.logWarning('Search failed after retries: $error');
          return <SearchResult>[];
        },
      ) ?? [];
    } catch (e) {
      if (e is AuraException) {
        rethrow;
      }
      throw NetworkException.searchFailed(query, e);
    }
  }

  Future<List<SearchResult>> _performSearch(String query) async {
    try {
      final response = await _dio.get(
        'https://html.duckduckgo.com/html/',
        queryParameters: {'q': query},
      );

      if (response.statusCode == 200) {
        return _parseSearchResults(response.data);
      } else if (response.statusCode == 429) {
        throw NetworkException(
          message: 'Too many requests',
          technicalDetails: 'Rate limited by DuckDuckGo',
          recoverySuggestion: 'Please wait a moment before searching again',
          errorCode: 'NETWORK_RATE_LIMITED',
        );
      } else {
        throw NetworkException.httpError(response.statusCode!, response.realUri.toString());
      }
    } on DioException catch (e) {
      throw _handleDioError(e, 'search');
    }
  }

  List<SearchResult> _parseSearchResults(String html) {
    try {
      final document = parser.parse(html);
      final results = <SearchResult>[];

      final resultElements = document.getElementsByClassName('result');

      for (var element in resultElements) {
        try {
          final titleElement = element.querySelector('.result__a');
          final snippetElement = element.querySelector('.result__snippet');
          final urlElement = element.querySelector('.result__url');

          if (titleElement != null && snippetElement != null) {
            String url = titleElement.attributes['href'] ??
                         urlElement?.text.trim() ?? '';

            if (url.isNotEmpty && !url.startsWith('http')) {
              url = 'https://$url';
            }

            if (url.isNotEmpty) {
              results.add(SearchResult(
                title: titleElement.text.trim(),
                snippet: snippetElement.text.trim(),
                url: url,
              ));
            }
          }
        } catch (e) {
          _errorHandler.logDebug('Failed to parse search result element: $e');
          // Continue parsing other results
        }
      }

      _errorHandler.logInfo('Parsed ${results.length} search results');
      return results;
    } catch (e) {
      _errorHandler.logWarning('Search result parsing failed: $e');
      return [];
    }
  }

  /// Scrape a URL with robust error handling
  Future<SearchResult> scrapeUrl(String url) async {
    // Validation
    if (url.trim().isEmpty) {
      throw ValidationException.emptyInput('URL');
    }

    // Check connectivity
    await _checkConnectivity();

    try {
      return await _errorHandler.executeWithRetry(
        operation: () => _performScrape(url),
        operationName: 'URL scrape',
        maxAttempts: 2,
      ) ?? SearchResult(
        title: 'Error',
        snippet: 'Failed to load page',
        url: url,
      );
    } catch (e) {
      if (e is AuraException) {
        rethrow;
      }
      throw NetworkException.scrapeFailed(url, e);
    }
  }

  Future<SearchResult> _performScrape(String url) async {
    // Ensure protocol is present
    String targetUrl = url;
    if (!url.startsWith('http')) {
      targetUrl = 'https://$url';
    }

    try {
      final response = await _dio.get(
        targetUrl,
        options: Options(
          validateStatus: (status) => status != null && status < 500,
          followRedirects: true,
          maxRedirects: 3,
        ),
      );

      if (response.statusCode == 200) {
        return _parseWebPage(response.data, targetUrl);
      } else if (response.statusCode == 403) {
        throw NetworkException(
          message: 'Access denied',
          technicalDetails: 'Website blocked access (403)',
          recoverySuggestion: 'This website may be blocking automated access',
          errorCode: 'NETWORK_ACCESS_DENIED',
        );
      } else if (response.statusCode == 404) {
        throw NetworkException(
          message: 'Page not found',
          technicalDetails: 'HTTP 404 from $targetUrl',
          recoverySuggestion: 'Check if the URL is correct',
          errorCode: 'NETWORK_HTTP_404',
        );
      } else {
        throw NetworkException.httpError(response.statusCode!, targetUrl);
      }
    } on DioException catch (e) {
      throw _handleDioError(e, 'scrape');
    }
  }

  SearchResult _parseWebPage(String html, String url) {
    try {
      final document = parser.parse(html);

      // Remove non-content elements
      document.querySelectorAll('script, style, nav, footer, header, aside')
          .forEach((element) => element.remove());

      final title = document.querySelector('title')?.text.trim() ??
                   document.querySelector('h1')?.text.trim() ??
                   url;

      // Extract meaningful text
      final buffer = StringBuffer();
      document.querySelectorAll('h1, h2, h3, p, li').forEach((element) {
        final text = element.text.trim();
        if (text.isNotEmpty && text.length > 10) {
          buffer.writeln(text);
          buffer.writeln();
        }
      });

      String content = buffer.toString().trim();

      if (content.isEmpty) {
        // Fallback: get all text
        content = document.body?.text.trim() ?? 'No readable content found';
      }

      // Truncate long content
      const maxLength = 2000;
      if (content.length > maxLength) {
        content = '${content.substring(0, maxLength)}...\n\n(Content truncated)';
      }

      return SearchResult(
        title: title,
        snippet: content,
        url: url,
      );
    } catch (e) {
      _errorHandler.logWarning('Web page parsing failed: $e');
      return SearchResult(
        title: 'Parse Error',
        snippet: 'Failed to extract readable content from page',
        url: url,
      );
    }
  }

  /// Check network connectivity before making requests
  Future<void> _checkConnectivity() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();

      if (connectivityResult.contains(ConnectivityResult.none)) {
        throw NetworkException.noConnection();
      }
    } catch (e) {
      if (e is NetworkException) {
        rethrow;
      }
      _errorHandler.logWarning('Connectivity check failed: $e');
      // Continue anyway - connectivity check might fail but network might work
    }
  }

  /// Handle Dio-specific errors
  NetworkException _handleDioError(DioException error, String operation) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkException.timeout(error.requestOptions.uri.toString());

      case DioExceptionType.connectionError:
        return NetworkException.noConnection();

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode ?? 0;
        return NetworkException.httpError(
          statusCode,
          error.requestOptions.uri.toString(),
        );

      case DioExceptionType.cancel:
        return NetworkException(
          message: 'Request was cancelled',
          technicalDetails: 'User or system cancelled the request',
          recoverySuggestion: 'Please try again',
          errorCode: 'NETWORK_CANCELLED',
        );

      default:
        return NetworkException(
          message: 'Network error during $operation',
          technicalDetails: error.toString(),
          recoverySuggestion: 'Check your internet connection and try again',
          errorCode: 'NETWORK_UNKNOWN_ERROR',
        );
    }
  }
}

class SearchResult {
  final String title;
  final String snippet;
  final String url;

  SearchResult({
    required this.title,
    required this.snippet,
    required this.url,
  });

  @override
  String toString() {
    return 'Title: $title\nURL: $url\nSnippet: $snippet\n';
  }
}
