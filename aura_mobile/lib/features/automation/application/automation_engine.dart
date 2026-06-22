import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'package:aura_mobile/core/services/app_control_service.dart';
import 'package:aura_mobile/features/automation/data/automation_repository.dart';
import 'package:aura_mobile/features/automation/domain/automation_rule.dart';
import 'package:aura_mobile/features/orchestrator/orchestrator_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/domain/services/memory_service.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart' show voiceServiceProvider;
import 'package:aura_mobile/core/services/duckduckgo_service.dart';
import 'package:aura_mobile/core/services/screen_context_service.dart';
import 'package:aura_mobile/core/services/notification_digest_service.dart';
import 'package:aura_mobile/core/services/smart_app_actions_service.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final automationEngineProvider = Provider((ref) {
  return AutomationEngine(
    ref,
    ref.read(automationRepositoryProvider),
    ref.read(orchestratorServiceProvider),
  );
});

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

/// Thrown when an automation rule fails validation.
class AutomationValidationException implements Exception {
  final List<ValidationError> errors;
  AutomationValidationException(this.errors);

  @override
  String toString() =>
      'Validation failed: ${errors.map((e) => e.message).join(', ')}';
}

/// Thrown when the maximum number of automation rules has been reached.
class AutomationLimitException implements Exception {
  final String message;
  AutomationLimitException(this.message);

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// AutomationEngine
// ---------------------------------------------------------------------------

/// Orchestrates validation, persistence, and background-task scheduling
/// for automation rules.
class AutomationEngine {
  final Ref _ref;
  final AutomationRepository _repository;
  final OrchestratorService _orchestrator;

  /// Hard limit on the number of rules a user can create.
  static const int maxRules = 50;

  /// Prefix used for workmanager task names so they can be identified.
  static const String taskPrefix = 'automation_rule_';

  AutomationEngine(this._ref, this._repository, this._orchestrator);

  // ─────────────────────────────────────────────────────────────────────────
  // Validation
  // ─────────────────────────────────────────────────────────────────────────

  /// Validates an [AutomationRule] and returns a list of [ValidationError]s.
  static List<ValidationError> validateRule(AutomationRule rule) {
    final errors = <ValidationError>[];

    // Name validation
    if (rule.name.isEmpty) {
      errors.add(const ValidationError(
        field: 'name',
        message: 'Name is required',
      ));
    } else if (rule.name.length > 100) {
      errors.add(const ValidationError(
        field: 'name',
        message: 'Name must be 100 characters or fewer',
      ));
    }

    // Action instruction validation
    if (rule.actionInstruction.isEmpty) {
      errors.add(const ValidationError(
        field: 'actionInstruction',
        message: 'Action instruction is required',
      ));
    } else if (rule.actionInstruction.length > 500) {
      errors.add(const ValidationError(
        field: 'actionInstruction',
        message: 'Action instruction must be 500 characters or fewer',
      ));
    }

    // Trigger-specific validation
    switch (rule.triggerType) {
      case TriggerType.scheduled:
        if (rule.scheduledTime == null) {
          errors.add(const ValidationError(
            field: 'scheduledTime',
            message: 'Scheduled time is required for scheduled triggers',
          ));
        } else if (rule.scheduledTime!.isBefore(DateTime.now())) {
          errors.add(const ValidationError(
            field: 'scheduledTime',
            message: 'Scheduled time must be in the future',
          ));
        }
        break;

      case TriggerType.recurring:
        if (rule.repeatInterval == null) {
          errors.add(const ValidationError(
            field: 'repeatInterval',
            message: 'Repeat interval is required for recurring triggers',
          ));
        } else if (rule.repeatInterval! < const Duration(minutes: 15)) {
          errors.add(const ValidationError(
            field: 'repeatInterval',
            message: 'Repeat interval must be at least 15 minutes',
          ));
        }
        break;

      case TriggerType.conditionBased:
        if (rule.checkInterval < const Duration(minutes: 15)) {
          errors.add(const ValidationError(
            field: 'checkInterval',
            message: 'Check interval must be at least 15 minutes',
          ));
        } else if (rule.checkInterval > const Duration(hours: 24)) {
          errors.add(const ValidationError(
            field: 'checkInterval',
            message: 'Check interval must not exceed 24 hours',
          ));
        }
        break;

      default:
        break;
    }

    return errors;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CRUD Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Creates and persists a new automation rule, then registers a background
  /// task via Workmanager.
  Future<void> createRule(AutomationRule rule) async {
    // 1. Validate
    final errors = validateRule(rule);
    if (errors.isNotEmpty) {
      throw AutomationValidationException(errors);
    }

    // 2. Parse instruction if needed
    final String? resolvedJson;
    if (rule.actionJson != null && rule.actionJson!.isNotEmpty) {
      resolvedJson = rule.actionJson;
    } else {
      resolvedJson = await _orchestrator.parseInstructionToToolCall(
          rule.actionInstruction);
    }
    final ruleWithJson = rule.copyWith(actionJson: resolvedJson);

    // 3. Check rule limit
    final count = await _repository.getRuleCount();
    if (count >= maxRules) {
      throw AutomationLimitException(
        'Cannot create rule: maximum of $maxRules rules reached',
      );
    }

    // 4. Persist to database
    await _repository.insertRule(ruleWithJson);

    // 5. Register background task
    try {
      if (ruleWithJson.isEnabled) {
        await _registerTask(ruleWithJson);
      }
    } catch (e) {
      await _repository.deleteRule(ruleWithJson.id);
      rethrow;
    }
  }

  /// Updates an existing automation rule.
  Future<void> updateRule(AutomationRule rule) async {
    final errors = validateRule(rule);
    if (errors.isNotEmpty) {
      throw AutomationValidationException(errors);
    }

    final String? resolvedJson;
    if (rule.actionJson != null && rule.actionJson!.isNotEmpty) {
      resolvedJson = rule.actionJson;
    } else {
      resolvedJson = await _orchestrator.parseInstructionToToolCall(
          rule.actionInstruction);
    }
    final ruleWithJson = rule.copyWith(actionJson: resolvedJson);

    await _cancelTask(ruleWithJson.id);
    await _repository.updateRule(ruleWithJson);

    if (ruleWithJson.isEnabled) {
      await _registerTask(ruleWithJson);
    }
  }

  /// Deletes an automation rule by ID. Cancels its background task first.
  Future<void> deleteRule(String ruleId) async {
    await _cancelTask(ruleId);
    await _repository.deleteRule(ruleId);
  }

  /// Toggles whether a rule is enabled or disabled.
  Future<void> setEnabled(String ruleId, bool enabled) async {
    final rule = await _repository.getRule(ruleId);
    if (rule == null) return;

    final updated = rule.copyWith(
      isEnabled: enabled,
      updatedAt: DateTime.now(),
    );
    await _repository.updateRule(updated);

    if (enabled) {
      await _registerTask(updated);
    } else {
      await _cancelTask(ruleId);
    }
  }

  /// Returns all automation rules for the management UI.
  Future<List<AutomationRule>> getAllRules() async {
    return _repository.getAllRules();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Event Triggers (Clipboard & Notifications)
  // ─────────────────────────────────────────────────────────────────────────

  /// Triggered whenever new text is copied to the clipboard.
  Future<void> checkAndTriggerClipboardFlows(String clipboardText) async {
    try {
      final rules = await getAllRules();
      for (final rule in rules) {
        if (rule.isEnabled && rule.triggerType == TriggerType.onClipboardCopy) {
          final filter = rule.condition ?? '';
          if (filter.isEmpty || clipboardText.toLowerCase().contains(filter.toLowerCase())) {
            final initialContext = {
              'clipboard': clipboardText,
            };
            await executeRuleNow(rule, initialContext: initialContext);
          }
        }
      }
    } catch (e) {
      print('AutomationEngine: Clipboard trigger failed: $e');
    }
  }

  /// Triggered whenever another app posts a notification.
  Future<void> checkAndTriggerNotificationFlows(String appName, String notificationText) async {
    try {
      final rules = await getAllRules();
      for (final rule in rules) {
        if (rule.isEnabled && rule.triggerType == TriggerType.onNotificationReceived) {
          final filter = rule.condition ?? '';
          if (filter.isEmpty ||
              appName.toLowerCase().contains(filter.toLowerCase()) ||
              notificationText.toLowerCase().contains(filter.toLowerCase())) {
            final initialContext = {
              'notification_text': notificationText,
              'notification_app': appName,
            };
            await executeRuleNow(rule, initialContext: initialContext);
          }
        }
      }
    } catch (e) {
      print('AutomationEngine: Notification trigger failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Workflow Execution Engine
  // ─────────────────────────────────────────────────────────────────────────

  /// Immediately executes [rule] from the main isolate.
  Future<String> executeRuleNow(AutomationRule rule, {Map<String, String>? initialContext}) async {
    try {
      final List<WorkflowStep> steps;
      if (rule.isWorkflow) {
        steps = rule.workflowSteps;
      } else {
        // Wrap legacy action as a single step workflow
        final jsonStr = rule.actionJson ?? '';
        final type = jsonStr.isNotEmpty ? (jsonDecode(jsonStr)['name'] as String? ?? 'legacy') : 'legacy';
        final params = jsonStr.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(jsonStr)['arguments'] as Map? ?? {}) : <String, dynamic>{};
        steps = [
          WorkflowStep(
            id: 'step_1',
            type: type,
            params: params,
          )
        ];
      }
      final result = await executeWorkflow(steps, initialContext: initialContext);
      await _repository.updateLastExecutedAt(rule.id, DateTime.now());
      return result;
    } catch (e) {
      return 'Failed: $e';
    }
  }

  /// Evaluates a list of workflow steps sequentially.
  Future<String> executeWorkflow(List<WorkflowStep> steps, {Map<String, String>? initialContext}) async {
    final context = <String, String>{};
    if (initialContext != null) {
      context.addAll(initialContext);
    }

    final appControl = AppControlService();
    final memoryService = _ref.read(memoryServiceProvider);
    final voiceService = _ref.read(voiceServiceProvider);
    final searchService = _ref.read(duckDuckGoServiceProvider);
    final llm = _ref.read(llmServiceProvider);

    final StringBuffer logs = StringBuffer();

    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final stepId = step.id.isEmpty ? 'step_${i + 1}' : step.id;

      // Resolve step placeholders
      final resolvedParams = <String, dynamic>{};
      step.params.forEach((key, val) {
        if (val is String) {
          resolvedParams[key] = _resolvePlaceholders(val, context);
        } else {
          resolvedParams[key] = val;
        }
      });

      String stepResult = '';
      try {
        switch (step.type) {
          case 'readClipboard':
            final clip = await Clipboard.getData(Clipboard.kTextPlain);
            stepResult = clip?.text ?? '';
            break;

          case 'readScreen':
            final screenService = _ref.read(screenContextServiceProvider);
            stepResult = await screenService.getScreenContent();
            break;

          case 'readNotifications':
            final digestService = _ref.read(notificationDigestServiceProvider);
            final notifs = await digestService.fetchRecentNotifications(since: const Duration(hours: 1));
            stepResult = notifs.map((n) => '[${n.appName}] ${n.title}: ${n.text}').join('\n');
            break;

          case 'webSearch':
            final query = resolvedParams['query']?.toString() ?? '';
            if (query.isNotEmpty) {
              final results = await searchService.search(query);
              stepResult = results.map((r) => '${r.title}\n${r.snippet}').join('\n\n');
            }
            break;

          case 'aiGenerate':
            final prompt = resolvedParams['prompt']?.toString() ?? '';
            if (prompt.isNotEmpty) {
              final responseBuffer = StringBuffer();
              await for (final chunk in llm.chat(
                prompt,
                systemPrompt: "You are AURA, a precise local AI assistant executing an automation workflow step.",
                temperature: 0.3,
                maxTokens: 512,
              )) {
                responseBuffer.write(chunk);
              }
              stepResult = responseBuffer.toString().trim();
            }
            break;

          case 'saveMemory':
            final content = resolvedParams['content']?.toString() ?? '';
            if (content.isNotEmpty) {
              await memoryService.saveMemory(content);
              stepResult = 'Saved to memory: "$content"';
            }
            break;

          case 'speakText':
            final text = resolvedParams['text']?.toString() ?? '';
            if (text.isNotEmpty) {
              await voiceService.speak(text);
              stepResult = 'Spoken: "$text"';
            }
            break;

          case 'showNotification':
            final title = resolvedParams['title']?.toString() ?? 'AURA Flow';
            final body = resolvedParams['body']?.toString() ?? '';
            await _showLocalNotification(stepId.hashCode, title, body);
            stepResult = 'Notification shown: $title - $body';
            break;

          case 'toggleFlashlight':
            final state = resolvedParams['state'] == true || resolvedParams['state']?.toString().toLowerCase() == 'on';
            await appControl.toggleTorch(state);
            stepResult = state ? 'Flashlight ON' : 'Flashlight OFF';
            break;

          case 'openApp':
            final app = resolvedParams['appName']?.toString() ?? '';
            await appControl.openApp(app);
            stepResult = 'Opened $app';
            break;

          case 'sendSMS':
            final contact = resolvedParams['contact']?.toString() ?? '';
            final msg = resolvedParams['message']?.toString() ?? '';
            await appControl.sendSMS(contact, msg);
            stepResult = 'Sent SMS to $contact';
            break;

          // Action mappings for legacy tool execution
          case 'toggle_torch':
            final stateArg = (resolvedParams['state']?.toString() ?? 'on').toLowerCase();
            final state = !(stateArg == 'off' || stateArg == 'false' || stateArg == 'disable');
            await appControl.toggleTorch(state);
            stepResult = state ? 'Flashlight ON' : 'Flashlight OFF';
            break;
          case 'send_sms':
            final name = resolvedParams['name']?.toString() ?? '';
            final msg = resolvedParams['message']?.toString() ?? '';
            await appControl.sendSMS(name, msg);
            stepResult = 'SMS sent to $name: "$msg"';
            break;
          case 'dial_contact':
            final contactName = resolvedParams['contactName']?.toString() ?? '';
            await appControl.dialContact(contactName);
            stepResult = 'Dialing $contactName';
            break;
          case 'open_app':
            final appName = resolvedParams['appName']?.toString() ?? '';
            await appControl.openApp(appName);
            stepResult = 'Opened $appName';
            break;
          case 'open_settings':
            final type = resolvedParams['type']?.toString() ?? 'general';
            await appControl.openSettings(type);
            stepResult = 'Opened $type settings';
            break;
          case 'open_camera':
            await appControl.openCamera();
            stepResult = 'Opened camera';
            break;
          case 'web_search':
            final queryArg = resolvedParams['query']?.toString() ?? '';
            await appControl.openApp('navigate:https://www.google.com/search?q=${Uri.encodeComponent(queryArg)}');
            stepResult = 'Searched Google for "$queryArg"';
            break;
          case 'ai_digest':
            final digestService = _ref.read(notificationDigestServiceProvider);
            final buffer = StringBuffer();
            await for (final chunk in digestService.generateDigest(since: const Duration(hours: 3))) {
              buffer.write(chunk);
            }
            final digestText = buffer.toString().trim();
            await _showLocalNotification(stepId.hashCode, 'AURA Notification Digest', truncateNotification(digestText));
            stepResult = 'Notification digest generated';
            break;
          case 'save_memory':
            final memoryContent = resolvedParams['content']?.toString() ?? '';
            if (memoryContent.isNotEmpty) {
              await memoryService.saveMemory(memoryContent);
              stepResult = 'Saved memory: "$memoryContent"';
            }
            break;

          // Smart App Actions
          case 'send_whatsapp':
            final contact = resolvedParams['contact']?.toString() ?? '';
            final msg = resolvedParams['message']?.toString() ?? '';
            final smartActions = _ref.read(smartAppActionsProvider);
            await smartActions.sendWhatsApp(contact, msg);
            stepResult = 'WhatsApp sent to $contact: "$msg"';
            break;

          case 'play_spotify':
            final query = resolvedParams['query']?.toString() ?? '';
            final smartActions = _ref.read(smartAppActionsProvider);
            await smartActions.playOnSpotify(query);
            stepResult = 'Playing "$query" on Spotify';
            break;

          case 'upi_payment':
            final upiId = resolvedParams['upiId']?.toString();
            final amount = resolvedParams['amount']?.toString();
            final note = resolvedParams['note']?.toString();
            final smartActions = _ref.read(smartAppActionsProvider);
            await smartActions.makeUpiPayment(upiId: upiId, amount: amount, note: note);
            stepResult = 'UPI payment of ₹$amount to $upiId';
            break;

          case 'book_ride':
            final destination = resolvedParams['destination']?.toString() ?? '';
            final app = resolvedParams['app']?.toString();
            final smartActions = _ref.read(smartAppActionsProvider);
            await smartActions.bookRide(destination, app: app);
            stepResult = 'Booking ride to $destination';
            break;

          case 'order_food':
            final restaurant = resolvedParams['restaurant']?.toString();
            final app = resolvedParams['app']?.toString();
            final smartActions = _ref.read(smartAppActionsProvider);
            await smartActions.orderFood(restaurant: restaurant, app: app);
            stepResult = 'Ordering food${restaurant != null ? ' from $restaurant' : ''}';
            break;

          case 'share_content':
            final text = resolvedParams['text']?.toString() ?? '';
            final app = resolvedParams['app']?.toString();
            final smartActions = _ref.read(smartAppActionsProvider);
            await smartActions.shareText(text, app: app);
            stepResult = 'Shared text${app != null ? ' to $app' : ''}';
            break;

          case 'open_profile':
            final platform = resolvedParams['platform']?.toString() ?? '';
            final username = resolvedParams['username']?.toString() ?? '';
            final smartActions = _ref.read(smartAppActionsProvider);
            await smartActions.openProfile(platform, username);
            stepResult = 'Opened @$username on $platform';
            break;

          default:
            stepResult = 'Skipped unknown step: ${step.type}';
        }
      } catch (e) {
        stepResult = 'Failed: $e';
      }

      context[stepId] = stepResult;
      logs.writeln('${step.type} results: $stepResult');
    }

    return logs.toString().trim();
  }

  String _resolvePlaceholders(String template, Map<String, String> context) {
    var result = template;
    context.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }

  Future<void> _showLocalNotification(int id, String title, String body) async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'automation_channel',
      'Automation Rules',
      channelDescription: 'Notifications for automation rule executions',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(id, title, body, details);
  }

  // ─────────────────────────────────────────────────────────────────────────

  /// Truncates a notification body to [maxLength] characters, appending an
  /// ellipsis (…) if truncated.
  static String truncateNotification(String response, {int maxLength = 256}) {
    if (response.length <= maxLength) return response;
    return '${response.substring(0, maxLength)}\u2026';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Registers the appropriate Workmanager task for the given rule.
  Future<void> _registerTask(AutomationRule rule) async {
    final taskName = _taskName(rule.id);
    final inputData = <String, dynamic>{'ruleId': rule.id};

    switch (rule.triggerType) {
      case TriggerType.scheduled:
        final delay = rule.scheduledTime!.difference(DateTime.now());
        await Workmanager().registerOneOffTask(
          taskName,
          taskName,
          initialDelay: delay.isNegative ? Duration.zero : delay,
          inputData: inputData,
        );
        break;

      case TriggerType.recurring:
        final frequency = rule.repeatInterval!;
        await Workmanager().registerPeriodicTask(
          taskName,
          taskName,
          frequency: frequency,
          inputData: inputData,
        );
        break;

      case TriggerType.conditionBased:
        await Workmanager().registerPeriodicTask(
          taskName,
          taskName,
          frequency: rule.checkInterval,
          inputData: inputData,
        );
        break;

      case TriggerType.conversationPattern:
      case TriggerType.onClipboardCopy:
      case TriggerType.onNotificationReceived:
        // No background Workmanager tasks needed as these run in response to real-time events.
        break;
    }
  }

  /// Cancels the Workmanager task associated with the given rule ID.
  Future<void> _cancelTask(String ruleId) async {
    await Workmanager().cancelByUniqueName(_taskName(ruleId));
  }

  /// Returns the unique task name for a rule.
  String _taskName(String ruleId) => '$taskPrefix$ruleId';
}
