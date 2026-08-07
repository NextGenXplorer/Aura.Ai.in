/// Deterministic, model-free planner for the command shapes AURA already
/// recognises. Runs in well under the rule-plan budget and works with no model
/// loaded (Req 4.5, 13.3). Returns null for anything it does not cover, so the
/// runner can fall back to the model planner (Req 4.6).
///
/// Feature: interactive-agent-mode
library;

import '../models/agent_plan.dart';
import '../models/agent_step.dart';

class RuleBasedPlanner {
  const RuleBasedPlanner();

  /// Common app names mapped to the token `AppControlService.openApp` expects.
  /// Kept intentionally small and additive; unknown apps still plan an openApp
  /// step using the spoken name, and the dispatcher reports if it is missing.
  static const Map<String, String> _knownApps = {
    'whatsapp': 'whatsapp',
    'spotify': 'spotify',
    'youtube': 'youtube',
    'instagram': 'instagram',
    'chrome': 'chrome',
    'gmail': 'gmail',
    'maps': 'maps',
    'camera': 'camera',
    'settings': 'settings',
    'phone': 'phone',
    'messages': 'messages',
  };

  // "open X and send <msg> to <name>" / "message <name> on whatsapp saying <msg>"
  static final RegExp _whatsappSend = RegExp(
    r'(?:whatsapp|message|msg|text)\s+(?:to\s+)?(?<name>[a-z0-9 ._-]+?)'
    r'\s+(?:saying|that|:|with)\s+(?<msg>.+)$',
    caseSensitive: false,
  );

  // "open <app> and search <query>" / "search <query> on <app>"
  static final RegExp _searchInApp = RegExp(
    r'search\s+(?:for\s+)?(?<query>.+?)\s+(?:on|in)\s+(?<app>[a-z0-9 ._-]+)$',
    caseSensitive: false,
  );

  // "play <query> on spotify" / "play <query>"
  static final RegExp _playMedia = RegExp(
    r'play\s+(?<query>.+?)(?:\s+on\s+spotify)?$',
    caseSensitive: false,
  );

  // "navigate to <dest>" / "directions to <dest>" / "take me to <dest>"
  static final RegExp _navigate = RegExp(
    r'(?:navigate|directions|take\s+me|go)\s+to\s+(?<dest>.+)$',
    caseSensitive: false,
  );

  // "open <app>" / "launch <app>"
  static final RegExp _openApp = RegExp(
    r'^(?:open|launch|start)\s+(?<app>[a-z0-9 ._-]+)$',
    caseSensitive: false,
  );

  Future<AgentPlan?> plan(String command, {Set<String>? installedApps}) async {
    final text = command.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();

    // WhatsApp send: open app, then a deep-link sendWhatsApp (irreversible).
    final wa = _whatsappSend.firstMatch(lower);
    if (wa != null && lower.contains('whatsapp')) {
      // The app name can appear between the contact and the message
      // ("message John on whatsapp saying ..."); strip a trailing "on <app>"
      // clause so the contact is just the name.
      final name = wa
          .namedGroup('name')!
          .trim()
          .replaceFirst(RegExp(r'\s+on\s+\w+$', caseSensitive: false), '')
          .trim();
      final msg = _originalCase(text, wa.namedGroup('msg')!.trim());
      return _plan(command, PlannerSource.rule, 'Message $name on WhatsApp', [
        _openAppStep('whatsapp'),
        AgentStep(
          id: 's2',
          kind: StepKind.deepLinkAction,
          strategy: ActionStrategy.deepLink,
          narration: 'Send "$msg" to $name on WhatsApp',
          isIrreversible: true,
          targetPackage: 'whatsapp',
          deepLinkMethod: 'sendWhatsApp',
          deepLinkArgs: {'contact': name, 'message': msg},
        ),
      ]);
    }

    // Search inside an app.
    final search = _searchInApp.firstMatch(lower);
    if (search != null) {
      final query = _originalCase(text, search.namedGroup('query')!.trim());
      final app = search.namedGroup('app')!.trim();
      return _plan(command, PlannerSource.rule, 'Search $app for "$query"', [
        _openAppStep(app),
        AgentStep(
          id: 's2',
          kind: StepKind.deepLinkAction,
          strategy: ActionStrategy.deepLink,
          narration: 'Search $app for "$query"',
          targetPackage: app,
          deepLinkMethod: 'searchOnApp',
          deepLinkArgs: {'appName': app, 'query': query},
        ),
      ]);
    }

    // Play media.
    if (lower.startsWith('play ')) {
      final media = _playMedia.firstMatch(lower);
      if (media != null) {
        final query = _originalCase(text, media.namedGroup('query')!.trim());
        return _plan(command, PlannerSource.rule, 'Play "$query" on Spotify', [
          AgentStep(
            id: 's1',
            kind: StepKind.deepLinkAction,
            strategy: ActionStrategy.deepLink,
            narration: 'Play "$query" on Spotify',
            targetPackage: 'spotify',
            deepLinkMethod: 'playOnSpotify',
            deepLinkArgs: {'query': query},
          ),
        ]);
      }
    }

    // Navigate.
    final nav = _navigate.firstMatch(lower);
    if (nav != null) {
      final dest = _originalCase(text, nav.namedGroup('dest')!.trim());
      return _plan(command, PlannerSource.rule, 'Navigate to $dest', [
        AgentStep(
          id: 's1',
          kind: StepKind.deepLinkAction,
          strategy: ActionStrategy.deepLink,
          narration: 'Get directions to $dest',
          targetPackage: 'maps',
          deepLinkMethod: 'openApp',
          deepLinkArgs: {'app': 'navigate:$dest'},
        ),
      ]);
    }

    // Bare open app.
    final open = _openApp.firstMatch(lower);
    if (open != null) {
      final app = open.namedGroup('app')!.trim();
      return _plan(command, PlannerSource.rule, 'Open $app', [_openAppStep(app)]);
    }

    return null;
  }

  AgentStep _openAppStep(String app) {
    final resolved = _knownApps[app.toLowerCase()] ?? app;
    return AgentStep(
      id: 's1',
      kind: StepKind.openApp,
      strategy: ActionStrategy.deepLink,
      narration: 'Open $app',
      targetPackage: resolved,
      deepLinkMethod: 'openApp',
      deepLinkArgs: {'app': resolved},
      postCondition: PackageBecomes(resolved),
    );
  }

  AgentPlan _plan(
    String command,
    PlannerSource source,
    String summary,
    List<AgentStep> steps,
  ) => AgentPlan(
    commandText: command,
    steps: steps,
    summary: summary,
    source: source,
  );

  /// Recovers the original-case substring for [lowerFragment] from [original]
  /// so messages/queries are not forced to lower case in what the user sees or
  /// what is sent.
  String _originalCase(String original, String lowerFragment) {
    final idx = original.toLowerCase().indexOf(lowerFragment);
    if (idx < 0) return lowerFragment;
    return original.substring(idx, idx + lowerFragment.length);
  }
}
