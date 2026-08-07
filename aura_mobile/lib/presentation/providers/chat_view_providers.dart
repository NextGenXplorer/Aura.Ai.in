import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aura_mobile/presentation/providers/chat_provider.dart';

/// Presentation-layer derived state for the chat list.
///
/// The chat screen used to read the whole [chatProvider] state in `build`,
/// which meant every streamed token rebuilt the entire screen (app bar, input
/// bar and every visible bubble) and re-ran all message parsing — regexes, the
/// email-draft lookup and a full markdown re-parse — for messages that had not
/// changed at all.
///
/// Parsing now happens once per state change in these providers, and each
/// bubble listens to its own [ChatMessageView]. Riverpod compares the view with
/// `==`, so a bubble whose content did not change is not rebuilt. During
/// streaming that leaves exactly one bubble rebuilding per frame.

/// A single option chip parsed out of an `[[OPTIONS:...]]` marker.
@immutable
class ChatOption {
  const ChatOption({required this.label, required this.value});

  final String label;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is ChatOption && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);
}

/// Everything a message bubble needs to paint itself, fully pre-parsed.
@immutable
class ChatMessageView {
  const ChatMessageView({
    required this.role,
    required this.content,
    this.rawContent = '',
    this.draftAddress,
    this.emailSubject,
    this.emailBody,
    this.options = const [],
    this.isStreaming = false,
  });

  static const empty = ChatMessageView(role: 'assistant', content: '');

  final String role;

  /// Display text, with option and email-draft markers already removed.
  final String content;

  /// Untouched message text, needed by the automation-result card.
  final String rawContent;

  final String? draftAddress;
  final String? emailSubject;
  final String? emailBody;
  final List<ChatOption> options;

  /// True while this message is still being written by the model. Used to keep
  /// expensive text selection off the bubble until the answer settles.
  final bool isStreaming;

  bool get isUser => role == 'user';
  bool get isSystem => role == 'system';
  bool get isEmailDraft => draftAddress != null;

  @override
  bool operator ==(Object other) =>
      other is ChatMessageView &&
      other.role == role &&
      other.content == content &&
      other.rawContent == rawContent &&
      other.draftAddress == draftAddress &&
      other.emailSubject == emailSubject &&
      other.emailBody == emailBody &&
      other.isStreaming == isStreaming &&
      listEquals(other.options, options);

  @override
  int get hashCode => Object.hash(
    role,
    content,
    rawContent,
    draftAddress,
    emailSubject,
    emailBody,
    isStreaming,
    Object.hashAll(options),
  );
}

final _optionsRegex = RegExp(r'\[\[OPTIONS:(.*?)\]\]');
final _subjectRegex = RegExp(r'Subject:\s*(.+?)(?:\n|$)');
final _bodyPrefixRegex = RegExp(r'^Body:\s*', caseSensitive: false);

const _draftMarker = 'drafting_email_to:';

bool _isHiddenMessage(Map<String, String> m) =>
    m['role'] == 'system' && (m['content'] ?? '').startsWith(_draftMarker);

/// Builds the view list in a single forward pass and reuses the views of
/// messages whose backing map is unchanged.
class _ChatViewCache {
  List<Map<String, String>> _messages = const [];
  List<ChatMessageView> _views = const [];

  List<ChatMessageView> build(
    List<Map<String, String>> messages,
    bool isThinking,
  ) {
    // Streaming fast path: only the final assistant map is replaced on each
    // update, so every earlier view is still valid and can be handed back
    // untouched (identical instances also keep `==` cheap downstream).
    if (_views.isNotEmpty &&
        messages.length == _messages.length &&
        _isStreamingTailChange(messages)) {
      final reused = List<ChatMessageView>.of(_views);
      reused[reused.length - 1] = _buildView(
        messages,
        messages.length - 1,
        isThinking: isThinking,
      );
      _messages = messages;
      _views = reused;
      return reused;
    }

    final views = <ChatMessageView>[];
    for (var i = 0; i < messages.length; i++) {
      if (_isHiddenMessage(messages[i])) continue;
      views.add(_buildView(messages, i, isThinking: isThinking));
    }

    _messages = messages;
    _views = views;
    return views;
  }

  /// True when [messages] differs from the cached list only in its last entry.
  bool _isStreamingTailChange(List<Map<String, String>> messages) {
    if (messages.isEmpty) return false;
    // A hidden message anywhere shifts view indices away from message indices,
    // so the tail shortcut cannot be used.
    if (_views.length != messages.length) return false;
    if (messages.last['role'] != 'assistant') return false;
    for (var i = 0; i < messages.length - 1; i++) {
      if (!identical(messages[i], _messages[i])) return false;
    }
    return true;
  }

  ChatMessageView _buildView(
    List<Map<String, String>> messages,
    int index, {
    required bool isThinking,
  }) {
    final message = messages[index];
    final role = message['role'] ?? 'assistant';
    final raw = message['content'] ?? '';

    if (role != 'assistant') {
      return ChatMessageView(role: role, content: raw, rawContent: raw);
    }

    var content = raw;

    // Walk back to the nearest email-draft marker for this turn. Replaces the
    // old `allMessages.indexOf(message)` scan, which compared maps by value.
    String? draftAddress;
    for (var i = index - 1; i >= 0; i--) {
      final m = messages[i];
      if (m['role'] == 'system' &&
          (m['content'] ?? '').startsWith(_draftMarker)) {
        draftAddress = m['content']!.replaceFirst(_draftMarker, '');
        break;
      }
      if (m['role'] == 'user') break;
    }

    String? emailSubject;
    String? emailBody;
    var isEmailDraft = false;
    if (draftAddress != null && content.contains('Subject:')) {
      final subjectMatch = _subjectRegex.firstMatch(content);
      if (subjectMatch != null) emailSubject = subjectMatch.group(1)?.trim();

      final afterSubject = content.substring(subjectMatch?.end ?? 0).trim();
      emailBody = afterSubject.replaceFirst(_bodyPrefixRegex, '').trim();

      if (emailSubject != null || emailBody.isNotEmpty) {
        isEmailDraft = true;
        content = '';
      }
    }

    var options = const <ChatOption>[];
    final optionsMatch = _optionsRegex.firstMatch(content);
    if (optionsMatch != null) {
      content = content.substring(0, optionsMatch.start).trim();
      options = (optionsMatch.group(1) ?? '')
          .split(',')
          .map((entry) {
            final parts = entry.split('|');
            final label = parts[0].trim();
            return ChatOption(
              label: label,
              value: parts.length > 1 ? parts[1].trim() : label,
            );
          })
          .toList(growable: false);
    }

    return ChatMessageView(
      role: role,
      content: content,
      rawContent: raw,
      draftAddress: isEmailDraft ? draftAddress : null,
      emailSubject: isEmailDraft ? emailSubject : null,
      emailBody: isEmailDraft ? emailBody : null,
      options: options,
      isStreaming: isThinking && index == messages.length - 1,
    );
  }
}

final _chatViewCacheProvider = Provider<_ChatViewCache>(
  (ref) => _ChatViewCache(),
);

/// Pre-parsed views for every message the list renders, in display order.
final chatMessageViewsProvider = Provider<List<ChatMessageView>>((ref) {
  final messages = ref.watch(chatProvider.select((s) => s.messages));
  final isThinking = ref.watch(chatProvider.select((s) => s.isThinking));
  return ref.read(_chatViewCacheProvider).build(messages, isThinking);
});

/// Number of bubbles to render. An `int` compares by value, so the list itself
/// only rebuilds when a message is added or removed — not on every token.
final chatMessageCountProvider = Provider<int>(
  (ref) => ref.watch(chatMessageViewsProvider).length,
);

/// The view for one row. Riverpod skips the notification when the value is
/// unchanged, so only the bubble that actually changed rebuilds.
final chatMessageViewProvider = Provider.autoDispose
    .family<ChatMessageView, int>((ref, index) {
      final views = ref.watch(chatMessageViewsProvider);
      return index < views.length ? views[index] : ChatMessageView.empty;
    });
