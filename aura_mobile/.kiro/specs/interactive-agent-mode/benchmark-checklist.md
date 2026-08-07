# Interactive Agent Mode — On-Device Benchmark Checklist

Task 13. These budgets are verified by measurement on a physical Reference Low-End Device, not by CI assertions,
because they depend on real hardware timing, the platform accessibility pipeline, and live memory pressure.

Record each result. A breach is filed as a defect against the implementation — the budget is not relaxed to fit
the number (design decision, task 13.1).

## Reference Low-End Device

The target baseline (requirements Glossary):

- 4 CPU cores
- 3 GB RAM
- Android 10 (API 29)
- No dedicated NPU
- At least three other apps resident during the run

Your connected device (`CPH2381`, Android 14, arm64) is **stronger** than the baseline, so passing on it is
necessary but not sufficient. Where possible, also test on a device at or near the baseline.

## Setup

1. Build a profile APK (release-like timing, with profiling available):
   ```
   flutter run --profile -d <deviceId>
   ```
2. Enable the accessibility service: Settings → Accessibility → AURA → On.
3. Turn on Interactive Mode: drawer → Interactive Mode → toggle on.
4. Open Flutter DevTools (the URL printed by `flutter run`) → Performance and Memory tabs.

## Budgets to verify

| # | Requirement | Budget | How to measure | Result | Pass? |
|---|---|---|---|---|---|
| B1 | 13.1 | UI stays within 16 ms frames during narration; ≤ 2 consecutive dropped frames | DevTools Performance: record while a multi-step run narrates; inspect the frame chart for jank bars | | |
| B2 | 13.3 | Rule planning ≤ 300 ms | Covered by the automated micro-benchmark `agent_planning_benchmark_test.dart`; also confirm on-device via a debug log timestamp around `RuleBasedPlanner.plan` | | |
| B3 | 13.5 | Deep-link dispatch ≤ 400 ms (excludes target app launch) | Time from `DeepLinkDispatcher.dispatch` entry to its returned outcome; log timestamps | | |
| B4 | 13.6 | Targeted node query ≤ 150 ms | Time a `findNodes` round on a busy screen (e.g. a chat list); log timestamps in `AgentActionSurface.findNodes` | | |
| B5 | 13.7 | Session memory delta ≤ 40 MB | DevTools Memory: snapshot with mode off, enter a session and run 3 commands, snapshot again; delta ≤ 40 MB | | |
| B6 | 13.8 | Zero added cost when mode is off | DevTools Memory + Performance with mode off vs. current `main` build: no measurable difference | | |
| B7 | 13.9 | An animating foreground app does not cause query storms | Open a screen with continuous animation (video/loader), start a UI-action run; confirm signature polling stays on the 350 ms cadence (log count of `getScreenSignature` calls/sec) | | |

## Functional smoke (real apps)

Run each command with Interactive Mode on and confirm the plan preview → gate → narration → result flow. These are
the acceptance-by-example checks the design defers to a device.

| Command | Expected | Result |
|---|---|---|
| "open WhatsApp" | Plan preview (1 step), WhatsApp opens after ack | |
| "message <contact> on WhatsApp saying hello" | 2-step plan; **gate shows the exact recipient + message** before sending | |
| "play <song> on spotify" | Spotify opens to the track | |
| "search for <item> on amazon" | Amazon opens with the search | |
| "navigate to <place>" | Maps opens directions | |
| Decline the send gate | Nothing sends; run reports aborted | |
| Tap Stop mid-run | Stops before the next step; reports which steps completed | |
| Command naming an uninstalled app | Reports the missing app; no steps run | |
| A banking/login screen in the foreground during a UI step | Step is refused (secure window); run fails gracefully | |
| Switch to an app not in the plan mid-run | Run pauses and asks to continue or abort | |

## Non-regression spot check (device)

With Interactive Mode **off**, confirm each still behaves exactly as before:

- [ ] Normal chat send and streaming
- [ ] Voice assistant
- [ ] Screen Reader AI (uses the same accessibility service)
- [ ] Smart summarizer / share-in
- [ ] Study tools, automation rules, document generation
- [ ] Model selection and download

## Sign-off

- Device(s) tested:
- Build:
- Date:
- All budgets within limits: ☐  (file defects for any breach)
- All functional smokes pass: ☐
- Non-regression clean: ☐
