import 'dart:convert';

/// Enumerates every concrete action a rule can perform.
enum ActionType {
  sendSMS,
  callContact,
  openApp,
  toggleFlashlight,
  webSearch,
  openSettings,
  openCamera,
  aiDigest,
  saveMemory,
  aiTask,
  // Smart App Actions
  sendWhatsApp,
  playSpotify,
  upiPayment,
  bookRide,
  orderFood,
  shareContent,
  openProfile;

  String get label => switch (this) {
    ActionType.sendSMS          => 'Send SMS',
    ActionType.callContact      => 'Call Contact',
    ActionType.openApp          => 'Open App',
    ActionType.toggleFlashlight => 'Flashlight',
    ActionType.webSearch        => 'Web Search',
    ActionType.openSettings     => 'Open Settings',
    ActionType.openCamera       => 'Open Camera',
    ActionType.aiDigest         => 'AI Digest',
    ActionType.saveMemory       => 'Save Memory',
    ActionType.aiTask           => 'AI Task',
    ActionType.sendWhatsApp     => 'Send WhatsApp',
    ActionType.playSpotify      => 'Play on Spotify',
    ActionType.upiPayment       => 'UPI Payment',
    ActionType.bookRide         => 'Book a Ride',
    ActionType.orderFood        => 'Order Food',
    ActionType.shareContent     => 'Share Content',
    ActionType.openProfile      => 'Open Profile',
  };

  String get description => switch (this) {
    ActionType.sendSMS          => 'Send a message to a contact',
    ActionType.callContact      => 'Dial a contact automatically',
    ActionType.openApp          => 'Launch any installed app',
    ActionType.toggleFlashlight => 'Turn flashlight on or off',
    ActionType.webSearch        => 'Search the web automatically',
    ActionType.openSettings     => 'Jump to a device setting',
    ActionType.openCamera       => 'Launch the camera',
    ActionType.aiDigest         => 'Generate a smart notification digest',
    ActionType.saveMemory       => 'Save a note/event to AURA\'s memory',
    ActionType.aiTask           => 'Let AURA decide what to do',
    ActionType.sendWhatsApp     => 'Send a WhatsApp message to a contact',
    ActionType.playSpotify      => 'Play a song, artist, or playlist on Spotify',
    ActionType.upiPayment       => 'Send a UPI payment (GPay, PhonePe, Paytm)',
    ActionType.bookRide         => 'Book a ride on Uber or Ola',
    ActionType.orderFood        => 'Order food from Swiggy or Zomato',
    ActionType.shareContent     => 'Share text to any app',
    ActionType.openProfile      => 'Open a social media profile',
  };

  /// Human-readable summary of what this rule will do, built from [params].
  String buildInstruction(Map<String, dynamic> params) => switch (this) {
    ActionType.sendSMS =>
        'Send SMS to ${params['contact'] ?? ''}: "${params['message'] ?? ''}"',
    ActionType.callContact =>
        'Call ${params['contact'] ?? ''}',
    ActionType.openApp =>
        'Open ${params['appName'] ?? ''}',
    ActionType.toggleFlashlight =>
        params['state'] == true ? 'Turn flashlight ON' : 'Turn flashlight OFF',
    ActionType.webSearch =>
        'Search for "${params['query'] ?? ''}"',
    ActionType.openSettings =>
        'Open ${params['settingsType'] ?? 'general'} settings',
    ActionType.openCamera => 'Open camera',
    ActionType.aiDigest => 'Generate AI summary of recent notifications',
    ActionType.saveMemory => 'Save memory: "${params['memoryText'] ?? ''}"',
    ActionType.aiTask => params['instruction'] as String? ?? '',
    ActionType.sendWhatsApp =>
        'WhatsApp ${params['contact'] ?? ''}: "${params['message'] ?? ''}"',
    ActionType.playSpotify =>
        'Play "${params['query'] ?? ''}" on Spotify',
    ActionType.upiPayment =>
        'Pay ₹${params['amount'] ?? '0'} to ${params['upiId'] ?? ''}${params['note'] != null ? ' (${params['note']})' : ''}',
    ActionType.bookRide =>
        'Book ride to ${params['destination'] ?? ''}${params['app'] != null ? ' via ${params['app']}' : ''}',
    ActionType.orderFood =>
        'Order food${params['restaurant'] != null ? ' from ${params['restaurant']}' : ''}${params['app'] != null ? ' on ${params['app']}' : ''}',
    ActionType.shareContent =>
        'Share "${params['text'] ?? ''}"${params['app'] != null ? ' to ${params['app']}' : ''}',
    ActionType.openProfile =>
        'Open @${params['username'] ?? ''} on ${params['platform'] ?? ''}',
  };

  /// Returns a pre-built tool-call JSON string, or `null` for [aiTask]
  /// (which is parsed by the orchestrator at rule creation time instead).
  String? buildActionJson(Map<String, dynamic> params) {
    switch (this) {
      case ActionType.sendSMS:
        return jsonEncode({'name': 'send_sms', 'arguments': {
          'name': params['contact'] ?? '',
          'message': params['message'] ?? '',
        }});
      case ActionType.callContact:
        return jsonEncode({'name': 'dial_contact', 'arguments': {
          'contactName': params['contact'] ?? '',
        }});
      case ActionType.openApp:
        return jsonEncode({'name': 'open_app', 'arguments': {
          'appName': params['appName'] ?? '',
        }});
      case ActionType.toggleFlashlight:
        return jsonEncode({'name': 'toggle_torch', 'arguments': {
          'state': params['state'] == true ? 'on' : 'off',
        }});
      case ActionType.webSearch:
        return jsonEncode({'name': 'web_search', 'arguments': {
          'query': params['query'] ?? '',
        }});
      case ActionType.openSettings:
        return jsonEncode({'name': 'open_settings', 'arguments': {
          'type': params['settingsType'] ?? 'general',
        }});
      case ActionType.openCamera:
        return jsonEncode({'name': 'open_camera', 'arguments': {}});
      case ActionType.aiDigest:
        return jsonEncode({'name': 'ai_digest', 'arguments': {}});
      case ActionType.saveMemory:
        return jsonEncode({'name': 'save_memory', 'arguments': {
          'content': params['memoryText'] ?? '',
        }});
      case ActionType.aiTask:
        return null; // orchestrator handles parsing
      case ActionType.sendWhatsApp:
        return jsonEncode({'name': 'send_whatsapp', 'arguments': {
          'contact': params['contact'] ?? '',
          'message': params['message'] ?? '',
        }});
      case ActionType.playSpotify:
        return jsonEncode({'name': 'play_spotify', 'arguments': {
          'query': params['query'] ?? '',
        }});
      case ActionType.upiPayment:
        return jsonEncode({'name': 'upi_payment', 'arguments': {
          'upiId': params['upiId'] ?? '',
          'amount': params['amount'] ?? '',
          'note': params['note'] ?? '',
        }});
      case ActionType.bookRide:
        return jsonEncode({'name': 'book_ride', 'arguments': {
          'destination': params['destination'] ?? '',
          'app': params['app'] ?? '',
        }});
      case ActionType.orderFood:
        return jsonEncode({'name': 'order_food', 'arguments': {
          'restaurant': params['restaurant'] ?? '',
          'app': params['app'] ?? '',
        }});
      case ActionType.shareContent:
        return jsonEncode({'name': 'share_content', 'arguments': {
          'text': params['text'] ?? '',
          'app': params['app'] ?? '',
        }});
      case ActionType.openProfile:
        return jsonEncode({'name': 'open_profile', 'arguments': {
          'platform': params['platform'] ?? '',
          'username': params['username'] ?? '',
        }});
    }
  }
}

/// Defines the type of trigger for an automation rule.
enum TriggerType {
  /// Fires once at a specific scheduled time.
  scheduled,

  /// Fires repeatedly at a fixed interval.
  recurring,

  /// Fires when a natural-language condition is evaluated as met.
  conditionBased,

  /// Fires when a keyword/phrase is matched in user conversation.
  conversationPattern,

  /// Fires when text is copied to clipboard.
  onClipboardCopy,

  /// Fires when any app receives a notification.
  onNotificationReceived,
}

/// Represents a single step in a multi-step agentic workflow.
class WorkflowStep {
  final String id;
  final String type; // readClipboard, readScreen, readNotifications, webSearch, aiGenerate, saveMemory, speakText, etc.
  final Map<String, dynamic> params;

  const WorkflowStep({
    required this.id,
    required this.type,
    required this.params,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'params': params,
      };

  factory WorkflowStep.fromMap(Map<String, dynamic> map) {
    return WorkflowStep(
      id: map['id'] as String? ?? '',
      type: map['type'] as String? ?? '',
      params: Map<String, dynamic>.from(map['params'] as Map? ?? {}),
    );
  }
}

/// Represents an automation rule that executes an action based on a trigger.
class AutomationRule {
  final String id;
  final String name;
  final TriggerType triggerType;
  final DateTime? scheduledTime;
  final Duration? repeatInterval;
  final String? condition;
  final Duration checkInterval;
  final String actionInstruction;
  final String? actionJson;
  final bool isEnabled;
  final DateTime? lastExecutedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AutomationRule({
    required this.id,
    required this.name,
    required this.triggerType,
    this.scheduledTime,
    this.repeatInterval,
    this.condition,
    this.checkInterval = const Duration(hours: 1),
    required this.actionInstruction,
    this.actionJson,
    this.isEnabled = true,
    this.lastExecutedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns whether this rule represents a multi-step workflow.
  bool get isWorkflow {
    if (actionJson == null || actionJson!.isEmpty) return false;
    try {
      final data = jsonDecode(actionJson!);
      return data is Map && data['isWorkflow'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Returns parsed steps if this rule is a workflow.
  List<WorkflowStep> get workflowSteps {
    if (actionJson == null || actionJson!.isEmpty) return [];
    try {
      final data = jsonDecode(actionJson!);
      if (data is Map && data['isWorkflow'] == true) {
        final stepsRaw = data['steps'] as List? ?? [];
        return stepsRaw
            .map((s) => WorkflowStep.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Returns a human-readable description of the trigger configuration.
  String get triggerDescription {
    switch (triggerType) {
      case TriggerType.scheduled:
        if (scheduledTime == null) return 'Scheduled (no time set)';
        final hour = scheduledTime!.hour.toString().padLeft(2, '0');
        final minute = scheduledTime!.minute.toString().padLeft(2, '0');
        return 'Every day at $hour:$minute';
      case TriggerType.recurring:
        if (repeatInterval == null) return 'Recurring (no interval set)';
        final totalMinutes = repeatInterval!.inMinutes;
        if (totalMinutes < 60) {
          return 'Every $totalMinutes minutes';
        }
        final hours = repeatInterval!.inHours;
        final remainingMinutes = totalMinutes % 60;
        if (remainingMinutes == 0) {
          return hours == 1 ? 'Every hour' : 'Every $hours hours';
        }
        return 'Every $hours hours and $remainingMinutes minutes';
      case TriggerType.conditionBased:
        if (condition == null || condition!.isEmpty) {
          return 'Condition-based (no condition set)';
        }
        return 'When: $condition';
      case TriggerType.conversationPattern:
        if (condition == null || condition!.isEmpty) {
          return 'On chat mention';
        }
        return 'On chat keyword: "$condition"';
      case TriggerType.onClipboardCopy:
        if (condition == null || condition!.isEmpty) {
          return 'When copying any text';
        }
        return 'When copying text matching: "$condition"';
      case TriggerType.onNotificationReceived:
        if (condition == null || condition!.isEmpty) {
          return 'On any notification';
        }
        return 'On notification from: $condition';
    }
  }

  /// Creates a copy of this rule with the given fields replaced.
  AutomationRule copyWith({
    String? id,
    String? name,
    TriggerType? triggerType,
    DateTime? scheduledTime,
    Duration? repeatInterval,
    String? condition,
    Duration? checkInterval,
    String? actionInstruction,
    String? actionJson,
    bool? isEnabled,
    DateTime? lastExecutedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AutomationRule(
      id: id ?? this.id,
      name: name ?? this.name,
      triggerType: triggerType ?? this.triggerType,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      repeatInterval: repeatInterval ?? this.repeatInterval,
      condition: condition ?? this.condition,
      checkInterval: checkInterval ?? this.checkInterval,
      actionInstruction: actionInstruction ?? this.actionInstruction,
      actionJson: actionJson ?? this.actionJson,
      isEnabled: isEnabled ?? this.isEnabled,
      lastExecutedAt: lastExecutedAt ?? this.lastExecutedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Represents a validation error for a specific field.
class ValidationError {
  final String field;
  final String message;

  const ValidationError({
    required this.field,
    required this.message,
  });

  @override
  String toString() => 'ValidationError(field: $field, message: $message)';
}
