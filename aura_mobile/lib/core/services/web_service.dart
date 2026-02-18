import 'package:aura_mobile/core/services/duckduckgo_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final webServiceProvider = Provider((ref) => WebService(ref.read(duckDuckGoServiceProvider)));

class WebService {
  final DuckDuckGoService _duckDuckGo;

  WebService(this._duckDuckGo);

  Future<List<SearchResult>> search(String message) async {
    // Extract search query by removing 'search' prefix if present
    String query = message;
    if (message.toLowerCase().startsWith('search ')) {
      query = message.substring(7).trim();
    }
    
    print('WEB_SERVICE: Searching for: $query');
    return await _duckDuckGo.search(query);
  }
}
