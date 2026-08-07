import 'dart:convert';

import 'package:aura_mobile/domain/entities/online_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalModelSelection {
  final String id;
  final String name;
  final String path;

  const LocalModelSelection({
    required this.id,
    required this.name,
    required this.path,
  });

  Map<String, Object> toJson() => {'id': id, 'name': name, 'path': path};

  static LocalModelSelection? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final id = map['id']?.toString() ?? '';
    final path = map['path']?.toString() ?? '';
    if (id.isEmpty || path.isEmpty) return null;
    return LocalModelSelection(
      id: id,
      name: map['name']?.toString() ?? id,
      path: path,
    );
  }
}

class OnlineModelSelection {
  final OnlineProvider provider;
  final String id;
  final String name;
  final int contextLength;
  final bool isExplicitlyFree;
  final bool supportsVision;
  final bool supportsToolCalling;

  const OnlineModelSelection({
    required this.provider,
    required this.id,
    required this.name,
    required this.contextLength,
    required this.isExplicitlyFree,
    required this.supportsVision,
    required this.supportsToolCalling,
  });

  factory OnlineModelSelection.fromModel(OnlineModel model) {
    return OnlineModelSelection(
      provider: model.provider,
      id: model.id,
      name: model.name,
      contextLength: model.contextLength,
      isExplicitlyFree: model.isExplicitlyFree,
      supportsVision: model.supportsVision,
      supportsToolCalling: false,
    );
  }

  OnlineModel toModel() => OnlineModel(
    provider: provider,
    id: id,
    name: name,
    contextLength: contextLength,
    isExplicitlyFree: isExplicitlyFree,
    supportsVision: supportsVision,
    supportsToolCalling: supportsToolCalling,
    isChatCapable: true,
    description: provider.availabilityNote,
  );

  Map<String, Object> toJson() => {
    'provider': provider.id,
    'id': id,
    'name': name,
    'contextLength': contextLength,
    'isExplicitlyFree': isExplicitlyFree,
    'supportsVision': supportsVision,
    'supportsToolCalling': supportsToolCalling,
  };

  static OnlineModelSelection? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final provider = OnlineProvider.fromId(map['provider']?.toString());
    final id = map['id']?.toString() ?? '';
    if (provider == null || id.isEmpty) return null;
    return OnlineModelSelection(
      provider: provider,
      id: id,
      name: map['name']?.toString() ?? id,
      contextLength: map['contextLength'] is int
          ? map['contextLength'] as int
          : 8192,
      isExplicitlyFree: map['isExplicitlyFree'] == true,
      supportsVision: map['supportsVision'] == true,
      supportsToolCalling: false,
    );
  }
}

class LLMSelectionSnapshot {
  final String? activeBackend;
  final LocalModelSelection? local;
  final OnlineModelSelection? online;

  const LLMSelectionSnapshot({this.activeBackend, this.local, this.online});

  LLMSelectionSnapshot copyWith({
    String? activeBackend,
    bool clearActiveBackend = false,
    LocalModelSelection? local,
    bool clearLocal = false,
    OnlineModelSelection? online,
    bool clearOnline = false,
  }) {
    return LLMSelectionSnapshot(
      activeBackend: clearActiveBackend
          ? null
          : activeBackend ?? this.activeBackend,
      local: clearLocal ? null : local ?? this.local,
      online: clearOnline ? null : online ?? this.online,
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'activeBackend': activeBackend,
    'local': local?.toJson(),
    'online': online?.toJson(),
  };
}

class LLMSelectionStore {
  static const snapshotKey = 'llm_selection_v1';
  static const localIdKey = 'active_local_model_id';
  static const localPathKey = 'selected_local_model_path';

  Future<LLMSelectionSnapshot> read() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(snapshotKey);
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          return LLMSelectionSnapshot(
            activeBackend: map['activeBackend']?.toString(),
            local: LocalModelSelection.fromJson(map['local']),
            online: OnlineModelSelection.fromJson(map['online']),
          );
        }
      } catch (_) {
        // Migrate from the legacy keys below if the snapshot is unreadable.
      }
    }

    final legacyBackend = prefs.getString('active_llm_backend');
    final legacyActiveId = prefs.getString('active_model_id');
    final localPath =
        prefs.getString(localPathKey) ?? prefs.getString('selected_model_path');
    final localId =
        prefs.getString(localIdKey) ??
        (legacyActiveId?.startsWith('online:') == false
            ? legacyActiveId
            : prefs.getString('selected_model_id'));
    final local = localId != null && localPath != null
        ? LocalModelSelection(id: localId, name: localId, path: localPath)
        : null;

    final provider = OnlineProvider.fromId(
      prefs.getString('active_online_provider'),
    );
    final onlineId = prefs.getString('active_online_model_id');
    final online = provider != null && onlineId != null
        ? OnlineModelSelection(
            provider: provider,
            id: onlineId,
            name: prefs.getString('active_online_model_name') ?? onlineId,
            contextLength: prefs.getInt('active_online_context_length') ?? 8192,
            isExplicitlyFree:
                prefs.getBool('active_online_explicitly_free') ?? false,
            supportsVision:
                prefs.getBool('active_online_supports_vision') ?? false,
            supportsToolCalling: false,
          )
        : null;
    final snapshot = LLMSelectionSnapshot(
      activeBackend: legacyBackend == 'online' && online != null
          ? 'online'
          : legacyBackend == 'offline' && local != null
          ? 'offline'
          : null,
      local: local,
      online: online,
    );
    await write(snapshot);
    return snapshot;
  }

  Future<void> write(LLMSelectionSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(snapshotKey, jsonEncode(snapshot.toJson()));
    await _writeCompatibilityKeys(prefs, snapshot);
  }

  Future<void> _writeCompatibilityKeys(
    SharedPreferences prefs,
    LLMSelectionSnapshot snapshot,
  ) async {
    final local = snapshot.local;
    if (local == null) {
      await prefs.remove(localIdKey);
      await prefs.remove(localPathKey);
      await prefs.remove('selected_model_path');
      await prefs.remove('selected_model_id');
    } else {
      await prefs.setString(localIdKey, local.id);
      await prefs.setString(localPathKey, local.path);
      await prefs.setString('selected_model_path', local.path);
      await prefs.setString('selected_model_id', local.id);
    }

    final online = snapshot.online;
    if (online == null) {
      for (final key in const [
        'active_online_provider',
        'active_online_model_id',
        'active_online_model_name',
        'active_online_context_length',
        'active_online_explicitly_free',
        'active_online_supports_vision',
        'active_online_supports_tools',
      ]) {
        await prefs.remove(key);
      }
    } else {
      await prefs.setString('active_online_provider', online.provider.id);
      await prefs.setString('active_online_model_id', online.id);
      await prefs.setString('active_online_model_name', online.name);
      await prefs.setInt('active_online_context_length', online.contextLength);
      await prefs.setBool(
        'active_online_explicitly_free',
        online.isExplicitlyFree,
      );
      await prefs.setBool(
        'active_online_supports_vision',
        online.supportsVision,
      );
      await prefs.setBool(
        'active_online_supports_tools',
        online.supportsToolCalling,
      );
    }

    final backend = snapshot.activeBackend;
    if (backend == null) {
      await prefs.remove('active_llm_backend');
      await prefs.remove('active_model_id');
    } else {
      await prefs.setString('active_llm_backend', backend);
      final activeId = backend == 'online'
          ? snapshot.online?.toModel().selectionId
          : snapshot.local?.id;
      if (activeId == null) {
        await prefs.remove('active_model_id');
      } else {
        await prefs.setString('active_model_id', activeId);
      }
    }
  }
}
