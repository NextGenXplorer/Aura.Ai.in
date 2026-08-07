# Implementation Plan: Interactive Agent Mode

## Overview

Work starts at the pure-Dart core — data models, budget constants, the strategy resolver, and the rule-based planner
— because all of it is testable with no device and no accessibility service. The native action surface comes next,
added to `ScreenContextAccessibilityService` behind the `actionsEnabled` gate so the existing read-only path is
provably untouched. The Dart dispatchers and `ScreenObserver` wrap that channel, the `AgentRunner` state machine is
built against fakes, and only then are the controller, providers, and UI wired in. Non-regression checks and the
low-end benchmark checklist close the plan.

Every new Dart file lives under `lib/features/interactive_agent/`. Only three existing files are edited, all
additively: `ScreenContextAccessibilityService.kt`, `MainActivity.kt`, and one provider file. The orchestrator,
intent detection, and every existing feature path are left alone.

Property-based tests are marked optional with `*` and are placed beside the code they validate.

## Tasks

- [x] 1. Core data models and budgets
  - [x] 1.1 Create the step, plan, and outcome model
    - Create `lib/features/interactive_agent/models/agent_step.dart` with `ActionStrategy`, `StepKind`, `AgentStep`, `NodeQuery`, `NodeDisambiguation`, and the sealed `PostCondition` hierarchy (`SignatureChanged`, `PackageBecomes`, `NodeExists`, `NodeTextEquals`)
    - Create `lib/features/interactive_agent/models/agent_plan.dart` with `AgentPlan` and `PlannerSource`
    - Create `lib/features/interactive_agent/models/run_result.dart` with the sealed `StepOutcome` and `RunResult` hierarchies and `AbortReason`
    - Create `lib/features/interactive_agent/models/screen_signature.dart` with `ScreenSignature` and `NodeMatch`
    - _Requirements: 4.1, 4.7, 4.8, 6.1, 8.3_

  - [x] 1.2 Define the irreversible step set and budget constants
    - Create `lib/features/interactive_agent/agent_budgets.dart` with `AgentBudgets` holding `stepBudget` 12, `timeBudget` 90s, `settleTimeout` 5s, `settleQuietInterval` 350ms, `maxRecoveryRetries` 2, `rulePlanBudget` 300ms, `modelPlanTimeout` 6s, `deepLinkDispatchBudget` 400ms, `nodeQueryBudget` 150ms, `signatureWalkDepth` 6, `signatureWalkNodes` 40, `gateTimeout` 45s, `diagnosticsRingSize` 64
    - Define the irreversible step classification as a single named predicate covering message send, call, payment, order/purchase, delete, and security/permission change
    - _Requirements: 9.2, 9.7, 12.1, 12.2, 12.6, 12.7, 13.10_

  - [x] 1.3 Create `AutonomyPosture` and session state
    - Create `lib/features/interactive_agent/models/session_state.dart` with `AutonomyPosture`, `RunPhase`, `PendingGate`, `InteractiveSessionState`, and the `RunEvent` hierarchy
    - Default `AutonomyPosture.guided`
    - _Requirements: 1.1, 11.1_

- [x] 2. Strategy resolution
  - [x] 2.1 Implement `StrategyResolver`
    - Create `lib/features/interactive_agent/planning/strategy_resolver.dart` with `resolve(AgentPlan)` and `hasDeepLinkFor(StepKind, String?)`
    - Assign exactly one strategy per step, preferring `deepLink` whenever a deep-link capability matches the step; map the capability set to the methods `SmartAppActionsService` and `AppControlService` already expose
    - Mark irreversible steps using the predicate from 1.2, and enforce `stepBudget` by truncating with a recorded marker
    - _Requirements: 4.7, 4.8, 5.1, 5.2, 5.3, 12.1_

  - [x]* 2.2 Write property test for plan length bound
    - **Property 1: Plan length is bounded**
    - **Validates: Requirements 12.1**

  - [x]* 2.3 Write property test for single strategy with deep-link preference
    - **Property 2: Every step has exactly one strategy, deep-link preferred**
    - **Validates: Requirements 4.7, 5.1, 5.2**

  - [x]* 2.4 Write property test for irreversible marking
    - **Property 3: Irreversible steps are always marked**
    - **Validates: Requirements 4.8, 9.2**

- [x] 3. Rule-based planner
  - [x] 3.1 Implement `RuleBasedPlanner`
    - Create `lib/features/interactive_agent/planning/agent_planner.dart` with the `AgentPlanner` interface and `PlanningContext`
    - Create `lib/features/interactive_agent/planning/rule_based_planner.dart` using precompiled static `RegExp`s, returning `null` when the command is not covered
    - Cover at minimum: open app; open app then send a message to a named contact; open app then search inside it; play media; navigate to a destination
    - Reuse the extraction style of `IntentDetectionService` without modifying that service
    - _Requirements: 3.6, 3.7, 4.1, 4.5, 4.6, 13.3_

  - [x]* 3.2 Write unit tests for rule planner coverage and refusal
    - Verify each supported phrasing yields an ordered plan with the expected step kinds, and that unsupported commands yield `null`
    - _Requirements: 4.5, 4.6_

- [x] 4. Native action surface, capability-gated
  - [x] 4.1 Add the gated action surface to the accessibility service
    - Edit `android/app/src/main/kotlin/com/aura/mobile/aura_mobile/assistant/ScreenContextAccessibilityService.kt`
    - Add `@Volatile var actionsEnabled: Boolean = false` and a dedicated `HandlerThread` for node work, created on enable and quit on disable
    - Add `screenSignature()` performing a bounded shallow walk (depth ≤ 6, ≤ 40 nodes) returning package, activity, structure hash, node count, and a secure-window flag
    - Add `findNodes(query, limit)` using `findAccessibilityNodeInfosByViewId` / `findAccessibilityNodeInfosByText` only, returning plain maps with a per-round handle token — never full-tree traversal
    - Add `tapNode`, `setNodeText` (full value via `ACTION_SET_TEXT`), `scrollNode`, and `performGlobal(back|home)`
    - Every action returns a refusal when `actionsEnabled` is false or the active window is secure
    - Leave `currentScreenContent`, `currentPackageName`, `currentActivityName`, `getScreenContext()`, `isServiceEnabled()`, the 500 ms debounce, `MAX_TREE_DEPTH`, and `MAX_CONTENT_LENGTH` behavior unchanged
    - _Requirements: 6.1, 6.2, 6.3, 6.7, 6.8, 7.1, 7.3, 7.4, 7.7, 13.2, 13.8_

  - [x] 4.2 Register the agent control channel
    - Edit `android/app/src/main/kotlin/com/aura/mobile/aura_mobile/MainActivity.kt` to register `com.aura.ai/agent_control` alongside the existing channels
    - Expose `setActionsEnabled`, `isServiceEnabled`, `getScreenSignature`, `findNodes`, `tapNode`, `setNodeText`, `scrollNode`, `performGlobal`
    - Reconfigure `serviceInfo` on enable and restore the read-only configuration on disable
    - Do not modify any existing channel handler
    - _Requirements: 1.2, 1.3, 7.3, 7.4, 14.4_

  - [ ]* 4.3 Write property test for inert disabled actions
    - **Property 9: Disabled actions are inert**
    - **Validates: Requirements 1.4, 13.8**

  - [ ]* 4.4 Write property test for bounded signature walk
    - **Property 13: The signature walk is bounded**
    - **Validates: Requirements 13.6, 13.9**

  - [x]* 4.5 Write property test for structure-only signatures
    - **Property 10: Signatures track structure, not content**
    - **Validates: Requirements 7.1**

- [ ] 5. Checkpoint - core and native surface complete
  - Ensure all tests pass and the app still builds for Android; ask the user if questions arise.

- [x] 6. Dispatchers and screen observation
  - [x] 6.1 Implement `UiActionDispatcher`
    - Create `lib/features/interactive_agent/dispatch/ui_action_dispatcher.dart` wrapping `com.aura.ai/agent_control`
    - Map channel refusals onto `StepBlockedBySecureWindow` and `StepDispatchFailed`; map empty and multi-match results onto `StepNoMatch` and `StepAmbiguous` honouring `NodeDisambiguation`
    - _Requirements: 6.2, 6.4, 6.5, 6.7, 8.1_

  - [x] 6.2 Implement `DeepLinkDispatcher`
    - Create `lib/features/interactive_agent/dispatch/deep_link_dispatcher.dart` delegating to the existing `AppControlService` and `SmartAppActionsService`
    - Add no new native intent code and do not modify either service
    - Surface a dispatch failure as `StepDispatchFailed` so the runner can apply the single UI-Action fallback
    - _Requirements: 5.3, 5.4, 5.6, 14.5_

  - [x] 6.3 Implement `ScreenObserver`
    - Create `lib/features/interactive_agent/dispatch/screen_observer.dart` exposing a debounced signature stream, `current()`, `awaitSettle({timeout})`, and `verify(PostCondition)`
    - Coalesce signature computation on a 350 ms quiet window
    - _Requirements: 6.6, 7.2, 7.5, 7.6, 13.9_

- [x] 7. The run state machine
  - [x] 7.1 Implement `AgentRunner`
    - Create `lib/features/interactive_agent/agent_runner.dart` emitting `RunEvent`s and implementing the documented loop: plan, plan acknowledgement, per-step gate check, narration, dispatch, settle and verify, bounded recovery, budget guards
    - Charge gate wait time outside the time budget
    - Apply the guided-posture rule requiring confirmation before the first UI Action of a run
    - Allow exactly one UI-Action retry after a failed deep-link step, with narration
    - Transition to paused when the foreground package leaves the plan's declared package set, and on system interruption
    - Support abort at step boundaries and report exactly the completed step ids on every outcome
    - _Requirements: 4.3, 5.6, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 9.1, 9.6, 10.1, 10.3, 10.4, 10.5, 12.2, 12.3, 12.4, 12.5, 13.2_

  - [x] 7.2 Implement the redacted diagnostics ring
    - Create `lib/features/interactive_agent/agent_diagnostics.dart` with a fixed 64-entry ring recording step id, kind, strategy, outcome type, and elapsed ms only
    - Discard run observations at run end and session state at session end
    - _Requirements: 13.10, 15.3, 15.4, 15.5, 15.6, 15.7_

  - [x]* 7.3 Write property test for refused gates
    - **Property 4: A refused gate executes nothing further**
    - **Validates: Requirements 9.4, 9.5**

  - [x]* 7.4 Write property test for abort prefix execution
    - **Property 5: Abort executes exactly the prefix**
    - **Validates: Requirements 10.3, 10.4**

  - [x]* 7.5 Write property test for bounded recovery
    - **Property 6: Recovery is bounded**
    - **Validates: Requirements 8.2, 8.3, 12.7**

  - [x]* 7.6 Write property test for gate-excluded time budget
    - **Property 7: Gate waits do not consume the time budget**
    - **Validates: Requirements 12.5**

  - [x]* 7.7 Write property test for exact completion reporting
    - **Property 8: Reported completions are exact**
    - **Validates: Requirements 8.5, 10.4**

  - [x]* 7.8 Write property test for mandatory money and security gates
    - **Property 14: Money and security steps are always gated**
    - **Validates: Requirements 9.7, 11.3**

  - [x]* 7.9 Write property test for diagnostics redaction
    - **Property 12: Diagnostics never carry user content**
    - **Validates: Requirements 15.3, 15.4**

- [ ] 8. Checkpoint - runner verified against fakes
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Model-based planner
  - [x] 9.1 Implement `ModelPlanner`
    - Create `lib/features/interactive_agent/planning/model_planner.dart` used only when the active model reports `supportsToolCalling` and the rule planner returned `null`
    - Reuse `ToolDefinition` and `FunctionCallCoordinator` rather than duplicating parse/validate logic
    - Reject any emission containing a step kind outside `StepKind`, wholesale
    - Apply `modelPlanTimeout` and fall back to refusal on expiry
    - _Requirements: 4.4, 4.5, 4.6, 13.4, 14.3, 15.2_

  - [x]* 9.2 Write property test for wholesale rejection of unknown step kinds
    - **Property 11: Unknown step kinds are rejected wholesale**
    - **Validates: Requirements 4.7**

- [x] 10. Session controller and wiring
  - [x] 10.1 Implement `InteractiveModeController`
    - Create `lib/features/interactive_agent/interactive_mode_controller.dart` as a `StateNotifier<InteractiveSessionState>` with `enterSession`, `exitSession`, `setPosture`, `submitCommand`, `abort`, `resolveGate`, `continueAfterPause`
    - Default the mode off, start every process with it off, and reject a second concurrent run
    - End the session and inform the user if the accessibility service is lost mid-session
    - _Requirements: 1.1, 1.2, 1.3, 1.5, 1.6, 1.7, 3.1, 3.5, 11.1_

  - [x] 10.2 Add providers without disturbing existing wiring
    - Add the Interactive Agent providers in a new provider file and reference it from the existing provider composition without altering existing provider definitions
    - Ensure no background entry point — automation rules, proactive nudges, notification listener, foreground service — can call `submitCommand`
    - _Requirements: 11.2, 11.6, 14.1, 14.2, 14.5_

- [x] 11. Presentation
  - [x] 11.1 Build the mode toggle and disclosure sheet
    - Add the Interactive Mode toggle and a disclosure sheet describing what is read, what is done, and how to revoke, shown before the accessibility hand-off
    - Reuse the existing `openAccessibilitySettings` method; do not prompt twice in one app session after a decline
    - Expose the autonomy posture, disclose that Continuous is not permitted under Play policy and is sideload-only, and keep it off by default
    - Make the disclosure text re-readable from the same place
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 11.4, 11.5_

  - [x] 11.2 Build the session overlay
    - Render the mode-active indicator, the plan summary before the first step, the current step with its position, and an always-reachable abort control
    - Watch only the narration and step-index slices so a step change repaints one widget rather than the chat tree; keep decorated containers inside repaint boundaries
    - Route spoken narration through the existing TTS service without changing it for other features
    - _Requirements: 1.2, 4.3, 10.1, 10.2, 10.6, 10.7, 13.1_

  - [x] 11.3 Build the confirmation gate sheet
    - Show the concrete effect including recipient and content where applicable, never a generic prompt
    - Treat decline and timeout as abort, never as approval
    - _Requirements: 9.1, 9.3, 9.4, 9.5_

  - [x] 11.4 Wire command capture
    - Accept commands from both voice and text while a session is active, echo the interpreted command before executing, and report when nothing actionable was found
    - Use the existing speech-to-text service without altering its configuration for other callers
    - Report a named missing app rather than starting execution
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.7_

- [x] 12. Non-regression verification
  - [x] 12.1 Verify the existing feature set is untouched
    - Confirm the existing screen-context channel methods still answer with their current contracts
    - Confirm intent detection, the orchestrator rule-based and function-calling branches, voice assistant, screen reader, smart summarizer, study tools, automation rules, document generation, and model selection behave as before with the mode off
    - Confirm no new runtime permission is required for users who never enable the mode, and the app still works with the accessibility service never enabled
    - Run the full existing test suite and confirm no test was weakened or removed
    - _Requirements: 1.4, 7.4, 14.1, 14.2, 14.3, 14.4, 14.5, 14.6, 14.7, 14.8_

- [~] 13. Low-end device benchmark checklist
  - [~] 13.1 Measure and record the performance budgets on a physical device
    - Checklist authored at `.kiro/specs/interactive-agent-mode/benchmark-checklist.md`
    - Rule-planning latency (B2, Req 13.3) automated in `agent_planning_benchmark_test.dart`
    - Remaining budgets (frame, node query, deep-link dispatch, memory) require a
      profile run on the physical device and are pending user execution
    - On a Reference Low-End Device, measure rule planning, deep-link dispatch, targeted node query, session memory delta, and frame behavior during narration
    - Record results against the budgets and file any breach as a defect rather than adjusting the budget
    - _Requirements: 13.1, 13.3, 13.5, 13.6, 13.7_

- [x] 14. Final checkpoint - feature integrated
  - Full suite green (278/0), `flutter analyze` reports zero errors, debug APK builds.

## Notes

- Tasks marked with `*` are optional property tests and can be skipped for a faster first cut, at the cost of the
  guarantees they encode.
- The only existing files edited are `ScreenContextAccessibilityService.kt`, `MainActivity.kt`, and one provider
  composition file. All edits are additive.
- The runner is fully testable against fake dispatchers and a fake observer, so tasks 1–3, 6–7 and 9–10 need no
  device.
- Requirements verified by example, integration, or manual benchmark rather than by a property: 1.1, 1.5, 2.x, 3.x,
  5.3, 13.1, 13.3, 13.5, 13.6, 13.7, 14.x, 15.7.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.3", "4.1"] },
    { "id": 1, "tasks": ["2.1", "3.1", "4.2", "4.3", "4.4", "4.5"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.4", "3.2", "6.1", "6.2", "6.3"] },
    { "id": 3, "tasks": ["7.1", "7.2"] },
    { "id": 4, "tasks": ["7.3", "7.4", "7.5", "7.6", "7.7", "7.8", "7.9", "9.1"] },
    { "id": 5, "tasks": ["9.2", "10.1"] },
    { "id": 6, "tasks": ["10.2", "11.1", "11.2", "11.3", "11.4"] },
    { "id": 7, "tasks": ["12.1"] },
    { "id": 8, "tasks": ["13.1"] }
  ]
}
```
