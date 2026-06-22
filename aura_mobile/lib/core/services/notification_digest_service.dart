import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/features/automation/application/automation_engine.dart';

final notificationDigestServiceProvider = Provider((ref) {
  return NotificationDigestService(ref);
});

// ── Models ───────────────────────────────────────────────────────────────────

class CapturedNotification {
  final String packageName;
  final String appName;
  final String title;
  final String text;
  final String category;
  final int postTime;

  CapturedNotification({
    required this.packageName,
    required this.appName,
    required this.title,
    required this.text,
    required this.category,
    required this.postTime,
  });

  factory CapturedNotification.fromMap(Map<dynamic, dynamic> map) {
    return CapturedNotification(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? '',
      title: map['title'] as String? ?? '',
      text: map['text'] as String? ?? '',
      category: map['category'] as String? ?? '',
      postTime: (map['postTime'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'packageName': packageName,
        'appName': appName,
        'title': title,
        'text': text,
        'category': category,
        'postTime': postTime,
      };

  DateTime get postDateTime =>
      DateTime.fromMillisecondsSinceEpoch(postTime);

  @override
  String toString() => '[$appName] $title: $text';
}

class NotificationGroup {
  final String appName;
  final String packageName;
  final List<CapturedNotification> notifications;
  final int count;

  NotificationGroup({
    required this.appName,
    required this.packageName,
    required this.notifications,
    required this.count,
  });

  factory NotificationGroup.fromMap(Map<dynamic, dynamic> map) {
    final rawNotifs = map['notifications'] as List<dynamic>? ?? [];
    final notifs = rawNotifs
        .map((n) => CapturedNotification.fromMap(n as Map<dynamic, dynamic>))
        .toList();

    return NotificationGroup(
      appName: map['appName'] as String? ?? '',
      packageName: map['packageName'] as String? ?? '',
      count: (map['count'] as num?)?.toInt() ?? notifs.length,
      notifications: notifs,
    );
  }

  @override
  String toString() => '$appName ($count notifications)';
}

// ── Service ──────────────────────────────────────────────────────────────────

class NotificationDigestService {
  static const _channel = MethodChannel('com.aura.ai/notifications');
  final Ref _ref;

  NotificationDigestService(this._ref) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationReceived') {
        try {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final appName = args['appName'] as String? ?? '';
          final text = args['text'] as String? ?? '';
          _ref.read(automationEngineProvider).checkAndTriggerNotificationFlows(appName, text);
        } catch (e) {
          debugPrint('NotificationDigest: Callback error: $e');
        }
      }
    });
  }

  /// Checks whether the NotificationListenerService is enabled in system settings.
  Future<bool> isListenerEnabled() async {
    try {
      final bool? enabled =
          await _channel.invokeMethod<bool>('isNotificationListenerEnabled');
      return enabled ?? false;
    } on PlatformException catch (e) {
      debugPrint('NotificationDigest: Failed to check listener status: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('NotificationDigest: Unexpected error checking status: $e');
      return false;
    }
  }

  /// Opens the system Notification Listener settings so the user can grant access.
  Future<void> openListenerSettings() async {
    try {
      await _channel.invokeMethod('openNotificationListenerSettings');
    } on PlatformException catch (e) {
      debugPrint(
          'NotificationDigest: Failed to open listener settings: ${e.message}');
    } catch (e) {
      debugPrint('NotificationDigest: Unexpected error opening settings: $e');
    }
  }

  /// Fetches raw notifications captured in the last [since] duration.
  /// Defaults to 1 hour.
  Future<List<CapturedNotification>> fetchRecentNotifications({
    Duration since = const Duration(hours: 1),
  }) async {
    try {
      final sinceMillis =
          DateTime.now().millisecondsSinceEpoch - since.inMilliseconds;

      final List<dynamic>? raw = await _channel.invokeMethod(
        'getRecentNotifications',
        {'sinceMillis': sinceMillis},
      );

      if (raw == null || raw.isEmpty) return [];

      return raw
          .map((item) =>
              CapturedNotification.fromMap(item as Map<dynamic, dynamic>))
          .toList();
    } on PlatformException catch (e) {
      debugPrint(
          'NotificationDigest: Failed to fetch recent notifications: ${e.message}');
      return [];
    } catch (e) {
      debugPrint(
          'NotificationDigest: Unexpected error fetching notifications: $e');
      return [];
    }
  }

  /// Fetches notifications grouped by app name.
  Future<List<NotificationGroup>> fetchGroupedNotifications() async {
    try {
      final List<dynamic>? raw = await _channel.invokeMethod(
        'getGroupedNotifications',
      );

      if (raw == null || raw.isEmpty) return [];

      return raw
          .map((item) =>
              NotificationGroup.fromMap(item as Map<dynamic, dynamic>))
          .toList();
    } on PlatformException catch (e) {
      debugPrint(
          'NotificationDigest: Failed to fetch grouped notifications: ${e.message}');
      return [];
    } catch (e) {
      debugPrint(
          'NotificationDigest: Unexpected error fetching grouped: $e');
      return [];
    }
  }

  /// Builds a smart digest: fetches grouped notifications, constructs a prompt,
  /// sends it to the on-device LLM, and streams back a human-readable summary.
  ///
  /// Returns an empty stream if there are no notifications or the model is not loaded.
  Stream<String> generateDigest({
    Duration since = const Duration(hours: 3),
  }) async* {
    // 1. Fetch recent grouped notifications
    final sinceMillis =
        DateTime.now().millisecondsSinceEpoch - since.inMilliseconds;

    List<CapturedNotification> recent;
    try {
      recent = await fetchRecentNotifications(since: since);
    } catch (e) {
      debugPrint('NotificationDigest: Could not fetch for digest: $e');
      yield 'Could not retrieve notifications.';
      return;
    }

    if (recent.isEmpty) {
      yield 'No new notifications to summarize.';
      return;
    }

    // 2. Group by app for the prompt
    final grouped = <String, List<CapturedNotification>>{};
    for (final n in recent) {
      grouped.putIfAbsent(n.appName, () => []).add(n);
    }

    // 3. Build the prompt
    final buffer = StringBuffer();
    buffer.writeln('Here are the user\'s recent notifications grouped by app:');
    buffer.writeln();

    for (final entry in grouped.entries) {
      buffer.writeln('## ${entry.key} (${entry.value.length} notifications)');
      for (final n in entry.value) {
        final time = n.postDateTime;
        final timeStr =
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
        if (n.title.isNotEmpty) {
          buffer.writeln('- [$timeStr] ${n.title}: ${n.text}');
        } else {
          buffer.writeln('- [$timeStr] ${n.text}');
        }
      }
      buffer.writeln();
    }

    final prompt = buffer.toString();

    const systemPrompt = '''You are AURA, a smart personal assistant. The user wants a quick digest of their recent notifications.

Rules:
- Summarize by app, highlighting what matters most (messages from people, actionable items, important updates).
- Skip spammy or promotional content — just mention "X promotional notifications" if any.
- Keep it concise: use bullet points, group related items.
- If there are messages from people, always include the sender name and a brief summary of the message.
- End with any suggested actions if appropriate (e.g., "You might want to reply to ...").
- Do NOT repeat raw notification text verbatim — paraphrase and condense.''';

    // 4. Stream from LLM
    final llm = _ref.read(llmServiceProvider);

    if (!llm.isModelLoaded) {
      yield 'AI model is not loaded. Cannot generate digest.';
      return;
    }

    yield* llm.chat(
      prompt,
      systemPrompt: systemPrompt,
      maxTokens: 512,
      temperature: 0.3,
    );
  }

  /// Clears all stored notifications on the native side.
  Future<void> clearNotifications() async {
    try {
      await _channel.invokeMethod('clearNotifications');
    } on PlatformException catch (e) {
      debugPrint(
          'NotificationDigest: Failed to clear notifications: ${e.message}');
    } catch (e) {
      debugPrint(
          'NotificationDigest: Unexpected error clearing: $e');
    }
  }
}
