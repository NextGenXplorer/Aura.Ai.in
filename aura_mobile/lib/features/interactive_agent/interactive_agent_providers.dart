/// Riverpod wiring for Interactive Agent Mode. Kept in its own file so it can
/// reference existing providers without any existing provider file referencing
/// interactive-agent code (Req 14 — additive only).
///
/// No background entry point constructs a runner: only the controller's
/// [InteractiveModeController.submitCommand] does, and that is user-initiated
/// (Req 11.2, 11.6).
///
/// Feature: interactive-agent-mode (Task 10.2)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/ai_providers.dart';
import '../../core/services/app_control_service.dart';
import '../../core/services/smart_app_actions_service.dart';
import '../../core/services/voice_service.dart' show VoiceService;
import 'agent_budgets.dart';
import 'agent_runner.dart';
import 'dispatch/deep_link_dispatcher.dart';
import 'dispatch/screen_observer.dart';
import 'dispatch/step_dispatch.dart';
import 'dispatch/ui_action_dispatcher.dart';
import 'interactive_mode_controller.dart';
import 'models/session_state.dart';
import 'planning/model_planner.dart';
import 'planning/rule_based_planner.dart';
import 'planning/strategy_resolver.dart';

const _budgets = AgentBudgets.defaults;

// A dedicated TTS instance for agent narration. Kept separate from the chat
// voice loop (which is bypassed while Interactive Mode is active), so there is
// no cross-talk and no import cycle with chat_provider.
final _agentNarratorProvider = Provider<VoiceService>((ref) {
  final voice = VoiceService();
  // Fire-and-forget init so narration uses the configured voice/rate.
  voice.initialize();
  return voice;
});

final _uiActionDispatcherProvider = Provider<UiActionDispatcher>(
  (ref) => UiActionDispatcher(),
);

final _stepDispatchProvider = Provider<StepDispatch>((ref) {
  final ui = ref.watch(_uiActionDispatcherProvider);
  final deepLink = DeepLinkDispatcher(
    ref.watch(appControlServiceProvider),
    ref.watch(smartAppActionsProvider),
  );
  final observer = ScreenObserver(ui, budgets: _budgets);
  return RealStepDispatch(deepLink, ui, observer);
});

const _rulePlanner = RuleBasedPlanner();

/// The session controller. This is the single, user-facing entry point.
final interactiveModeControllerProvider =
    StateNotifierProvider<InteractiveModeController, InteractiveSessionState>((
      ref,
    ) {
      final dispatch = ref.watch(_stepDispatchProvider);
      const resolver = StrategyResolver(budgets: _budgets);

      // Model planning is enabled only when the active model reports tool
      // calling; otherwise the rule planner is the sole planner (Req 4.4, 4.5).
      return InteractiveModeController(
        dispatch: dispatch,
        // Spoken narration (Req 10.6), fire-and-forget through TTS.
        narrator: (text) {
          // Not awaited: narration must never block the run loop.
          ref.read(_agentNarratorProvider).speak(text);
        },
        runnerFactory: (gate) {
          final llm = ref.read(llmServiceProvider);
          final modelPlanner = llm.supportsToolCalling
              ? ModelPlanner((prompt) async {
                  final buffer = StringBuffer();
                  await for (final token in llm.chat(
                    prompt,
                    temperature: 0.2,
                    maxTokens: 512,
                  )) {
                    buffer.write(token);
                  }
                  return buffer.toString();
                })
              : null;

          return AgentRunner(
            buildRulePlan: (command) => _rulePlanner.plan(command),
            buildModelPlan: modelPlanner == null
                ? null
                : (command) => modelPlanner.plan(command),
            dispatch: dispatch,
            gate: gate,
            resolver: resolver,
            budgets: _budgets,
          );
        },
      );
    });
