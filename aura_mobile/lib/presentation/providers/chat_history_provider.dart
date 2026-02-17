
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/domain/repositories/chat_history_repository.dart';
import 'package:aura_mobile/core/providers/repository_providers.dart';

final chatHistoryProvider = FutureProvider<List<ChatSession>>((ref) async {
  final repo = ref.watch(chatHistoryRepositoryProvider);
  return repo.getSessions();
});
