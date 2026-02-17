import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/data/datasources/database_helper.dart';
import 'package:aura_mobile/data/repositories/memory_repository_impl.dart';
import 'package:aura_mobile/data/repositories/chat_history_repository_impl.dart';
import 'package:aura_mobile/domain/repositories/memory_repository.dart';
import 'package:aura_mobile/domain/repositories/chat_history_repository.dart';

// Database Provider
final databaseHelperProvider = Provider((ref) => DatabaseHelper());

// Repository Providers
final memoryRepositoryProvider = Provider<MemoryRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return MemoryRepositoryImpl(dbHelper);
});

final chatHistoryRepositoryProvider = Provider<ChatHistoryRepository>((ref) {
  return ChatHistoryRepositoryImpl();
});
