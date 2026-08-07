/// Observes the screen through cheap signatures: exposes a polled signature
/// stream, waits for the screen to settle, and verifies post-conditions with
/// targeted queries (Req 6.6, 7.2, 7.5, 7.6, 13.9).
///
/// Feature: interactive-agent-mode (Task 6.3)
library;

import 'dart:async';

import '../agent_budgets.dart';
import '../models/agent_step.dart';
import '../models/screen_signature.dart';
import 'ui_action_dispatcher.dart';

class ScreenObserver {
  final UiActionDispatcher _ui;
  final AgentBudgets _budgets;

  ScreenObserver(this._ui, {AgentBudgets budgets = AgentBudgets.defaults})
    : _budgets = budgets;

  Future<ScreenSignature> current() => _ui.screenSignature();

  /// Completes true once the signature is stable for [AgentBudgets.settleQuietInterval],
  /// or false if it never stabilises within [timeout] (Req 7.5, 7.6). Polls at
  /// the quiet-interval cadence rather than subscribing to native events, so a
  /// rapidly animating app cannot drive query storms (Req 13.9).
  Future<bool> awaitSettle({Duration? timeout}) async {
    final limit = timeout ?? _budgets.settleTimeout;
    final deadline = DateTime.now().add(limit);
    final quiet = _budgets.settleQuietInterval;

    ScreenSignature previous = await current();
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(quiet);
      final now = await current();
      if (now == previous) {
        return true; // unchanged across a quiet interval -> settled
      }
      previous = now;
    }
    return false;
  }

  /// Verifies a step's post-condition against the current screen (Req 6.6).
  /// A signature-based condition is compared against [before]; node conditions
  /// issue a targeted query.
  Future<bool> verify(PostCondition condition, {ScreenSignature? before}) async {
    switch (condition) {
      case SignatureChanged():
        final now = await current();
        return before == null || now != before;
      case PackageBecomes(:final packageName):
        final now = await current();
        return now.packageName == packageName ||
            now.packageName.contains(packageName);
      case NodeExists(:final query):
        final matches = await _ui.findNodes(query, limit: 1);
        return matches.isNotEmpty;
      case NodeTextEquals(:final query, :final value):
        final matches = await _ui.findNodes(query, limit: 1);
        return matches.isNotEmpty && matches.first.text == value;
    }
  }
}
