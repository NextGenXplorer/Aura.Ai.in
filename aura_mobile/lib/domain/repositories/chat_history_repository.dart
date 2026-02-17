
abstract class ChatHistoryRepository {
  Future<List<ChatSession>> getSessions();
  Future<void> saveSession(ChatSession session);
  Future<void> deleteSession(String sessionId);
  Future<ChatSession?> getSession(String sessionId);
}


class ChatSession {
  final String id;
  final String title;
  final DateTime lastModified;
  final List<Map<String, String>> messages;
  
  ChatSession({
    required this.id,
    required this.title,
    required this.lastModified,
    required this.messages,
  });

  // Metadata only (for list)
  factory ChatSession.fromJsonMetadata(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'],
      title: json['title'],
      lastModified: DateTime.parse(json['lastModified']),
      messages: [], // Content not loaded in metadata
    );
  }

  // Full object (from file)
  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'],
      title: json['title'],
      lastModified: DateTime.parse(json['lastModified']),
      messages: (json['messages'] as List<dynamic>)
          .map((m) => Map<String, String>.from(m))
          .toList(),
    );
  }

  Map<String, dynamic> toJsonMetadata() {
    return {
      'id': id,
      'title': title,
      'lastModified': lastModified.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'lastModified': lastModified.toIso8601String(),
      'messages': messages,
    };
  }
}
