import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final userProvider = StateNotifierProvider<UserNotifier, AsyncValue<String>>((ref) {
  return UserNotifier();
});

class UserNotifier extends StateNotifier<AsyncValue<String>> {
  UserNotifier() : super(const AsyncValue.loading()) {
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('user_name') ?? 'User';
      state = AsyncValue.data(name);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}
