import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/features/automation/application/automation_engine.dart';
import 'package:aura_mobile/features/automation/domain/automation_rule.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';
import 'package:uuid/uuid.dart';

const _kSettingsTypes = <String>[
  'general', 'wifi', 'bluetooth', 'battery', 'display',
  'sound', 'apps', 'location', 'privacy', 'accessibility',
];

class AutomationRuleFormScreen extends ConsumerStatefulWidget {
  final AutomationRule? existingRule;

  const AutomationRuleFormScreen({super.key, this.existingRule});

  @override
  ConsumerState<AutomationRuleFormScreen> createState() =>
      _AutomationRuleFormScreenState();
}

class _AutomationRuleFormScreenState
    extends ConsumerState<AutomationRuleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _conditionController;

  // Trigger state
  TriggerType _triggerType = TriggerType.recurring;
  DateTime? _scheduledTime;
  Duration _selectedInterval = const Duration(hours: 1);
  Duration _checkInterval    = const Duration(hours: 1);

  // Workflow steps state
  List<WorkflowStep> _steps = [];

  // Controllers cache for step fields to prevent text loss on state rebuilds
  final Map<String, TextEditingController> _stepControllers = {};

  bool _isSaving = false;
  Map<String, String> _fieldErrors = {};

  static final _intervalOptions = <Duration, String>{
    const Duration(minutes: 15): '15 min',
    const Duration(minutes: 30): '30 min',
    const Duration(hours: 1)  : '1 hour',
    const Duration(hours: 2)  : '2 hours',
    const Duration(hours: 6)  : '6 hours',
    const Duration(hours: 12) : '12 hours',
    const Duration(hours: 24) : '24 hours',
  };

  bool get _isEditing => widget.existingRule != null;

  @override
  void initState() {
    super.initState();
    final rule = widget.existingRule;

    _nameController = TextEditingController(text: rule?.name ?? '');
    _conditionController = TextEditingController(text: rule?.condition ?? '');

    if (rule != null) {
      _triggerType      = rule.triggerType;
      _scheduledTime    = rule.scheduledTime;
      _selectedInterval = rule.repeatInterval ?? const Duration(hours: 1);
      _checkInterval    = rule.checkInterval;

      if (rule.isWorkflow) {
        _steps = rule.workflowSteps.map(_normalizeStep).toList();
      } else {
        // Build single step from legacy action
        final jsonStr = rule.actionJson ?? '';
        final type = jsonStr.isNotEmpty ? (jsonDecode(jsonStr)['name'] as String? ?? 'aiTask') : 'aiTask';
        final params = jsonStr.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(jsonStr)['arguments'] as Map? ?? {}) : <String, dynamic>{};
        
        final legacyStep = WorkflowStep(
          id: 'step_1',
          type: type,
          params: params,
        );
        _steps = [_normalizeStep(legacyStep)];
      }
    } else {
      // Start with one step to help user get started
      _steps = [
        const WorkflowStep(
          id: 'step_1',
          type: 'readClipboard',
          params: {},
        )
      ];
    }
  }

  WorkflowStep _normalizeStep(WorkflowStep step) {
    switch (step.type) {
      case 'send_sms':
        final contact = step.params['name'] ?? step.params['contact'] ?? '';
        final msg = step.params['message'] ?? '';
        return WorkflowStep(
          id: step.id,
          type: 'sendSMS',
          params: {'contact': contact, 'message': msg},
        );
      case 'toggle_torch':
        final stateVal = step.params['state'];
        final state = stateVal == true || stateVal?.toString().toLowerCase() == 'on';
        return WorkflowStep(
          id: step.id,
          type: 'toggleFlashlight',
          params: {'state': state},
        );
      case 'web_search':
        return WorkflowStep(
          id: step.id,
          type: 'webSearch',
          params: {'query': step.params['query'] ?? ''},
        );
      case 'save_memory':
        return WorkflowStep(
          id: step.id,
          type: 'saveMemory',
          params: {'content': step.params['content'] ?? step.params['memoryText'] ?? ''},
        );
      case 'open_app':
        return WorkflowStep(
          id: step.id,
          type: 'openApp',
          params: {'appName': step.params['appName'] ?? ''},
        );
      default:
        return step;
      }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _conditionController.dispose();
    for (final controller in _stepControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _getControllerForStep(String stepId, String paramName, String initialValue) {
    final key = '${stepId}_$paramName';
    if (!_stepControllers.containsKey(key)) {
      _stepControllers[key] = TextEditingController(text: initialValue);
      // Auto-update parameters in the state
      _stepControllers[key]!.addListener(() {
        final idx = _steps.indexWhere((s) => s.id == stepId);
        if (idx >= 0) {
          final oldStep = _steps[idx];
          final newParams = Map<String, dynamic>.from(oldStep.params);
          newParams[paramName] = _stepControllers[key]!.text;
          _steps[idx] = WorkflowStep(id: oldStep.id, type: oldStep.type, params: newParams);
        }
      });
    }
    return _stepControllers[key]!;
  }

  void _moveStepUp(int index) {
    if (index == 0) return;
    setState(() {
      final step = _steps.removeAt(index);
      _steps.insert(index - 1, step);
      _updateStepIds();
    });
  }

  void _moveStepDown(int index) {
    if (index == _steps.length - 1) return;
    setState(() {
      final step = _steps.removeAt(index);
      _steps.insert(index + 1, step);
      _updateStepIds();
    });
  }

  void _deleteStep(int index) {
    setState(() {
      _steps.removeAt(index);
      _updateStepIds();
    });
  }

  void _updateStepIds() {
    for (int i = 0; i < _steps.length; i++) {
      final oldStep = _steps[i];
      final newId = 'step_${i + 1}';
      
      // Migrate controller keys to preserve input focus & value
      final oldKeyPrefix = '${oldStep.id}_';
      final newKeyPrefix = '${newId}_';
      final keysToMigrate = _stepControllers.keys.where((k) => k.startsWith(oldKeyPrefix)).toList();
      for (final oldKey in keysToMigrate) {
        final paramName = oldKey.substring(oldKeyPrefix.length);
        final newKey = '$newKeyPrefix$paramName';
        if (oldKey != newKey) {
          _stepControllers[newKey] = _stepControllers.remove(oldKey)!;
        }
      }

      _steps[i] = WorkflowStep(id: newId, type: oldStep.type, params: oldStep.params);
    }
  }

  String _stepTypeLabel(String type) => switch (type) {
    'readClipboard' => 'Clipboard Reader',
    'readScreen' => 'OCR Screen Text',
    'readNotifications' => 'Notifications Reader',
    'webSearch' => 'Web Search',
    'aiGenerate' => 'AI Generator',
    'saveMemory' => 'Save Memory',
    'speakText' => 'Speak Text (TTS)',
    'showNotification' => 'Push Notification',
    'toggleFlashlight' => 'Toggle Flashlight',
    'openApp' => 'Open App',
    'sendSMS' => 'Send SMS',
    'dial_contact' => 'Call Contact',
    'open_settings' => 'Open Settings',
    'open_camera' => 'Open Camera',
    'ai_digest' => 'AI Notif Digest',
    'send_whatsapp' => 'Send WhatsApp',
    'play_spotify' => 'Play Spotify',
    'upi_payment' => 'UPI Payment',
    'book_ride' => 'Book Ride',
    'order_food' => 'Order Food',
    'share_content' => 'Share Content',
    'open_profile' => 'Open Profile',
    _ => type,
  };

  IconData _stepTypeIcon(String type) => switch (type) {
    'readClipboard' => Icons.assignment_returned_rounded,
    'readScreen' => Icons.screenshot_rounded,
    'readNotifications' => Icons.notifications_active_rounded,
    'webSearch' => Icons.travel_explore_rounded,
    'aiGenerate' => Icons.auto_awesome_rounded,
    'saveMemory' => Icons.save_rounded,
    'speakText' => Icons.volume_up_rounded,
    'showNotification' => Icons.chat_bubble_rounded,
    'toggleFlashlight' => Icons.flashlight_on_rounded,
    'openApp' => Icons.apps_rounded,
    'sendSMS' => Icons.sms_rounded,
    'dial_contact' => Icons.call_rounded,
    'open_settings' => Icons.tune_rounded,
    'open_camera' => Icons.camera_alt_rounded,
    'ai_digest' => Icons.auto_awesome_rounded,
    'send_whatsapp' => Icons.chat_rounded,
    'play_spotify' => Icons.music_note_rounded,
    'upi_payment' => Icons.currency_rupee_rounded,
    'book_ride' => Icons.local_taxi_rounded,
    'order_food' => Icons.restaurant_rounded,
    'share_content' => Icons.share_rounded,
    'open_profile' => Icons.person_rounded,
    _ => Icons.circle_outlined,
  };

  Color _stepTypeColor(String type) => switch (type) {
    'readClipboard' => const Color(0xFF34C759),
    'readScreen' => const Color(0xFF30B0E8),
    'readNotifications' => const Color(0xFFAF52DE),
    'webSearch' => const Color(0xFF32D4C8),
    'aiGenerate' => const Color(0xFFC8A96A),
    'saveMemory' => const Color(0xFFE08244),
    'speakText' => const Color(0xFFE54B64),
    'showNotification' => const Color(0xFF4C8DF5),
    'toggleFlashlight' => const Color(0xFFFFCC00),
    'openApp' => const Color(0xFF8E8E93),
    'sendSMS' => const Color(0xFF00C7B1),
    'dial_contact' => const Color(0xFF30B0E8),
    'open_settings' => const Color(0xFF8E8E93),
    'open_camera' => const Color(0xFFFF6B81),
    'ai_digest' => const Color(0xFFC8A96A),
    'send_whatsapp' => const Color(0xFF25D366),
    'play_spotify' => const Color(0xFF1DB954),
    'upi_payment' => const Color(0xFF5F259F),
    'book_ride' => const Color(0xFF000000),
    'order_food' => const Color(0xFFE23744),
    'share_content' => const Color(0xFF4285F4),
    'open_profile' => const Color(0xFFE1306C),
    _ => const Color(0xFFBC4B2E),
  };

  Future<void> _save() async {
    setState(() => _fieldErrors = {});
    if (!_formKey.currentState!.validate()) return;

    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one step in the workflow.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();

      // Read current values from controllers into step parameters
      for (int i = 0; i < _steps.length; i++) {
        final step = _steps[i];
        final newParams = Map<String, dynamic>.from(step.params);

        if (step.type == 'webSearch') {
          newParams['query'] = _stepControllers['${step.id}_query']?.text ?? '';
        } else if (step.type == 'aiGenerate') {
          newParams['prompt'] = _stepControllers['${step.id}_prompt']?.text ?? '';
        } else if (step.type == 'saveMemory') {
          newParams['content'] = _stepControllers['${step.id}_content']?.text ?? '';
        } else if (step.type == 'speakText') {
          newParams['text'] = _stepControllers['${step.id}_text']?.text ?? '';
        } else if (step.type == 'showNotification') {
          newParams['title'] = _stepControllers['${step.id}_title']?.text ?? '';
          newParams['body'] = _stepControllers['${step.id}_body']?.text ?? '';
        } else if (step.type == 'openApp') {
          newParams['appName'] = _stepControllers['${step.id}_appName']?.text ?? '';
        } else if (step.type == 'sendSMS') {
          newParams['contact'] = _stepControllers['${step.id}_contact']?.text ?? '';
          newParams['message'] = _stepControllers['${step.id}_message']?.text ?? '';
        } else if (step.type == 'dial_contact') {
          newParams['contactName'] = _stepControllers['${step.id}_contactName']?.text ?? '';
        } else if (step.type == 'send_whatsapp') {
          newParams['contact'] = _stepControllers['${step.id}_contact']?.text ?? '';
          newParams['message'] = _stepControllers['${step.id}_message']?.text ?? '';
        } else if (step.type == 'play_spotify') {
          newParams['query'] = _stepControllers['${step.id}_query']?.text ?? '';
        } else if (step.type == 'upi_payment') {
          newParams['upiId'] = _stepControllers['${step.id}_upiId']?.text ?? '';
          newParams['amount'] = _stepControllers['${step.id}_amount']?.text ?? '';
          newParams['note'] = _stepControllers['${step.id}_note']?.text ?? '';
        } else if (step.type == 'book_ride') {
          newParams['destination'] = _stepControllers['${step.id}_destination']?.text ?? '';
          newParams['app'] = _stepControllers['${step.id}_app']?.text ?? '';
        } else if (step.type == 'order_food') {
          newParams['restaurant'] = _stepControllers['${step.id}_restaurant']?.text ?? '';
          newParams['app'] = _stepControllers['${step.id}_app']?.text ?? '';
        } else if (step.type == 'share_content') {
          newParams['text'] = _stepControllers['${step.id}_text']?.text ?? '';
          newParams['app'] = _stepControllers['${step.id}_app']?.text ?? '';
        } else if (step.type == 'open_profile') {
          newParams['platform'] = _stepControllers['${step.id}_platform']?.text ?? '';
          newParams['username'] = _stepControllers['${step.id}_username']?.text ?? '';
        }

        _steps[i] = WorkflowStep(id: step.id, type: step.type, params: newParams);
      }

      final String actionJson = jsonEncode({
        'isWorkflow': true,
        'steps': _steps.map((s) => s.toMap()).toList(),
      });

      final String actionInstruction = 'Workflow: ' + _steps.map((s) => _stepTypeLabel(s.type)).join(' ➔ ');

      final rule = AutomationRule(
        id                : widget.existingRule?.id ?? const Uuid().v4(),
        name              : _nameController.text.trim(),
        triggerType       : _triggerType,
        scheduledTime     : _triggerType == TriggerType.scheduled ? _scheduledTime : null,
        repeatInterval    : _triggerType == TriggerType.recurring  ? _selectedInterval : null,
        condition         : _triggerType == TriggerType.scheduled ? null : _conditionController.text.trim(),
        checkInterval     : _triggerType == TriggerType.conditionBased ? _checkInterval : const Duration(hours: 1),
        actionInstruction : actionInstruction,
        actionJson        : actionJson,
        isEnabled         : widget.existingRule?.isEnabled ?? true,
        lastExecutedAt    : widget.existingRule?.lastExecutedAt,
        createdAt         : widget.existingRule?.createdAt ?? now,
        updatedAt         : now,
      );

      final ruleErrors = AutomationEngine.validateRule(rule);
      if (ruleErrors.isNotEmpty) {
        setState(() {
          for (final e in ruleErrors) {
            _fieldErrors[e.field] = e.message;
          }
        });
        return;
      }

      final engine = ref.read(automationEngineProvider);
      if (_isEditing) {
        await engine.updateRule(rule);
      } else {
        await engine.createRule(rule);
      }
      if (mounted) Navigator.of(context).pop();
    } on AutomationValidationException catch (e) {
      setState(() {
        for (final err in e.errors) {
          _fieldErrors[err.field] = err.message;
        }
      });
    } on AutomationLimitException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickDateTime() async {
    final now  = DateTime.now();
    final date = await showDatePicker(
      context     : context,
      initialDate : _scheduledTime ?? now,
      firstDate   : now,
      lastDate    : now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: ClayColors.goldAccent, onPrimary: Colors.white,
            onSurface: ClayColors.textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context     : context,
      initialTime : TimeOfDay.fromDateTime(_scheduledTime ?? now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: ClayColors.goldAccent, onPrimary: Colors.white,
            onSurface: ClayColors.textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _fieldErrors.remove('scheduledTime');
    });
  }

  Widget _clayField({
    required TextEditingController controller,
    required String hint,
    String? label,
    int maxLines  = 1,
    int? maxLength,
    String? error,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label, style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold, fontSize: 13, color: ClayColors.textDark)),
          const SizedBox(height: 6),
        ],
        ClayContainer(
          borderRadius: 14,
          isInset: true,
          depth: 4.0,
          baseColor      : const Color(0xFFE5E2DA),
          highlightColor : const Color(0xFFF7F4EF),
          shadowColor    : const Color(0xFFCBC7BE),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller  : controller,
                  maxLines    : maxLines,
                  maxLength   : maxLength,
                  keyboardType: keyboardType,
                  validator   : validator,
                  style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 14, fontWeight: FontWeight.w600),
                  buildCounter: maxLength != null
                      ? (context, {required currentLength, required isFocused, maxLength}) => null
                      : null,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: GoogleFonts.outfit(color: ClayColors.textHint, fontSize: 14),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 4),
            child: Text(error, style: GoogleFonts.outfit(
              color: ClayColors.redAccent, fontSize: 11, fontWeight: FontWeight.w500)),
          ),
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(icon, size: 16, color: ClayColors.goldAccent),
        const SizedBox(width: 8),
        Text(title, style: GoogleFonts.outfit(
          fontWeight: FontWeight.bold, fontSize: 13,
          color: ClayColors.goldAccent, letterSpacing: 0.5)),
      ]),
    );
  }

  Widget _buildTriggerGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('WHEN TO RUN (TRIGGER)', Icons.bolt_rounded),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: TriggerType.values.map((type) {
            final isSelected = _triggerType == type;
            final (icon, label) = switch (type) {
              TriggerType.scheduled => (Icons.alarm_rounded, 'Once (Time)'),
              TriggerType.recurring => (Icons.loop_rounded, 'Recurring'),
              TriggerType.conditionBased => (Icons.rule_rounded, 'Condition'),
              TriggerType.conversationPattern => (Icons.chat_bubble_outline_rounded, 'Chat Pattern'),
              TriggerType.onClipboardCopy => (Icons.copy_rounded, 'Clipboard Copy'),
              TriggerType.onNotificationReceived => (Icons.notifications_active_rounded, 'Notification'),
            };
            return GestureDetector(
              onTap: () => setState(() {
                _triggerType = type;
                _fieldErrors.clear();
              }),
              child: ClayContainer(
                width: (MediaQuery.of(context).size.width - 48) / 2,
                borderRadius: 14,
                isInset: isSelected,
                depth: 4.0,
                baseColor: isSelected ? ClayColors.goldHighlight : const Color(0xFFE5E2DA),
                highlightColor: const Color(0xFFF7F4EF),
                shadowColor: const Color(0xFFCBC7BE),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: isSelected ? ClayColors.goldAccent : ClayColors.textMuted),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? ClayColors.goldAccent : ClayColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTriggerConfig() {
    switch (_triggerType) {
      case TriggerType.scheduled:
        return _buildDatePickerButton();
      case TriggerType.recurring:
        return _buildIntervalDropdown(
          label: 'Repeat Interval', value: _selectedInterval,
          error: _fieldErrors['repeatInterval'],
          onChanged: (v) { if (v != null) setState(() => _selectedInterval = v); },
        );
      case TriggerType.conditionBased:
        return Column(children: [
          _clayField(
            controller: _conditionController,
            hint : 'e.g., Battery level below 20%',
            label: 'On-Device Condition description',
            error: _fieldErrors['condition'],
          ),
          const SizedBox(height: 12),
          _buildIntervalDropdown(
            label: 'Check interval', value: _checkInterval,
            error: _fieldErrors['checkInterval'],
            onChanged: (v) { if (v != null) setState(() => _checkInterval = v); },
          ),
        ]);
      case TriggerType.conversationPattern:
        return _clayField(
          controller: _conditionController,
          hint: 'e.g., summary, check-out, weather',
          label: 'Conversation Trigger Keyword / Phrase',
          error: _fieldErrors['condition'],
        );
      case TriggerType.onClipboardCopy:
        return _clayField(
          controller: _conditionController,
          hint: 'e.g., http (leave empty to trigger on any text copy)',
          label: 'Clipboard Text Filter (Optional)',
          error: _fieldErrors['condition'],
        );
      case TriggerType.onNotificationReceived:
        return _clayField(
          controller: _conditionController,
          hint: 'e.g., WhatsApp (leave empty to trigger on any notification)',
          label: 'App Name / Content Filter (Optional)',
          error: _fieldErrors['condition'],
        );
    }
  }

  Widget _buildDatePickerButton() {
    final hasTime = _scheduledTime != null;
    final label = hasTime
        ? '${_scheduledTime!.day}/${_scheduledTime!.month}/${_scheduledTime!.year}'
          ' ${_scheduledTime!.hour.toString().padLeft(2, '0')}:'
          '${_scheduledTime!.minute.toString().padLeft(2, '0')}'
        : 'Pick Date & Time';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Scheduled Time', style: GoogleFonts.outfit(
        fontWeight: FontWeight.bold, fontSize: 13, color: ClayColors.textDark)),
      const SizedBox(height: 6),
      ClayButton(
        onTap: _pickDateTime,
        borderRadius: 14,
        baseColor: ClayColors.warmGrey,
        highlightColor: ClayColors.highlight,
        shadowColor: ClayColors.shadow,
        depth: 5.0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          const Icon(Icons.calendar_today_rounded, color: ClayColors.goldAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: GoogleFonts.outfit(
            color: hasTime ? ClayColors.textDark : ClayColors.textHint,
            fontWeight: FontWeight.w600, fontSize: 14))),
          const Icon(Icons.arrow_drop_down_rounded, color: ClayColors.textHint),
        ]),
      ),
      if (_fieldErrors.containsKey('scheduledTime'))
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 4),
          child: Text(_fieldErrors['scheduledTime']!, style: GoogleFonts.outfit(
            color: ClayColors.redAccent, fontSize: 11)),
        ),
    ]);
  }

  Widget _buildIntervalDropdown({
    required String label,
    required Duration value,
    required ValueChanged<Duration?> onChanged,
    String? error,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.outfit(
        fontWeight: FontWeight.bold, fontSize: 13, color: ClayColors.textDark)),
      const SizedBox(height: 6),
      ClayContainer(
        borderRadius: 14, isInset: true, depth: 4.0,
        baseColor: const Color(0xFFE5E2DA),
        highlightColor: const Color(0xFFF7F4EF),
        shadowColor: const Color(0xFFCBC7BE),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Duration>(
            value: value, isExpanded: true,
            icon: const Icon(Icons.arrow_drop_down_rounded, color: ClayColors.textHint),
            style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 14, fontWeight: FontWeight.w600),
            dropdownColor: ClayColors.warmGrey,
            items: _intervalOptions.entries.map((e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, style: GoogleFonts.outfit(
                color: ClayColors.textDark, fontWeight: FontWeight.w600)),
            )).toList(),
            onChanged: onChanged,
          ),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 4),
          child: Text(error, style: GoogleFonts.outfit(
            color: ClayColors.redAccent, fontSize: 11)),
        ),
    ]);
  }

  List<String> _getPlaceholdersForStep(int index) {
    final list = ['{clipboard}', '{notification_text}', '{notification_app}'];
    for (int i = 0; i < index; i++) {
      list.add('{step_${i + 1}}');
    }
    return list;
  }

  Widget _buildPlaceholderChips(TextEditingController controller, List<String> placeholders) {
    if (placeholders.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tap variable to insert:', style: GoogleFonts.outfit(fontSize: 10, color: ClayColors.textHint)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: placeholders.map((placeholder) {
              return GestureDetector(
                onTap: () {
                  final text = controller.text;
                  final selection = controller.selection;
                  final insertion = placeholder;
                  
                  if (selection.isValid) {
                    final start = selection.start;
                    final end = selection.end;
                    controller.text = text.replaceRange(start, end, insertion);
                    controller.selection = TextSelection.collapsed(offset: start + insertion.length);
                  } else {
                    controller.text = text + insertion;
                    controller.selection = TextSelection.collapsed(offset: controller.text.length);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: ClayColors.goldAccent.withOpacity(0.08),
                    border: Border.all(color: ClayColors.goldAccent.withOpacity(0.15)),
                  ),
                  child: Text(
                    placeholder,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: ClayColors.goldAccent,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowBuilder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionHeader('WORKFLOW STEPS SEQUENCE', Icons.list_alt_rounded),
            GestureDetector(
              onTap: _showAddStepSheet,
              child: Row(
                children: [
                  const Icon(Icons.add_circle_outline_rounded, size: 14, color: ClayColors.goldAccent),
                  const SizedBox(width: 4),
                  Text('Add Step', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: ClayColors.goldAccent)),
                ],
              ),
            ),
          ],
        ),
        if (_steps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No steps defined. Add a step to build your workflow.',
                style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 13),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _steps.length,
            itemBuilder: (context, index) {
              final step = _steps[index];
              return _buildStepCard(step, index);
            },
          ),
      ],
    );
  }

  Widget _buildStepCard(WorkflowStep step, int index) {
    final color = _stepTypeColor(step.type);
    final icon = _stepTypeIcon(step.type);
    final isFirst = index == 0;
    final isLast = index == _steps.length - 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClayContainer(
        borderRadius: 18,
        baseColor: ClayColors.warmGrey,
        highlightColor: ClayColors.highlight,
        shadowColor: ClayColors.shadow,
        depth: 5.0,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Circular Step Index Badge
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _stepTypeLabel(step.type),
                    style: GoogleFonts.outfit(
                      color: ClayColors.textDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '{${step.id}}',
                  style: GoogleFonts.outfit(color: ClayColors.textHint, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                // Reorder / Delete Actions
                if (!isFirst)
                  GestureDetector(
                    onTap: () => _moveStepUp(index),
                    child: const Icon(Icons.arrow_upward_rounded, size: 16, color: ClayColors.textHint),
                  ),
                if (!isFirst && !isLast) const SizedBox(width: 6),
                if (!isLast)
                  GestureDetector(
                    onTap: () => _moveStepDown(index),
                    child: const Icon(Icons.arrow_downward_rounded, size: 16, color: ClayColors.textHint),
                  ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _deleteStep(index),
                  child: const Icon(Icons.delete_outline_rounded, size: 18, color: ClayColors.redAccent),
                ),
              ],
            ),
            const Divider(height: 20, color: Color(0xFFD6CDBB)),
            _buildStepFormFields(step, index),
          ],
        ),
      ),
    );
  }

  Widget _buildStepFormFields(WorkflowStep step, int index) {
    final placeholders = _getPlaceholdersForStep(index);

    switch (step.type) {
      case 'readClipboard':
        return Text(
          'Gets the current plain text copied to the clipboard. The output is saved in variable {${step.id}}.',
          style: GoogleFonts.outfit(fontSize: 12, color: ClayColors.textMuted, height: 1.4),
        );
      case 'readScreen':
        return Text(
          'OCR analyzes text directly from the screen context. The output is saved in variable {${step.id}}.',
          style: GoogleFonts.outfit(fontSize: 12, color: ClayColors.textMuted, height: 1.4),
        );
      case 'readNotifications':
        return Text(
          'Reads all recent notifications from the past hour. The output is saved in variable {${step.id}}.',
          style: GoogleFonts.outfit(fontSize: 12, color: ClayColors.textMuted, height: 1.4),
        );
      case 'webSearch':
        final ctrl = _getControllerForStep(step.id, 'query', step.params['query'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(
              controller: ctrl,
              hint: 'e.g., weather forecast in {clipboard}',
              label: 'Search Query',
            ),
            _buildPlaceholderChips(ctrl, placeholders),
          ],
        );
      case 'aiGenerate':
        final ctrl = _getControllerForStep(step.id, 'prompt', step.params['prompt'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(
              controller: ctrl,
              hint: 'e.g., Synthesize the news: {step_1}',
              label: 'AI Prompt / Instruction',
              maxLines: 4,
              maxLength: 500,
            ),
            _buildPlaceholderChips(ctrl, placeholders),
          ],
        );
      case 'saveMemory':
        final ctrl = _getControllerForStep(step.id, 'content', step.params['content'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(
              controller: ctrl,
              hint: 'e.g., {step_2} was scheduled',
              label: 'Content to save',
            ),
            _buildPlaceholderChips(ctrl, placeholders),
          ],
        );
      case 'speakText':
        final ctrl = _getControllerForStep(step.id, 'text', step.params['text'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(
              controller: ctrl,
              hint: 'e.g., AURA digested: {step_1}',
              label: 'Text to speak',
            ),
            _buildPlaceholderChips(ctrl, placeholders),
          ],
        );
      case 'showNotification':
        final titleCtrl = _getControllerForStep(step.id, 'title', step.params['title'] ?? '');
        final bodyCtrl = _getControllerForStep(step.id, 'body', step.params['body'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(
              controller: titleCtrl,
              hint: 'e.g., AURA Digest',
              label: 'Notification Title',
            ),
            const SizedBox(height: 10),
            _clayField(
              controller: bodyCtrl,
              hint: 'e.g., Output: {step_2}',
              label: 'Notification Body',
              maxLines: 2,
            ),
            _buildPlaceholderChips(bodyCtrl, placeholders),
          ],
        );
      case 'toggleFlashlight':
        final isSelected = step.params['state'] == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Flashlight State', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: ClayColors.textDark)),
            const SizedBox(height: 8),
            ClayContainer(
              borderRadius: 14, isInset: true, depth: 3.0,
              baseColor: const Color(0xFFE5E2DA),
              highlightColor: const Color(0xFFF7F4EF),
              shadowColor: const Color(0xFFCBC7BE),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          final newParams = Map<String, dynamic>.from(step.params);
                          newParams['state'] = true;
                          _steps[index] = WorkflowStep(id: step.id, type: step.type, params: newParams);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: isSelected ? const Color(0xFFFFCC00) : Colors.transparent,
                        ),
                        child: Center(
                          child: Text('ON', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? Colors.white : ClayColors.textMuted)),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          final newParams = Map<String, dynamic>.from(step.params);
                          newParams['state'] = false;
                          _steps[index] = WorkflowStep(id: step.id, type: step.type, params: newParams);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: !isSelected ? ClayColors.textHint : Colors.transparent,
                        ),
                        child: Center(
                          child: Text('OFF', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: !isSelected ? Colors.white : ClayColors.textMuted)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case 'openApp':
        final ctrl = _getControllerForStep(step.id, 'appName', step.params['appName'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(
              controller: ctrl,
              hint: 'e.g., Spotify',
              label: 'App Name',
            ),
            _buildPlaceholderChips(ctrl, placeholders),
          ],
        );
      case 'sendSMS':
        final contactCtrl = _getControllerForStep(step.id, 'contact', step.params['contact'] ?? '');
        final msgCtrl = _getControllerForStep(step.id, 'message', step.params['message'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(
              controller: contactCtrl,
              hint: 'e.g., Mom or +12345678',
              label: 'Contact Name / Number',
            ),
            const SizedBox(height: 10),
            _clayField(
              controller: msgCtrl,
              hint: 'e.g., Weather update: {step_1}',
              label: 'Message',
              maxLines: 2,
            ),
            _buildPlaceholderChips(msgCtrl, placeholders),
          ],
        );
      case 'dial_contact':
        final ctrl = _getControllerForStep(step.id, 'contactName', step.params['contactName'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(
              controller: ctrl,
              hint: 'e.g., Dad',
              label: 'Contact Name',
            ),
            _buildPlaceholderChips(ctrl, placeholders),
          ],
        );
      case 'open_settings':
        final selectedType = step.params['type'] ?? 'general';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings Category', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: ClayColors.textDark)),
            const SizedBox(height: 8),
            ClayContainer(
              borderRadius: 14, isInset: true, depth: 4.0,
              baseColor: const Color(0xFFE5E2DA),
              highlightColor: const Color(0xFFF7F4EF),
              shadowColor: const Color(0xFFCBC7BE),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedType,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down_rounded, color: ClayColors.textHint),
                  style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 14, fontWeight: FontWeight.w600),
                  dropdownColor: ClayColors.warmGrey,
                  items: _kSettingsTypes.map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t[0].toUpperCase() + t.substring(1),
                      style: GoogleFonts.outfit(color: ClayColors.textDark, fontWeight: FontWeight.w600)),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        final newParams = Map<String, dynamic>.from(step.params);
                        newParams['type'] = v;
                        _steps[index] = WorkflowStep(id: step.id, type: step.type, params: newParams);
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        );
      case 'open_camera':
        return Text(
          'Launches the device camera interface.',
          style: GoogleFonts.outfit(fontSize: 12, color: ClayColors.textMuted, height: 1.4),
        );
      case 'ai_digest':
        return Text(
          'Generates a comprehensive summary of recent system notifications using local AI.',
          style: GoogleFonts.outfit(fontSize: 12, color: ClayColors.textMuted, height: 1.4),
        );
      case 'send_whatsapp':
        final contactCtrl = _getControllerForStep(step.id, 'contact', step.params['contact'] ?? '');
        final msgCtrl = _getControllerForStep(step.id, 'message', step.params['message'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(controller: contactCtrl, hint: 'e.g., Mom or +919876543210', label: 'Contact Name / Number'),
            const SizedBox(height: 10),
            _clayField(controller: msgCtrl, hint: 'e.g., Hey! {step_1}', label: 'Message', maxLines: 2),
            _buildPlaceholderChips(msgCtrl, placeholders),
          ],
        );
      case 'play_spotify':
        final ctrl = _getControllerForStep(step.id, 'query', step.params['query'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(controller: ctrl, hint: 'e.g., Chill Vibes playlist', label: 'Song / Artist / Playlist'),
            _buildPlaceholderChips(ctrl, placeholders),
          ],
        );
      case 'upi_payment':
        final upiCtrl = _getControllerForStep(step.id, 'upiId', step.params['upiId'] ?? '');
        final amountCtrl = _getControllerForStep(step.id, 'amount', step.params['amount'] ?? '');
        final noteCtrl = _getControllerForStep(step.id, 'note', step.params['note'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(controller: upiCtrl, hint: 'e.g., name@upi', label: 'UPI ID'),
            const SizedBox(height: 10),
            _clayField(controller: amountCtrl, hint: 'e.g., 100', label: 'Amount (₹)', keyboardType: TextInputType.number),
            const SizedBox(height: 10),
            _clayField(controller: noteCtrl, hint: 'e.g., Monthly rent', label: 'Note (Optional)'),
          ],
        );
      case 'book_ride':
        final destCtrl = _getControllerForStep(step.id, 'destination', step.params['destination'] ?? '');
        final appCtrl = _getControllerForStep(step.id, 'app', step.params['app'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(controller: destCtrl, hint: 'e.g., Airport', label: 'Destination'),
            const SizedBox(height: 10),
            _clayField(controller: appCtrl, hint: 'e.g., Uber or Ola (leave empty for auto)', label: 'App (Optional)'),
          ],
        );
      case 'order_food':
        final restCtrl = _getControllerForStep(step.id, 'restaurant', step.params['restaurant'] ?? '');
        final appCtrl = _getControllerForStep(step.id, 'app', step.params['app'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(controller: restCtrl, hint: 'e.g., Dominos (optional)', label: 'Restaurant (Optional)'),
            const SizedBox(height: 10),
            _clayField(controller: appCtrl, hint: 'e.g., Swiggy or Zomato (optional)', label: 'App (Optional)'),
          ],
        );
      case 'share_content':
        final textCtrl = _getControllerForStep(step.id, 'text', step.params['text'] ?? '');
        final appCtrl = _getControllerForStep(step.id, 'app', step.params['app'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(controller: textCtrl, hint: 'e.g., {step_1}', label: 'Text to Share', maxLines: 2),
            _buildPlaceholderChips(textCtrl, placeholders),
            const SizedBox(height: 10),
            _clayField(controller: appCtrl, hint: 'e.g., WhatsApp (leave empty for share sheet)', label: 'Target App (Optional)'),
          ],
        );
      case 'open_profile':
        final platformCtrl = _getControllerForStep(step.id, 'platform', step.params['platform'] ?? '');
        final usernameCtrl = _getControllerForStep(step.id, 'username', step.params['username'] ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clayField(controller: platformCtrl, hint: 'e.g., Instagram, Twitter, LinkedIn', label: 'Platform'),
            const SizedBox(height: 10),
            _clayField(controller: usernameCtrl, hint: 'e.g., john_doe', label: 'Username'),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _showAddStepSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClayContainer(
        borderRadius: 28,
        baseColor: ClayColors.warmGrey,
        highlightColor: ClayColors.highlight,
        shadowColor: ClayColors.shadow,
        depth: 8.0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ADD WORKFLOW STEP',
              style: GoogleFonts.outfit(
                color: ClayColors.goldAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
                children: [
                  _addStepTile(ctx, 'readClipboard', 'Clipboard', Icons.assignment_returned_rounded, const Color(0xFF34C759)),
                  _addStepTile(ctx, 'readScreen', 'OCR Screen', Icons.screenshot_rounded, const Color(0xFF30B0E8)),
                  _addStepTile(ctx, 'readNotifications', 'Notifs', Icons.notifications_active_rounded, const Color(0xFFAF52DE)),
                  _addStepTile(ctx, 'webSearch', 'Web Search', Icons.travel_explore_rounded, const Color(0xFF32D4C8)),
                  _addStepTile(ctx, 'aiGenerate', 'AI reasoning', Icons.auto_awesome_rounded, const Color(0xFFC8A96A)),
                  _addStepTile(ctx, 'saveMemory', 'Save Memory', Icons.save_rounded, const Color(0xFFE08244)),
                  _addStepTile(ctx, 'speakText', 'Speak TTS', Icons.volume_up_rounded, const Color(0xFFE54B64)),
                  _addStepTile(ctx, 'showNotification', 'Push Notif', Icons.chat_bubble_rounded, const Color(0xFF4C8DF5)),
                  _addStepTile(ctx, 'toggleFlashlight', 'Flashlight', Icons.flashlight_on_rounded, const Color(0xFFFFCC00)),
                  _addStepTile(ctx, 'openApp', 'Open App', Icons.apps_rounded, const Color(0xFF8E8E93)),
                  _addStepTile(ctx, 'sendSMS', 'Send SMS', Icons.sms_rounded, const Color(0xFF00C7B1)),
                  _addStepTile(ctx, 'dial_contact', 'Call contact', Icons.call_rounded, const Color(0xFF30B0E8)),
                  _addStepTile(ctx, 'open_settings', 'Settings', Icons.tune_rounded, const Color(0xFF8E8E93)),
                  _addStepTile(ctx, 'open_camera', 'Camera', Icons.camera_alt_rounded, const Color(0xFFFF6B81)),
                  _addStepTile(ctx, 'ai_digest', 'AI Notif Digest', Icons.auto_awesome_rounded, const Color(0xFFC8A96A)),
                  // Smart App Actions
                  _addStepTile(ctx, 'send_whatsapp', 'WhatsApp', Icons.chat_rounded, const Color(0xFF25D366)),
                  _addStepTile(ctx, 'play_spotify', 'Spotify', Icons.music_note_rounded, const Color(0xFF1DB954)),
                  _addStepTile(ctx, 'upi_payment', 'UPI Pay', Icons.currency_rupee_rounded, const Color(0xFF5F259F)),
                  _addStepTile(ctx, 'book_ride', 'Book Ride', Icons.local_taxi_rounded, const Color(0xFF000000)),
                  _addStepTile(ctx, 'order_food', 'Order Food', Icons.restaurant_rounded, const Color(0xFFE23744)),
                  _addStepTile(ctx, 'share_content', 'Share', Icons.share_rounded, const Color(0xFF4285F4)),
                  _addStepTile(ctx, 'open_profile', 'Profile', Icons.person_rounded, const Color(0xFFE1306C)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addStepTile(BuildContext ctx, String type, String label, IconData icon, Color color) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        setState(() {
          final stepId = 'step_${_steps.length + 1}';
          final params = <String, dynamic>{};
          if (type == 'toggleFlashlight') {
            params['state'] = true;
          } else if (type == 'open_settings') {
            params['type'] = 'general';
          }
          _steps.add(WorkflowStep(id: stepId, type: type, params: params));
        });
      },
      child: ClayContainer(
        borderRadius: 16,
        depth: 4.0,
        baseColor: const Color(0xFFECE9E3),
        highlightColor: const Color(0xFFF7F4EF),
        shadowColor: const Color(0xFFCBC7BE),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.12)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: ClayColors.textDark),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation      : 0,
        iconTheme      : const IconThemeData(color: ClayColors.textDark),
        title: Text(
          _isEditing ? 'Edit AI Agentic Workflow' : 'New AI Agentic Workflow',
          style: GoogleFonts.outfit(
            color: ClayColors.goldAccent, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
          children: [
            // Rule Name
            _sectionHeader('WORKFLOW NAME', Icons.label_rounded),
            _clayField(
              controller: _nameController,
              hint      : 'e.g., Clipboard AI Synthesizer',
              label     : null,
              maxLength : 100,
              error     : _fieldErrors['name'],
              validator : (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),

            const SizedBox(height: 24),

            // Trigger Grid Selection
            _buildTriggerGrid(),

            const SizedBox(height: 20),

            // Trigger Specific Config
            _buildTriggerConfig(),

            const SizedBox(height: 28),

            // Workflow builder
            _buildWorkflowBuilder(),

            const SizedBox(height: 36),

            // Save button
            ClayButton(
              onTap        : _isSaving ? null : _save,
              borderRadius : 20,
              baseColor    : ClayColors.goldAccent,
              highlightColor: ClayColors.goldHighlight,
              shadowColor  : ClayColors.goldShadow,
              depth        : 6.0,
              padding      : const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        _isEditing ? 'Update Workflow' : 'Create Workflow',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
