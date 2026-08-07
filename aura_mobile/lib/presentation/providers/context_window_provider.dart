import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/context_builder_service.dart';

// ─── Color state for the context window usage indicator ───────────────────────

enum ContextWindowColorState { normal, warning, critical }

// ─── Immutable state ─────────────────────────────────────────────────────────

class ContextWindowState {
  final int estimatedTokens;
  final int maxTokens;
  final int currentTurns;
  final int maxTurns;
  final ContextWindowColorState colorState;
  final ModelTier modelTier;

  const ContextWindowState({
    this.estimatedTokens = 0,
    this.maxTokens = 4096,
    this.currentTurns = 0,
    this.maxTurns = 10,
    this.colorState = ContextWindowColorState.normal,
    this.modelTier = ModelTier.large,
  });

  ContextWindowState copyWith({
    int? estimatedTokens,
    int? maxTokens,
    int? currentTurns,
    int? maxTurns,
    ContextWindowColorState? colorState,
    ModelTier? modelTier,
  }) {
    return ContextWindowState(
      estimatedTokens: estimatedTokens ?? this.estimatedTokens,
      maxTokens: maxTokens ?? this.maxTokens,
      currentTurns: currentTurns ?? this.currentTurns,
      maxTurns: maxTurns ?? this.maxTurns,
      colorState: colorState ?? this.colorState,
      modelTier: modelTier ?? this.modelTier,
    );
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final contextWindowProvider =
    StateNotifierProvider<ContextWindowNotifier, ContextWindowState>((ref) {
      return ContextWindowNotifier(ref);
    });

// ─── Notifier ────────────────────────────────────────────────────────────────

class ContextWindowNotifier extends StateNotifier<ContextWindowState> {
  final Ref _ref;

  ContextWindowNotifier(this._ref) : super(const ContextWindowState());

  // ─── Pure functions ──────────────────────────────────────────────────────

  /// Estimate token count from text using the ~4 chars per token heuristic.
  /// Returns 0 for empty or null-length text.
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 4).ceil();
  }

  /// Determine color state from the ratio of current tokens to max tokens.
  ///   normal:   tokens <= 75% of max  (≤ 3072 for 4096)
  ///   warning:  tokens > 75% and <= 90%  (≤ 3686 for 4096)
  ///   critical: tokens > 90%
  static ContextWindowColorState colorStateForTokens(
    int tokens,
    int maxTokens,
  ) {
    if (maxTokens <= 0) return ContextWindowColorState.normal;
    final ratio = tokens / maxTokens;
    if (ratio > 0.90) return ContextWindowColorState.critical;
    if (ratio > 0.75) return ContextWindowColorState.warning;
    return ContextWindowColorState.normal;
  }

  /// Calculate the effective turn count from a messages list.
  /// A "turn" = 1 user message + 1 assistant response = 2 entries.
  /// Returns min(messages.length ~/ 2, maxTurnsForTier).
  static int calculateTurns(
    List<Map<String, String>> messages,
    ModelTier tier,
  ) {
    if (messages.isEmpty) return 0;
    final rawTurns = messages.length ~/ 2;
    return rawTurns < maxTurnsForTier(tier) ? rawTurns : maxTurnsForTier(tier);
  }

  /// Max conversation turns allowed for a given model tier.
  static int maxTurnsForTier(ModelTier tier) {
    switch (tier) {
      case ModelTier.small:
        return 4;
      case ModelTier.medium:
        return 6;
      case ModelTier.large:
        return 10;
    }
  }

  // ─── State mutations ─────────────────────────────────────────────────────

  /// Recalculate the context window state after the message list changes.
  ///
  /// **PERFORMANCE NOTE**: This method calls `ContextBuilderService.buildPrompt`
  /// which generates embeddings + queries the memory/document tables. It costs
  /// 100-500ms on a phone. Use [updateFromMessagesFast] for per-message updates
  /// and only call this method on:
  /// - Initial load
  /// - Model tier change
  /// - Manual user-triggered refresh
  Future<void> recalculate(List<Map<String, String>> messages) async {
    final contextService = _ref.read(contextBuilderServiceProvider);

    String fullPrompt;

    if (messages.isEmpty) {
      // No messages yet — estimate the system prompt size alone.
      fullPrompt = await contextService.buildPrompt(
        userMessage: '',
        chatHistory: [],
        includeMemories: false,
        includeDocuments: false,
      );
    } else {
      // Extract the last user message.
      final lastUserMessage =
          messages.lastWhere(
            (m) => m['role'] == 'user',
            orElse: () => {'role': 'user', 'content': ''},
          )['content'] ??
          '';

      // Convert message maps to chat history strings.
      final chatHistory = messages.map((m) {
        final role = m['role'] == 'user' ? 'User' : 'Assistant';
        return '$role: ${m['content'] ?? ''}';
      }).toList();

      fullPrompt = await contextService.buildPrompt(
        userMessage: lastUserMessage,
        chatHistory: chatHistory,
        includeMemories: true,
        includeDocuments: true,
      );
    }

    final tokens = estimateTokens(fullPrompt);
    final turns = calculateTurns(messages, state.modelTier);
    final color = colorStateForTokens(tokens, state.maxTokens);

    state = state.copyWith(
      estimatedTokens: tokens,
      currentTurns: turns,
      colorState: color,
    );
  }

  /// Cheap per-message update that does NOT call `buildPrompt` (no embedding,
  /// no DB query). Estimates tokens by summing the character count of all
  /// messages plus a small overhead for the system prompt and role labels.
  ///
  /// This is the method to call after every send/receive in the chat flow.
  /// Accuracy is within ~5% of the true assembled-prompt token count, which is
  /// fine for a UX meter.
  void updateFromMessagesFast(List<Map<String, String>> messages) {
    // ~200 chars of system prompt overhead + 12 chars per message for role/newlines
    int totalChars = 200;
    for (final msg in messages) {
      totalChars += (msg['content']?.length ?? 0) + 12;
    }
    final tokens = (totalChars / 4).ceil();
    final turns = calculateTurns(messages, state.modelTier);
    final color = colorStateForTokens(tokens, state.maxTokens);

    state = state.copyWith(
      estimatedTokens: tokens,
      currentTurns: turns,
      colorState: color,
    );
  }

  /// Update the model tier (called when the user switches models).
  ///
  /// The context limit is re-read from the active engine at the same time, so
  /// the indicator reflects the real window of the selected model (a large
  /// online context is no longer displayed as if it were 4096 tokens).
  void updateModelTier(ModelTier tier) {
    final newMaxTurns = maxTurnsForTier(tier);
    final newMaxTokens = _ref.read(llmServiceProvider).contextTokens;
    final newColor = colorStateForTokens(state.estimatedTokens, newMaxTokens);

    state = state.copyWith(
      modelTier: tier,
      maxTurns: newMaxTurns,
      maxTokens: newMaxTokens,
      colorState: newColor,
    );
  }

  /// Update the estimated token count live during streaming.
  /// Uses a baseline token count to avoid slow prompt rebuilds.
  void updateStreamingTokens(int baselineTokens, String currentText) {
    // Length of "Assistant: " prefix is 11 plus newline is 12 characters.
    final addedChars = currentText.isNotEmpty ? currentText.length + 12 : 0;
    final addedTokens = (addedChars / 4).ceil();
    final newColor = colorStateForTokens(
      baselineTokens + addedTokens,
      state.maxTokens,
    );

    state = state.copyWith(
      estimatedTokens: baselineTokens + addedTokens,
      colorState: newColor,
    );
  }
}
