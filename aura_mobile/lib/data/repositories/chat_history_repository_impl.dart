
import 'dart:convert';
import 'dart:io';
import 'package:aura_mobile/domain/repositories/chat_history_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatHistoryRepositoryImpl implements ChatHistoryRepository {
  static const String _sessionsKey = 'chat_sessions_index';

  @override
  Future<List<ChatSession>> getSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? sessionsJson = prefs.getString(_sessionsKey);
    if (sessionsJson == null) return [];
    
    final List<dynamic> decoded = jsonDecode(sessionsJson);
    return decoded.map((json) => ChatSession.fromJsonMetadata(json)).toList()
      ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
  }

  @override
  Future<void> saveSession(ChatSession session) async {
    // 1. Save Content to File
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/chat_${session.id}.json');
    await file.writeAsString(jsonEncode(session.toJson()));

    // 2. Update Index in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final sessions = await getSessions();
    final index = sessions.indexWhere((s) => s.id == session.id);
    
    if (index != -1) {
      sessions[index] = session;
    } else {
      sessions.add(session);
    }
    
    final List<Map<String, dynamic>> sessionsMetadata = sessions
        .map((s) => s.toJsonMetadata())
        .toList();
        
    await prefs.setString(_sessionsKey, jsonEncode(sessionsMetadata));
  }

  @override
  Future<ChatSession?> getSession(String sessionId) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/chat_$sessionId.json');
      if (!await file.exists()) return null;
      
      final content = await file.readAsString();
      return ChatSession.fromJson(jsonDecode(content));
    } catch (e) {
      print("Error loading session $sessionId: $e");
      return null;
    }
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    // 1. Delete File
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/chat_$sessionId.json');
    if (await file.exists()) {
      await file.delete();
    }

    // 2. Remove from Index
    final prefs = await SharedPreferences.getInstance();
    final sessions = await getSessions();
    sessions.removeWhere((s) => s.id == sessionId);
    
    final List<Map<String, dynamic>> sessionsMetadata = sessions
        .map((s) => s.toJsonMetadata())
        .toList();
        
    await prefs.setString(_sessionsKey, jsonEncode(sessionsMetadata));
  }
}
