// Tests for the dispatch layer: UiActionDispatcher result-code mapping and
// DeepLinkDispatcher delegation + failure containment.
//
// Feature: interactive-agent-mode (Task 6)

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/core/services/app_control_service.dart';
import 'package:aura_mobile/core/services/smart_app_actions_service.dart';
import 'package:aura_mobile/features/interactive_agent/dispatch/deep_link_dispatcher.dart';
import 'package:aura_mobile/features/interactive_agent/dispatch/ui_action_dispatcher.dart';
import 'package:aura_mobile/features/interactive_agent/models/agent_step.dart';
import 'package:aura_mobile/features/interactive_agent/models/run_result.dart';

const _channelName = 'com.aura.ai/agent_control';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(_channelName);

  void mock(Future<Object?>? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('UiActionDispatcher outcome mapping', () {
    test('a matching node + ok yields StepSucceeded', () async {
      mock((call) async {
        if (call.method == 'findNodes') {
          return [
            {'handleToken': 1, 'editable': false, 'clickable': true},
          ];
        }
        if (call.method == 'tapNode') return AgentResult.ok;
        return null;
      });
      final d = UiActionDispatcher(channel: channel);
      final outcome = await d.tap(const NodeQuery(text: 'Send'));
      expect(outcome, isA<StepSucceeded>());
    });

    test('no matches yields StepNoMatch without acting', () async {
      var tapped = false;
      mock((call) async {
        if (call.method == 'findNodes') return <Object?>[];
        if (call.method == 'tapNode') tapped = true;
        return null;
      });
      final d = UiActionDispatcher(channel: channel);
      final outcome = await d.tap(const NodeQuery(text: 'Missing'));
      expect(outcome, isA<StepNoMatch>());
      expect(tapped, isFalse, reason: 'must not tap when nothing matched');
    });

    test('multiple matches with onlyIfUnique yields StepAmbiguous', () async {
      mock((call) async {
        if (call.method == 'findNodes') {
          return [
            {'handleToken': 1},
            {'handleToken': 2},
          ];
        }
        return null;
      });
      final d = UiActionDispatcher(channel: channel);
      final outcome = await d.tap(
        const NodeQuery(text: 'Send', onMultiple: NodeDisambiguation.onlyIfUnique),
      );
      expect(outcome, isA<StepAmbiguous>());
    });

    test('a secure-window code yields StepBlockedBySecureWindow', () async {
      mock((call) async {
        if (call.method == 'findNodes') {
          return [
            {'handleToken': 1},
          ];
        }
        if (call.method == 'setNodeText') return AgentResult.secure;
        return null;
      });
      final d = UiActionDispatcher(channel: channel);
      final outcome = await d.setText(const NodeQuery(viewId: 'field'), 'hi');
      expect(outcome, isA<StepBlockedBySecureWindow>());
    });

    test('a PlatformException becomes StepDispatchFailed, not a throw', () async {
      mock((call) async {
        if (call.method == 'findNodes') {
          return [
            {'handleToken': 1},
          ];
        }
        throw PlatformException(code: 'BOOM');
      });
      final d = UiActionDispatcher(channel: channel);
      final outcome = await d.tap(const NodeQuery(text: 'x'));
      expect(outcome, isA<StepDispatchFailed>());
    });

    test('global back maps ok to success', () async {
      mock((call) async => call.method == 'performGlobal' ? AgentResult.ok : null);
      final d = UiActionDispatcher(channel: channel);
      expect(await d.global('back'), isA<StepSucceeded>());
    });
  });

  group('DeepLinkDispatcher delegation and containment', () {
    test('openApp step delegates to AppControlService', () async {
      final appControl = _RecordingAppControl();
      final dispatcher = DeepLinkDispatcher(appControl, _NoopSmartActions());
      final outcome = await dispatcher.dispatch(
        const AgentStep(
          id: 's1',
          kind: StepKind.openApp,
          strategy: ActionStrategy.deepLink,
          narration: 'Open WhatsApp',
          deepLinkMethod: 'openApp',
          deepLinkArgs: {'app': 'whatsapp'},
        ),
      );
      expect(outcome, isA<StepSucceeded>());
      expect(appControl.opened, 'whatsapp');
    });

    test('a throwing service becomes StepDispatchFailed', () async {
      final dispatcher = DeepLinkDispatcher(
        _ThrowingAppControl(),
        _NoopSmartActions(),
      );
      final outcome = await dispatcher.dispatch(
        const AgentStep(
          id: 's1',
          kind: StepKind.openApp,
          strategy: ActionStrategy.deepLink,
          narration: 'Open Nope',
          deepLinkMethod: 'openApp',
          deepLinkArgs: {'app': 'nope'},
        ),
      );
      expect(outcome, isA<StepDispatchFailed>());
    });

    test('an unknown deep-link method fails gracefully', () async {
      final dispatcher = DeepLinkDispatcher(
        _RecordingAppControl(),
        _NoopSmartActions(),
      );
      final outcome = await dispatcher.dispatch(
        const AgentStep(
          id: 's1',
          kind: StepKind.deepLinkAction,
          strategy: ActionStrategy.deepLink,
          narration: 'do',
          deepLinkMethod: 'no_such_method',
        ),
      );
      expect(outcome, isA<StepDispatchFailed>());
    });
  });
}

class _RecordingAppControl extends AppControlService {
  String? opened;
  @override
  Future<void> openApp(String appName) async {
    opened = appName;
  }
}

class _ThrowingAppControl extends AppControlService {
  @override
  Future<void> openApp(String appName) async {
    throw 'Could not open $appName';
  }
}

class _NoopSmartActions extends SmartAppActionsService {}
