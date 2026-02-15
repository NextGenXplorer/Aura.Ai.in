import 'package:dio/dio.dart';
import 'package:html/parser.dart' as parser;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final duckDuckGoServiceProvider = Provider((ref) => DuckDuckGoService(Dio()));

class DuckDuckGoService {
  final Dio _dio;

  DuckDuckGoService(this._dio);

  Future<List<SearchResult>> search(String query) async {
    try {
      final response = await _dio.get(
        'https://html.duckduckgo.com/html/',
        queryParameters: {'q': query},
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          },
        ),
      );

      if (response.statusCode == 200) {
        final document = parser.parse(response.data);
        final results = <SearchResult>[];

        // DuckDuckGo HTML structure usually wraps results in .result
        final resultElements = document.getElementsByClassName('result');

        for (var element in resultElements) {
          final titleElement = element.querySelector('.result__a');
          final snippetElement = element.querySelector('.result__snippet');
          final urlElement = element.querySelector('.result__url');

          if (titleElement != null && snippetElement != null) {
            String url = titleElement.attributes['href'] ?? urlElement?.text.trim() ?? '';
            if (url.isNotEmpty && !url.startsWith('http')) {
              url = 'https://$url';
            }

            results.add(SearchResult(
              title: titleElement.text.trim(),
              snippet: snippetElement.text.trim(),
              url: url,
            ));
          }
        }
        return results;
      } else {
        throw Exception('Failed to load search results: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('DuckDuckGo Search Failed: $e');
    }
  }

  Future<SearchResult> scrapeUrl(String url) async {
    try {
      // Ensure protocol is present
      String targetUrl = url;
      if (!url.startsWith('http')) {
        targetUrl = 'https://$url';
      }

      final response = await _dio.get(
        targetUrl,
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        final document = parser.parse(response.data);
        
        // Remove script and style elements
        document.querySelectorAll('script, style, nav, footer, header').forEach((element) => element.remove());
        
        final title = document.querySelector('title')?.text.trim() ?? url;
        
        // Extract meaningful text (paragraphs and headings)
        final buffer = StringBuffer();
        document.querySelectorAll('h1, h2, h3, p').forEach((element) {
          final text = element.text.trim();
          if (text.isNotEmpty) {
            buffer.writeln(text);
            buffer.writeln(); 
          }
        });
        
        String content = buffer.toString().trim();
        if (content.length > 2000) {
          content = "${content.substring(0, 2000)}...\n\n(Content truncated)";
        }
        
        if (content.isEmpty) {
           content = "No readable text content found on page.";
        }

        return SearchResult(
          title: title,
          snippet: content,
          url: targetUrl,
        );
      } else {
        throw Exception('Failed to load page: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to scrape URL: $e');
    }
  }
}

class SearchResult {
  final String title;
  final String snippet;
  final String url;

  SearchResult({required this.title, required this.snippet, required this.url});

  @override
  String toString() {
    return 'Title: $title\nURL: $url\nSnippet: $snippet\n';
  }
}
