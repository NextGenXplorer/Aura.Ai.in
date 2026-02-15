import 'package:aura_mobile/features/agents/domain/agent.dart';
import 'package:aura_mobile/core/services/duckduckgo_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final searchAgentProvider = Provider((ref) => SearchAgent(ref.read(duckDuckGoServiceProvider)));

class SearchAgent implements Agent {
  final DuckDuckGoService _searchService;

  SearchAgent(this._searchService);

  @override
  String get name => 'SearchAgent';

  @override
  Future<bool> canHandle(String intent) async {
    return intent == 'web_search';
  }

  @override
  Stream<String> process(String input, {Map<String, dynamic>? context}) async* {
    print("SEARCH_AGENT: Processing input: '$input'");
    final trimmedInput = input.trim();
    // Simple heuristic for URL: No spaces, contains a dot, and length > 3
    final isUrl = !trimmedInput.contains(' ') && trimmedInput.contains('.') && trimmedInput.length > 4;
    print("SEARCH_AGENT: isUrl=$isUrl (input='$trimmedInput')");

    if (isUrl) {
       yield "Navigating to: \"$trimmedInput\"...\n\n";
       try {
         final result = await _searchService.scrapeUrl(trimmedInput);
         yield "**${result.title}**\n";
         yield "*(Content from ${result.url})*\n\n";
         yield "${result.snippet}\n\n";
         yield "[View Original](${result.url})\n";
       } catch (e) {
         yield "I couldn't read the content from that URL: $e";
       }
       return;
    }

    yield "Searching the web for: \"$trimmedInput\"...\n\n";

    try {
      final results = await _searchService.search(trimmedInput);

      if (results.isEmpty) {
        yield "I couldn't find any results for that query.";
        return;
      }

      // Synthesize a summary (for now, just listing top results)
      // In a full RAG system, we would feed this to the LLM to summarize.
      // For this step, we will display the results directly.
      
      yield "Here is what I found:\n\n";
      
      for (var i = 0; i < results.length && i < 5; i++) {
        final result = results[i];
        yield "**${result.title}**\n";
        yield "${result.snippet}\n";
        yield "[Source](${result.url})\n\n";
      }
      
    } catch (e) {
      yield "I encountered an error while searching: $e";
    }
  }
}
