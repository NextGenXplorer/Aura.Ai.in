/// Wraps the `com.aura.ai/agent_control` channel, turning raw string result
/// codes and node maps into typed [StepOutcome]s and [NodeMatch]es.
///
/// Feature: interactive-agent-mode (Task 6.1)
library;

import 'package:flutter/services.dart';

import '../models/agent_step.dart';
import '../models/run_result.dart';
import '../models/screen_signature.dart';

/// Native result codes returned by AgentActionSurface, mirrored here so the
/// mapping to outcomes lives in one place.
class AgentResult {
  static const ok = 'ok';
  static const disabled = 'actions_disabled';
  static const secure = 'secure_window';
  static const noService = 'no_service';
  static const noTarget = 'no_target';
  static const actionFailed = 'action_failed';
  static const staleToken = 'stale_token';
}

class UiActionDispatcher {
  final MethodChannel _channel;

  UiActionDispatcher({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.aura.ai/agent_control');

  /// Enable or disable the native action surface (session entry/exit).
  Future<bool> setActionsEnabled(bool enabled) async {
    final ok = await _channel.invokeMethod<bool>('setActionsEnabled', {
      'enabled': enabled,
    });
    return ok ?? false;
  }

  Future<bool> isServiceEnabled() async {
    final ok = await _channel.invokeMethod<bool>('isServiceEnabled');
    return ok ?? false;
  }

  /// Opens Android accessibility settings so the user can enable the service
  /// (Req 2.2). Reuses the same intent the existing screen-context feature uses.
  Future<void> openAccessibilitySettings() async {
    await _channel.invokeMethod('openAccessibilitySettings');
  }

  Future<ScreenSignature> screenSignature() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      'getScreenSignature',
    );
    if (map == null || map.isEmpty) return ScreenSignature.empty;
    return ScreenSignature.fromWire(map);
  }

  /// Targeted node lookup. Returns matches in reading order (Req 6.2).
  Future<List<NodeMatch>> findNodes(NodeQuery query, {int limit = 5}) async {
    final raw = await _channel.invokeListMethod<Object?>('findNodes', {
      'query': query.toWire(),
      'limit': limit,
    });
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((m) => NodeMatch.fromWire(m.cast<Object?, Object?>()))
        .toList();
  }

  /// Resolves a query to a single actionable node token per [NodeQuery.onMultiple],
  /// or an outcome explaining why it could not (Req 6.4, 6.5).
  Future<_Resolved> resolve(NodeQuery query) async {
    final matches = await findNodes(query, limit: 5);
    if (matches.isEmpty) return _Resolved.outcome(StepNoMatch(query));
    if (matches.length > 1 &&
        query.onMultiple == NodeDisambiguation.onlyIfUnique) {
      return _Resolved.outcome(StepAmbiguous(matches.length));
    }
    // firstInReadingOrder (or a unique match): take the first.
    return _Resolved.token(matches.first.handleToken);
  }

  Future<StepOutcome> tap(NodeQuery query) => _actOnResolved(query, (token) {
    return _channel.invokeMethod<String>('tapNode', {'handleToken': token});
  });

  Future<StepOutcome> setText(NodeQuery query, String value) =>
      _actOnResolved(query, (token) {
        return _channel.invokeMethod<String>('setNodeText', {
          'handleToken': token,
          'value': value,
        });
      });

  Future<StepOutcome> scroll(NodeQuery query, ScrollDirection direction) =>
      _actOnResolved(query, (token) {
        return _channel.invokeMethod<String>('scrollNode', {
          'handleToken': token,
          'forward': direction == ScrollDirection.forward,
        });
      });

  Future<StepOutcome> global(String action) async {
    return _mapCode(
      await _invokeCode('performGlobal', {'action': action}),
      elapsed: Duration.zero,
    );
  }

  Future<StepOutcome> _actOnResolved(
    NodeQuery query,
    Future<String?> Function(int token) act,
  ) async {
    final sw = Stopwatch()..start();
    final resolved = await resolve(query);
    if (resolved.outcome != null) return resolved.outcome!;
    final code = await _guard(() => act(resolved.token!));
    sw.stop();
    return _mapCode(code, elapsed: sw.elapsed);
  }

  Future<String?> _invokeCode(
    String method,
    Map<String, Object?> args,
  ) => _guard(() => _channel.invokeMethod<String>(method, args));

  /// Any PlatformException from the channel becomes a dispatch failure rather
  /// than an uncaught throw (crash-safety, Req 8.1).
  Future<String?> _guard(Future<String?> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      return 'platform:${e.code}';
    } on MissingPluginException {
      return AgentResult.noService;
    }
  }

  StepOutcome _mapCode(String? code, {required Duration elapsed}) {
    switch (code) {
      case AgentResult.ok:
        return StepSucceeded(elapsed);
      case AgentResult.secure:
        return const StepBlockedBySecureWindow();
      case AgentResult.disabled:
        return const StepDispatchFailed('actions disabled');
      case AgentResult.noService:
        return const StepDispatchFailed('accessibility service unavailable');
      case AgentResult.noTarget:
        return const StepDispatchFailed('no actionable target');
      case AgentResult.staleToken:
        return const StepDispatchFailed('stale node reference');
      case AgentResult.actionFailed:
        return const StepDispatchFailed('action rejected by target');
      default:
        return StepDispatchFailed(code ?? 'unknown');
    }
  }
}

/// Internal: either a resolved token or a terminal outcome.
class _Resolved {
  final int? token;
  final StepOutcome? outcome;
  const _Resolved.token(this.token) : outcome = null;
  const _Resolved.outcome(this.outcome) : token = null;
}
