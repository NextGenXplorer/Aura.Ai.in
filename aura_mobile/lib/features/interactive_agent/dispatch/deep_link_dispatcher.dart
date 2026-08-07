/// Executes deep-link steps by delegating to the app's existing
/// [AppControlService] and [SmartAppActionsService]. Adds no new native intent
/// code and does not modify either service (Req 5.3, 5.4, 14.5).
///
/// Feature: interactive-agent-mode (Task 6.2)
library;

import '../../../core/services/app_control_service.dart';
import '../../../core/services/smart_app_actions_service.dart';
import '../models/agent_step.dart';
import '../models/run_result.dart';

class DeepLinkDispatcher {
  final AppControlService _appControl;
  final SmartAppActionsService _smartActions;

  DeepLinkDispatcher(this._appControl, this._smartActions);

  /// Dispatches [step]. A failure in the underlying service becomes a
  /// [StepDispatchFailed] outcome — never an uncaught throw — so the runner can
  /// apply the single UI-action fallback (Req 5.6, 8.1).
  Future<StepOutcome> dispatch(AgentStep step) async {
    final sw = Stopwatch()..start();
    try {
      await _invoke(step);
      sw.stop();
      return StepSucceeded(sw.elapsed);
    } catch (e) {
      sw.stop();
      return StepDispatchFailed(_reason(e));
    }
  }

  Future<void> _invoke(AgentStep step) {
    final args = step.deepLinkArgs;
    switch (step.deepLinkMethod) {
      case 'openApp':
        return _appControl.openApp(args['app'] ?? step.targetPackage ?? '');
      case 'openSettings':
        return _appControl.openSettings(args['type'] ?? 'general');
      case 'openCamera':
        return _appControl.openCamera();
      case 'sendWhatsApp':
        return _smartActions.sendWhatsApp(
          args['contact'] ?? '',
          args['message'] ?? '',
        );
      case 'searchOnApp':
        return _smartActions.searchOnApp(
          args['appName'] ?? '',
          args['query'] ?? '',
        );
      case 'makeUpiPayment':
        return _smartActions.makeUpiPayment(
          upiId: args['upiId'],
          amount: args['amount'],
          note: args['note'],
        );
      case 'playOnSpotify':
        return _smartActions.playOnSpotify(args['query'] ?? '');
      case 'bookRide':
        return _smartActions.bookRide(args['destination'] ?? '', app: args['app']);
      case 'orderFood':
        return _smartActions.orderFood(
          restaurant: args['restaurant'],
          app: args['app'],
        );
      case 'shareText':
        return _smartActions.shareText(args['text'] ?? '', app: args['app']);
      case 'openProfile':
        return _smartActions.openProfile(
          args['platform'] ?? '',
          args['username'] ?? '',
        );
      default:
        throw ArgumentError(
          'No deep-link capability for method "${step.deepLinkMethod}"',
        );
    }
  }

  String _reason(Object e) {
    // AppControlService rethrows a human string; SmartAppActionsService rethrows
    // the PlatformException. Normalise to a short reason.
    final text = e.toString();
    return text.length > 120 ? text.substring(0, 120) : text;
  }
}
