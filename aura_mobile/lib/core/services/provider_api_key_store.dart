import 'package:aura_mobile/domain/entities/online_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores user-supplied provider keys in the platform keystore/keychain.
/// Keys are never written to SharedPreferences or application logs.
class ProviderApiKeyStore {
  final FlutterSecureStorage _storage;

  ProviderApiKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  String _key(OnlineProvider provider) => 'aura_api_key_${provider.id}';

  Future<String?> read(OnlineProvider provider) async {
    final value = await _storage.read(key: _key(provider));
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<bool> hasKey(OnlineProvider provider) async =>
      await read(provider) != null;

  Future<void> write(OnlineProvider provider, String apiKey) async {
    final value = apiKey.trim();
    if (value.isEmpty) {
      throw ArgumentError('API key cannot be empty.');
    }
    await _storage.write(key: _key(provider), value: value);
  }

  Future<void> delete(OnlineProvider provider) =>
      _storage.delete(key: _key(provider));
}
