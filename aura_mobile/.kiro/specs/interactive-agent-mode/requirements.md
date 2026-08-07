# Requirements Document

## Introduction

AURA Mobile today detects intents from a single user message and satisfies them with one
action: a rule-based intent match, a native function call, or a deep link into another app
(WhatsApp, Spotify, UPI, ride, food, share). It can also *read* the foreground screen through
a read-only `AccessibilityService` that publishes the current package name, activity name, and
visible text.

This feature adds **Interactive Mode**: an explicitly activated, user-initiated mode in which
AURA carries out a multi-step operation inside *another app on the device* — for example
"open WhatsApp and send a message to Rahul" or "open Settings and turn on Wi-Fi". Interactive
Mode drives the target app one step at a time, observes the resulting screen, and asks the user
to confirm before any step that cannot be undone.

Three forces shape every requirement in this document.

**Purely additive.** Interactive Mode is a new, parallel branch. The existing rule-based intent
path, the existing native function-calling path, the existing deep-link actions, the existing
read-only screen capture and its `MainActivity` channels, the existing regex intent detection,
and the existing voice stack all keep their current behavior and signatures. Nothing in this
feature removes, rewrites, or gates an existing capability.

**Smooth on low-end devices.** The step loop must never block the Flutter UI isolate or the
Android main thread, and must never traverse the whole accessibility node tree per step. This
document expresses that as measurable frame, latency, step-count, and memory budgets, plus an
action-strategy hierarchy that prefers a deep link (near-instant, no screen scraping) and falls
back to accessibility UI driving only when no deep link can satisfy the operation.

**Google Play accessibility policy.** Google Play's
[Accessibility API policy](https://support.google.com/googleplay/android-developer/answer/10964491?hl=en)
requires that actions taken on a user's behalf serve a narrow and clearly understood purpose, and
strictly prohibits use of the API that lets an application autonomously initiate, plan, and
execute actions or decisions. Applications targeting Android 12 and above also require an
approved Play permissions declaration for the accessibility use. Therefore the default posture
of Interactive Mode is **confirm-before-act, user-initiated, one step at a time**. Any
fully-autonomous execution is an explicit opt-in that is available only in sideload builds and
is absent from Play builds.

### Recorded Defaults (chosen here, correctable during review)

These values were selected so the document stays testable. Each is stated as an acceptance
criterion so it can be changed in review.

- Low_End_Device threshold: Device_RAM at or below 3,072 MB, or 4 or fewer CPU cores (R14.1)
- Session step budget: 12 Steps (R13.1)
- Session wall-clock budget: 90 seconds (R13.3)
- Per-Step screen-match timeout: 5 seconds (R11.1)
- Recovery attempts per Step: 2 (R11.3)
- Deep_Link_Action latency ceiling: 800 ms (R14.4)
- UI_Action latency ceiling: 1,500 ms (R14.5)
- Screen_Query latency ceiling: 300 ms (R14.6), node cap 200, depth cap 12 (R9.3, R9.4)
- Frame budget: 90th-percentile combined build-plus-raster time at or below 16 ms (R14.2)
- Added resident memory ceiling during a Session: 40 MB over pre-Session baseline (R14.7)
- Confirmation_Gate timeout: 30 seconds, resolving to Abort (R10.6)
- Autonomous_Execution_Option: absent from Play builds, opt-in and off by default in
  sideload builds (R15.4, R15.5)

## Glossary

- **AURA**: The AURA Mobile Flutter application described by this document, comprising its Dart layers and its Android native layer.
- **Interactive_Mode**: A named operating mode of AURA, activated only by an explicit user act, in which AURA performs a multi-Step operation inside a Target_App by issuing Deep_Link_Actions and UI_Actions and observing the resulting Screen_State. Interactive_Mode is distinct from, and additional to, the existing rule-based intent path and the existing native function-calling path.
- **Legacy_Path**: The set of AURA behaviors that exist before Interactive_Mode is installed, comprising the rule-based intent path in `OrchestratorService`, the native function-calling path in `OrchestratorService` with its tool registry, the regex detection in `IntentDetectionService`, the deep-link actions in `SmartAppActionsService`, the read-only screen capture in `ScreenContextAccessibilityService`, the `MainActivity` channel methods `getScreenContext`, `isAccessibilityEnabled`, and `openAccessibilitySettings`, and the voice stack comprising `VoiceService`, `TtsManager`, `AssistantForegroundService`, and the voice overlay.
- **Session**: One bounded execution of Interactive_Mode, beginning when AURA accepts a Command and ending in exactly one Terminal_Outcome. A Session owns exactly one Plan, one Target_App reference, one Step_Budget, and one Time_Budget.
- **Terminal_Outcome**: One of exactly four Session end states: `completed`, `aborted`, `failed`, or `expired`.
- **Command**: One natural-language instruction from the user, captured as text, that describes the operation to perform inside a Target_App.
- **Target_App**: The installed application, identified by its Android package name, inside which the Session performs its Steps.
- **Plan**: An ordered, finite list of Steps produced from a Command before execution of the first Step begins.
- **Step**: One unit of a Plan, comprising an Action_Intent, an optional Target_Descriptor, an Expected_Screen_Condition, and an Irreversibility_Flag.
- **Action_Intent**: The abstract operation a Step performs, being exactly one of `launch_app`, `open_target`, `tap`, `set_text`, `scroll`, `navigate_back`, `navigate_home`, or `wait_for_screen`.
- **Target_Descriptor**: The identifying attributes used to locate one on-screen element, comprising any of a view identifier, a text value, a content description, and an element class name.
- **Expected_Screen_Condition**: A checkable predicate over a Screen_State that states what must be true for a Step to be considered successful.
- **Irreversibility_Flag**: A boolean field on a Step that is true when the Step performs an Irreversible_Operation.
- **Irreversible_Operation**: An operation whose effect cannot be undone from inside AURA, comprising sending a message, placing a call, initiating a payment, confirming a purchase or order, and deleting user data.
- **Action_Strategy**: The mechanism selected to carry out one Step, being exactly one of `deep_link` or `ui_action`.
- **Deep_Link_Action**: A Step carried out by issuing an Android intent or URI to the Target_App through the existing `com.aura.ai/app_control` channel, without reading or driving the Target_App's view hierarchy.
- **UI_Action**: A Step carried out by the Interaction_Service performing an accessibility gesture or node action on the Target_App's view hierarchy, being exactly one of click, set text, scroll, global back, or global home.
- **Screen_State**: A bounded snapshot of the foreground window, comprising the foreground package name, the foreground activity name, and a list of Element_Records.
- **Element_Record**: One entry of a Screen_State, comprising a view identifier, a text value, a content description, a class name, screen bounds, and the boolean attributes clickable, editable, scrollable, and enabled.
- **Screen_Query**: A single request for a Screen_State or for the Element_Records matching one Target_Descriptor, evaluated on demand and bounded by a node cap and a depth cap.
- **Interaction_Service**: The new Android accessibility component that performs UI_Actions and answers Screen_Queries. It is a component separate from `ScreenContextAccessibilityService`.
- **Planner**: The AURA component that converts a Command into a Plan.
- **Deterministic_Planner**: A rule-based Planner implementation that produces a Plan from a Command using pattern rules and a fixed recipe catalog, without model inference.
- **Model_Planner**: A Planner implementation that produces a Plan by calling the active model through the existing tool-definition types `ToolDefinition`, `ToolParameter`, `FunctionCallRequest`, and `FunctionCallResult`.
- **Session_Controller**: The AURA component that owns Session lifecycle, Step sequencing, budget enforcement, and Terminal_Outcome reporting.
- **Confirmation_Gate**: A blocking prompt presented to the user immediately before a Step whose Irreversibility_Flag is true, resolved only by an explicit user approval or an explicit user rejection, or by timing out.
- **Recovery**: The bounded response to a Step whose Expected_Screen_Condition is unmet, comprising a re-observation of the Screen_State, a repeat of the Step, and a re-derivation of the remaining Steps.
- **Abort**: The immediate, user-visible termination of a Session that performs no further Steps and leaves the Target_App in its current state.
- **Step_Budget**: The maximum number of Steps a single Session may execute.
- **Time_Budget**: The maximum wall-clock duration of a single Session.
- **Low_End_Device**: A device whose Device_RAM or CPU core count is at or below the thresholds stated in this document.
- **Device_RAM**: The total physical memory reported by the device, expressed in megabytes.
- **Session_Trace**: The ordered record of a Session's Steps and outcomes retained for user-visible review and diagnostics.
- **Autonomous_Execution_Option**: A user setting that, when enabled, permits a Session to execute a Step whose Irreversibility_Flag is true without a Confirmation_Gate.
- **Play_Build**: A build of AURA distributed through Google Play.
- **Sideload_Build**: A build of AURA distributed outside Google Play by direct application-package installation.

## Requirements

### Requirement 1: Purely Additive Integration and Non-Regression

**User Story:** As an existing AURA user, I want everything that works today to keep working exactly as it does, so that gaining Interactive Mode costs me nothing.

#### Acceptance Criteria

1. THE AURA SHALL retain every Legacy_Path component with the public members and method signatures those components expose before Interactive_Mode is installed.
2. WHILE Interactive_Mode is inactive, THE OrchestratorService SHALL route each user message through the same path that the OrchestratorService selects before Interactive_Mode is installed.
3. THE AURA SHALL implement Interactive_Mode as a branch of the OrchestratorService that is entered only for a Command accepted by the Session_Controller, leaving the rule-based intent path and the native function-calling path as separate branches.
4. THE `ScreenContextAccessibilityService` SHALL continue to publish `currentPackageName`, `currentScreenContent`, and `currentActivityName` by debounced node traversal with the debounce interval, depth cap, and content-length cap it applies before Interactive_Mode is installed.
5. THE `MainActivity` SHALL continue to answer the channel methods `getScreenContext`, `isAccessibilityEnabled`, and `openAccessibilitySettings` with the argument names and return shapes those methods use before Interactive_Mode is installed.
6. THE AURA SHALL implement the Interaction_Service as an Android component separate from `ScreenContextAccessibilityService`, leaving the source of `ScreenContextAccessibilityService` free of UI_Action code.
7. THE Planner SHALL reuse the existing `ToolDefinition`, `ToolParameter`, `FunctionCallRequest`, and `FunctionCallResult` types without altering the declared members of those types.
8. WHEN a Deep_Link_Action matches an operation already provided by `SmartAppActionsService`, THE Session_Controller SHALL invoke the existing `SmartAppActionsService` method for that operation.
9. WHILE a Session is running, THE AURA SHALL keep the Legacy_Path voice stack able to start speech recognition and text-to-speech playback.
10. THE `IntentDetectionService` SHALL return, for every input it classifies before Interactive_Mode is installed, the same classification it returns after Interactive_Mode is installed.

### Requirement 2: Mode Lifecycle and Explicit Activation

**User Story:** As a user, I want Interactive Mode to start only when I ask for it and to end in a state I can see, so that AURA never drives my apps behind my back.

#### Acceptance Criteria

1. WHEN the user activates Interactive_Mode through the Interactive_Mode control in the AURA interface, THE Session_Controller SHALL set Interactive_Mode to active and display an active-mode indicator.
2. WHILE Interactive_Mode is inactive, THE Session_Controller SHALL decline every request to execute a Step and SHALL report that Interactive_Mode is inactive.
3. THE AURA SHALL set Interactive_Mode to inactive on every application start, independent of the value Interactive_Mode held when the application last stopped.
4. WHEN the user deactivates Interactive_Mode, THE Session_Controller SHALL end any running Session with the Terminal_Outcome `aborted` and set Interactive_Mode to inactive.
5. WHILE Interactive_Mode is active AND no Session is running, THE Session_Controller SHALL hold at most one Session and SHALL accept a new Command.
6. IF a Command arrives WHILE a Session is running, THEN THE Session_Controller SHALL retain the running Session, decline the arriving Command, and report that a Session is already running.
7. WHEN a Session reaches a Terminal_Outcome, THE Session_Controller SHALL display that Terminal_Outcome to the user and release every Screen_Query and UI_Action resource the Session held.
8. WHEN a Session reaches a Terminal_Outcome, THE Session_Controller SHALL keep Interactive_Mode active and ready to accept the next Command.

### Requirement 3: Accessibility Capability Onboarding and Consent

**User Story:** As a user, I want a clear explanation and an explicit choice before AURA can act inside my apps, so that I understand what I am enabling.

#### Acceptance Criteria

1. WHEN the user activates Interactive_Mode WHILE the Interaction_Service is disabled, THE AURA SHALL display a disclosure screen stating the operations Interactive_Mode performs, the data the Interaction_Service reads, and the confirm-before-act posture, and SHALL request the user's acceptance.
2. WHEN the user accepts the disclosure screen, THE AURA SHALL open the Android accessibility settings screen for the Interaction_Service.
3. IF the user declines the disclosure screen, THEN THE AURA SHALL set Interactive_Mode to inactive and keep every Legacy_Path capability available.
4. WHILE the Interaction_Service is disabled, THE Session_Controller SHALL accept a Command whose Plan contains only Deep_Link_Actions and SHALL decline a Command whose Plan contains a UI_Action, reporting that the Interaction_Service is required for that Command.
5. WHEN the user returns to AURA from the Android accessibility settings screen, THE AURA SHALL re-read the enabled state of the Interaction_Service and display that state.
6. THE AURA SHALL declare in the Interaction_Service configuration the narrow purpose of performing user-confirmed operations inside a Target_App on the user's instruction.
7. WHERE the AURA application package targets Android API level 31 or above, THE AURA SHALL include the Play permissions declaration for the Interaction_Service accessibility use in the release submission.
8. WHEN the user disables the Interaction_Service in Android settings WHILE a Session is running, THE Session_Controller SHALL end that Session with the Terminal_Outcome `aborted` and report that the Interaction_Service was disabled.

### Requirement 4: Command Capture from Voice and Text

**User Story:** As a user, I want to give an Interactive Mode command by speaking or typing, so that I can use whichever input suits the moment.

#### Acceptance Criteria

1. WHILE Interactive_Mode is active, THE AURA SHALL accept a Command from the text chat input and from the voice input provided by the Legacy_Path voice stack.
2. WHEN the Legacy_Path voice stack produces a final recognized transcript WHILE Interactive_Mode is active, THE Session_Controller SHALL treat that transcript as the Command text.
3. WHEN a Command is captured, THE AURA SHALL display the captured Command text to the user before the first Step executes.
4. IF a captured Command contains no non-whitespace character, THEN THE Session_Controller SHALL decline the Command and report that no instruction was recognized.
5. IF a captured Command exceeds 1,000 characters, THEN THE Session_Controller SHALL decline the Command and report the character limit.
6. WHEN a Command is captured from voice input, THE Session_Controller SHALL apply the same Plan construction, Confirmation_Gate, and budget rules that apply to a Command captured from text input.

### Requirement 5: Plan Construction

**User Story:** As a user, I want AURA to work out the whole sequence of steps up front and show it to me, so that I know what it intends to do before it starts.

#### Acceptance Criteria

1. WHEN the Session_Controller accepts a Command, THE Planner SHALL produce exactly one Plan containing at least 1 Step and at most the Step_Budget number of Steps.
2. THE Planner SHALL resolve exactly one Target_App package name for each Plan and SHALL record that package name on the Session.
3. THE Planner SHALL assign each Step exactly one Action_Intent, exactly one Expected_Screen_Condition, and exactly one Irreversibility_Flag value.
4. THE Planner SHALL set the Irreversibility_Flag to true for each Step that performs an Irreversible_Operation.
5. WHEN a Plan is produced, THE Session_Controller SHALL display the ordered Step list in user-readable form and SHALL request the user's approval of the Plan before the first Step executes.
6. IF the user rejects a displayed Plan, THEN THE Session_Controller SHALL end the Session with the Terminal_Outcome `aborted` and perform zero Steps.
7. IF the Planner cannot resolve a Target_App package name that is installed on the device, THEN THE Session_Controller SHALL end the Session with the Terminal_Outcome `failed` and report the unresolved application name.
8. IF the Planner produces a Plan containing more Steps than the Step_Budget, THEN THE Session_Controller SHALL end the Session with the Terminal_Outcome `failed` and report that the Command exceeds the Step_Budget.
9. IF a Command requests an operation that is absent from the Action_Intent set, THEN THE Session_Controller SHALL end the Session with the Terminal_Outcome `failed` and report the unsupported operation.
10. THE Planner SHALL produce every Plan before the first Step executes and SHALL leave the Plan's Step count unchanged except during Recovery.

### Requirement 6: Planner Degradation to Deterministic Rules

**User Story:** As a user on a small on-device model, I want Interactive Mode to still work for common commands, so that a limited model does not make the mode useless.

#### Acceptance Criteria

1. WHILE the active model reports the ModelTier value `small`, THE Session_Controller SHALL select the Deterministic_Planner as the Planner for each new Session.
2. WHILE no model is loaded, THE Session_Controller SHALL select the Deterministic_Planner as the Planner for each new Session.
3. WHILE the active model has the tool-calling capability field set to true, THE Session_Controller SHALL select the Model_Planner as the Planner for each new Session.
4. IF the Model_Planner returns a result that is not a `FunctionCallParsed` value, THEN THE Session_Controller SHALL request a Plan from the Deterministic_Planner for the same Command.
5. IF the Model_Planner produces no Plan within 5 seconds of receiving a Command, THEN THE Session_Controller SHALL request a Plan from the Deterministic_Planner for the same Command.
6. IF the Deterministic_Planner holds no recipe matching a Command, THEN THE Session_Controller SHALL end the Session with the Terminal_Outcome `failed` and report that the Command is unrecognized.
7. THE Deterministic_Planner SHALL produce a Plan for a given Command text and a given installed-application set that is identical across repeated calls with that same Command text and that same installed-application set.
8. WHEN the Session_Controller selects a Planner, THE Session_Controller SHALL record the selected Planner identifier in the Session_Trace.

### Requirement 7: Deep-Link-First Action Strategy

**User Story:** As a user on a modest phone, I want AURA to use the fastest available mechanism for each step, so that operations finish quickly without scraping my screen.

#### Acceptance Criteria

1. WHEN the Session_Controller prepares a Step, THE Session_Controller SHALL evaluate the `deep_link` Action_Strategy before the `ui_action` Action_Strategy.
2. WHERE a Deep_Link_Action satisfies a Step's Action_Intent and Target_App, THE Session_Controller SHALL select the `deep_link` Action_Strategy for that Step.
3. WHERE no Deep_Link_Action satisfies a Step's Action_Intent and Target_App, THE Session_Controller SHALL select the `ui_action` Action_Strategy for that Step.
4. WHILE a Step executes under the `deep_link` Action_Strategy, THE Session_Controller SHALL issue zero Screen_Queries for that Step other than the single Screen_Query that evaluates the Step's Expected_Screen_Condition.
5. WHEN every Step of a Plan is satisfiable by a Deep_Link_Action, THE Session_Controller SHALL execute the Session without performing any UI_Action.
6. IF a Deep_Link_Action returns a platform error, THEN THE Session_Controller SHALL select the `ui_action` Action_Strategy for that Step and record the deep-link failure in the Session_Trace.
7. WHEN the Session_Controller selects an Action_Strategy for a Step, THE Session_Controller SHALL record that Action_Strategy in the Session_Trace.

### Requirement 8: UI Action Execution

**User Story:** As a user, I want AURA to tap, type, and scroll inside an app when no shortcut exists, so that commands without a deep link still complete.

#### Acceptance Criteria

1. THE Interaction_Service SHALL perform each of the UI_Action kinds click, set text, scroll, global back, and global home on request from the Session_Controller.
2. WHEN the Session_Controller requests a click UI_Action with a Target_Descriptor, THE Interaction_Service SHALL locate the single Element_Record matching that Target_Descriptor whose clickable attribute is true and SHALL perform the click on that element.
3. WHEN the Session_Controller requests a set text UI_Action with a Target_Descriptor and a text value, THE Interaction_Service SHALL locate the single Element_Record matching that Target_Descriptor whose editable attribute is true and SHALL replace that element's text with the supplied text value.
4. WHEN the Session_Controller requests a scroll UI_Action with a direction, THE Interaction_Service SHALL perform the scroll on the nearest ancestor Element_Record whose scrollable attribute is true.
5. IF a Target_Descriptor matches zero Element_Records, THEN THE Interaction_Service SHALL return a target-not-found result identifying the Target_Descriptor and SHALL leave the Target_App unmodified.
6. IF a Target_Descriptor matches more than one Element_Record, THEN THE Interaction_Service SHALL return an ambiguous-target result reporting the match count and SHALL leave the Target_App unmodified.
7. WHILE the foreground package name differs from the Session's Target_App package name, THE Interaction_Service SHALL decline every UI_Action request and SHALL return a foreground-mismatch result.
8. WHEN the Interaction_Service completes a UI_Action, THE Interaction_Service SHALL return a result stating whether the accessibility action was accepted by the Target_App.
9. THE Interaction_Service SHALL perform every UI_Action on a thread other than the Flutter UI isolate.

### Requirement 9: Bounded Screen State Observation

**User Story:** As a user on a low-RAM phone, I want screen reading to stay cheap, so that Interactive Mode does not make my phone stutter.

#### Acceptance Criteria

1. THE Interaction_Service SHALL answer a Screen_Query only when the Session_Controller issues that Screen_Query.
2. WHEN the Session_Controller issues a Screen_Query carrying a Target_Descriptor, THE Interaction_Service SHALL return only the Element_Records matching that Target_Descriptor.
3. THE Interaction_Service SHALL visit at most 200 accessibility nodes per Screen_Query.
4. THE Interaction_Service SHALL visit accessibility nodes to a maximum tree depth of 12 per Screen_Query.
5. WHEN a Screen_Query reaches the node cap of 200 nodes or the depth cap of 12 levels, THE Interaction_Service SHALL return the Element_Records collected up to that cap together with a truncation marker.
6. WHEN more than one accessibility window-content-changed event arrives within 250 milliseconds, THE Interaction_Service SHALL evaluate at most one Screen_State refresh for those events.
7. THE Interaction_Service SHALL release every accessibility node it acquires during a Screen_Query before returning the Screen_Query result.
8. WHILE no Session is running, THE Interaction_Service SHALL hold zero cached Screen_States and zero cached Element_Records.
9. THE Interaction_Service SHALL return at most 8,192 characters of combined text values and content descriptions per Screen_Query.

### Requirement 10: Confirmation Gates Before Irreversible Operations

**User Story:** As a user, I want to approve anything that cannot be undone, so that AURA never sends, calls, pays, buys, or deletes on its own.

#### Acceptance Criteria

1. WHEN the Session_Controller prepares a Step whose Irreversibility_Flag is true, THE Session_Controller SHALL present a Confirmation_Gate before that Step executes.
2. THE Confirmation_Gate SHALL display the Action_Intent of the pending Step, the Target_App name, and the exact text value the Step will submit when the Step carries a text value.
3. WHILE a Confirmation_Gate is unresolved, THE Session_Controller SHALL execute zero Steps.
4. WHEN the user approves a Confirmation_Gate, THE Session_Controller SHALL execute the single Step that the Confirmation_Gate described.
5. IF the user rejects a Confirmation_Gate, THEN THE Session_Controller SHALL end the Session with the Terminal_Outcome `aborted` and leave the Target_App in its current state.
6. IF a Confirmation_Gate remains unresolved for 30 seconds, THEN THE Session_Controller SHALL end the Session with the Terminal_Outcome `aborted` and report the confirmation timeout.
7. THE Session_Controller SHALL treat each of sending a message, placing a call, initiating a payment, confirming a purchase or order, and deleting user data as an Irreversible_Operation.
8. WHEN a Confirmation_Gate is approved, THE Session_Controller SHALL apply that approval to exactly one Step and SHALL present a further Confirmation_Gate for each subsequent Step whose Irreversibility_Flag is true.
9. THE Session_Controller SHALL record each Confirmation_Gate presentation and its resolution in the Session_Trace.

### Requirement 11: Failure, Timeout, and Recovery

**User Story:** As a user, I want AURA to notice when an app does not look like it expected and stop rather than flail, so that a mismatch cannot cause a wrong action.

#### Acceptance Criteria

1. IF a Step's Expected_Screen_Condition remains unmet 5 seconds after the Step's action is issued, THEN THE Session_Controller SHALL treat that Step as unmet and begin Recovery for that Step.
2. WHEN Recovery begins for a Step, THE Session_Controller SHALL issue one Screen_Query and re-evaluate the Step's Expected_Screen_Condition against the returned Screen_State.
3. WHEN a Step's Expected_Screen_Condition is unmet after re-evaluation, THE Session_Controller SHALL repeat that Step at most 2 times.
4. IF a Step's Expected_Screen_Condition remains unmet after 2 repeat attempts, THEN THE Session_Controller SHALL end the Session with the Terminal_Outcome `failed` and report the Step index and the unmet Expected_Screen_Condition.
5. WHILE a Step whose Irreversibility_Flag is true is in Recovery, THE Session_Controller SHALL present a Confirmation_Gate before each repeat attempt of that Step.
6. IF the foreground package name differs from the Session's Target_App package name WHEN a Step is prepared, THEN THE Session_Controller SHALL end the Session with the Terminal_Outcome `failed` and report the foreground application mismatch.
7. IF the Interaction_Service returns an ambiguous-target result for a Step, THEN THE Session_Controller SHALL end the Session with the Terminal_Outcome `failed` and report that the target element was ambiguous.
8. WHEN a Session ends with the Terminal_Outcome `failed`, THE Session_Controller SHALL report the completed Step count and the total Step count to the user.
9. WHEN a Session ends with the Terminal_Outcome `failed`, THE AURA SHALL keep Interactive_Mode active and keep every Legacy_Path capability available.

### Requirement 12: Abort and Cancellation at Any Step

**User Story:** As a user, I want a single obvious way to stop AURA mid-operation, so that I stay in control at every moment.

#### Acceptance Criteria

1. WHILE a Session is running, THE AURA SHALL display an abort control that is reachable without leaving the foreground Target_App.
2. WHEN the user activates the abort control, THE Session_Controller SHALL end the Session with the Terminal_Outcome `aborted` within 500 milliseconds and execute zero further Steps.
3. WHEN the user speaks the abort phrase recognized by the Legacy_Path voice stack WHILE a Session is running, THE Session_Controller SHALL end the Session with the Terminal_Outcome `aborted`.
4. WHEN a Session ends with the Terminal_Outcome `aborted`, THE Session_Controller SHALL leave the Target_App in the state the Target_App holds at the moment of the Abort.
5. WHEN a Session ends with the Terminal_Outcome `aborted`, THE Session_Controller SHALL cancel every pending Screen_Query and every pending UI_Action of that Session.
6. WHEN a Session ends with the Terminal_Outcome `aborted`, THE Session_Controller SHALL report to the user the count of Steps executed before the Abort.
7. WHILE a Confirmation_Gate is unresolved, THE AURA SHALL keep the abort control active.

### Requirement 13: Step and Time Budgets

**User Story:** As a user, I want a hard ceiling on how long and how far a single command can run, so that Interactive Mode can never loop indefinitely.

#### Acceptance Criteria

1. THE Session_Controller SHALL set the Step_Budget of each Session to 12 Steps.
2. WHEN a Session has executed a number of Steps equal to the Step_Budget AND the Plan holds a further Step, THE Session_Controller SHALL end the Session with the Terminal_Outcome `expired` and report that the Step_Budget was reached.
3. THE Session_Controller SHALL set the Time_Budget of each Session to 90 seconds of wall-clock time measured from acceptance of the Command.
4. WHEN a Session reaches its Time_Budget, THE Session_Controller SHALL end the Session with the Terminal_Outcome `expired` and report that the Time_Budget was reached.
5. THE Session_Controller SHALL exclude the duration of each unresolved Confirmation_Gate from the elapsed time counted against the Time_Budget.
6. THE Session_Controller SHALL count each repeat attempt performed during Recovery against the Step_Budget.
7. WHILE a Session is running, THE AURA SHALL display the executed Step count and the Step_Budget.
8. WHEN a Session ends with the Terminal_Outcome `expired`, THE Session_Controller SHALL leave the Target_App in its current state and keep Interactive_Mode active.

### Requirement 14: Performance Budgets on Low-End Devices

**User Story:** As a user with a 2 GB phone, I want Interactive Mode to run without stutter, so that the feature is usable on the device I actually own.

#### Acceptance Criteria

1. THE AURA SHALL classify a device as a Low_End_Device when the Device_RAM is at or below 3,072 megabytes or the reported CPU core count is at or below 4.
2. WHILE a Session is running on a Low_End_Device, THE AURA SHALL render the AURA interface with a 90th-percentile combined frame build and raster time at or below 16 milliseconds.
3. THE Session_Controller SHALL perform every Screen_Query, every Plan construction call, and every UI_Action dispatch off the Flutter UI isolate, leaving no single Flutter UI isolate task introduced by Interactive_Mode exceeding 8 milliseconds.
4. WHEN a Step executes under the `deep_link` Action_Strategy on a Low_End_Device, THE Session_Controller SHALL complete that Step within 800 milliseconds measured from Step dispatch to Expected_Screen_Condition evaluation.
5. WHEN a Step executes under the `ui_action` Action_Strategy on a Low_End_Device, THE Session_Controller SHALL complete that Step within 1,500 milliseconds measured from Step dispatch to Expected_Screen_Condition evaluation.
6. WHEN the Session_Controller issues a Screen_Query on a Low_End_Device, THE Interaction_Service SHALL return the Screen_Query result within 300 milliseconds.
7. WHILE a Session is running on a Low_End_Device, THE AURA SHALL keep the resident memory added by Interactive_Mode at or below 40 megabytes above the resident memory measured immediately before the Session began.
8. WHEN a Session reaches a Terminal_Outcome, THE AURA SHALL release the memory the Session allocated for Screen_States, Element_Records, and the Plan, returning resident memory to within 5 megabytes of the pre-Session measurement.
9. WHERE the device is classified as a Low_End_Device, THE Session_Controller SHALL select the Deterministic_Planner for each new Session when the active model reports the ModelTier value `small`.
10. IF a Screen_Query exceeds 300 milliseconds, THEN THE Interaction_Service SHALL return the Element_Records collected up to that point together with a truncation marker.

### Requirement 15: Play-Policy Autonomy Posture

**User Story:** As the AURA publisher, I want the shipped behavior to match Google Play's accessibility policy, so that the application stays distributable.

#### Acceptance Criteria

1. THE Session_Controller SHALL begin every Session from an explicit user Command and SHALL begin zero Sessions from a timer, a push message, a broadcast, or a model-initiated request.
2. THE Session_Controller SHALL execute the Steps of a Session one at a time, completing the Expected_Screen_Condition evaluation of each Step before dispatching the next Step.
3. THE Session_Controller SHALL present the Plan for user approval before the first Step of every Session executes.
4. WHERE the running build is a Play_Build, THE AURA SHALL omit the Autonomous_Execution_Option from the settings interface and SHALL present a Confirmation_Gate for every Step whose Irreversibility_Flag is true.
5. WHERE the running build is a Sideload_Build, THE AURA SHALL present the Autonomous_Execution_Option in the settings interface with the value disabled on first run.
6. WHEN the user enables the Autonomous_Execution_Option, THE AURA SHALL display a notice stating that the option applies to Sideload_Builds only and that the user accepts responsibility for the actions performed, and SHALL record the acceptance.
7. WHILE the Autonomous_Execution_Option is enabled, THE Session_Controller SHALL apply the Step_Budget, the Time_Budget, and the abort control to every Session.
8. THE AURA SHALL restrict the Interaction_Service purpose declaration to performing user-confirmed operations inside a Target_App on the user's instruction.

### Requirement 16: Privacy of Screen Content

**User Story:** As a user, I want what is on my screen to stay on my device, so that using Interactive Mode does not leak my private information.

#### Acceptance Criteria

1. THE AURA SHALL retain every Screen_State and every Element_Record in process memory only, writing zero Screen_State values and zero Element_Record values to persistent storage.
2. WHILE the active model runs on the device, THE AURA SHALL send zero Screen_State values and zero Element_Record values to any network destination.
3. WHERE the user has selected an online model as the active model, THE AURA SHALL request the user's confirmation to send Screen_State values to that online model before the first Screen_State value of the Session is sent.
4. IF the user declines to send Screen_State values to an online model, THEN THE Session_Controller SHALL select the Deterministic_Planner for that Session and send zero Screen_State values to the online model.
5. WHEN a Session reaches a Terminal_Outcome, THE AURA SHALL discard every Screen_State value and every Element_Record value the Session held.
6. THE AURA SHALL retain zero text values captured from an Element_Record whose editable attribute is true and whose input type is a password type.
7. WHEN a Session_Trace entry describes a Step, THE AURA SHALL record the Action_Intent, the Target_App package name, the Action_Strategy, the Step outcome, and the elapsed milliseconds, and SHALL record zero Element_Record text values.

### Requirement 17: Observability Without Content Leakage

**User Story:** As a user and as a developer diagnosing a failure, I want a readable trace of what happened, so that problems can be fixed without exposing screen text.

#### Acceptance Criteria

1. WHEN a Session executes a Step, THE AURA SHALL append one Session_Trace entry for that Step containing the Step index, the Action_Intent, the Action_Strategy, the Step outcome, and the elapsed milliseconds.
2. WHEN a Session reaches a Terminal_Outcome, THE AURA SHALL append one Session_Trace entry containing the Terminal_Outcome, the executed Step count, and the total elapsed milliseconds.
3. THE AURA SHALL make the Session_Trace of the most recent Session viewable by the user from the AURA interface.
4. THE AURA SHALL retain the Session_Traces of at most 10 Sessions and SHALL discard the oldest retained Session_Trace when an eleventh Session_Trace is appended.
5. WHEN the AURA writes a diagnostic log entry for Interactive_Mode, THE AURA SHALL replace each Element_Record text value and each Element_Record content description with a redaction marker.
6. WHEN a Target_Descriptor is recorded in the Session_Trace or in a diagnostic log entry, THE AURA SHALL record the view identifier and the element class name and SHALL replace the text value with a redaction marker.
7. WHEN the AURA writes a diagnostic log entry for a set text UI_Action, THE AURA SHALL record the submitted text length in characters and SHALL replace the submitted text with a redaction marker.
8. THE AURA SHALL retain every Session_Trace in application-private storage that is readable only by AURA.
