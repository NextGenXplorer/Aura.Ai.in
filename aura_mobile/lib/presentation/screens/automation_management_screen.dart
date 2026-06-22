import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:aura_mobile/features/automation/application/automation_engine.dart';
import 'package:aura_mobile/features/automation/domain/automation_rule.dart';
import 'package:aura_mobile/presentation/screens/automation_rule_form_screen.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

class AutomationManagementScreen extends ConsumerStatefulWidget {
  const AutomationManagementScreen({super.key});

  @override
  ConsumerState<AutomationManagementScreen> createState() =>
      _AutomationManagementScreenState();
}

class _AutomationManagementScreenState
    extends ConsumerState<AutomationManagementScreen> {
  List<AutomationRule>? _rules;
  bool _isLoading = true;
  String? _error;
  String? _runningRuleId;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final rules = await ref.read(automationEngineProvider).getAllRules();
      setState(() { _rules = rules; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _toggleEnabled(String ruleId, bool value) async {
    try {
      await ref.read(automationEngineProvider).setEnabled(ruleId, value);
      await _loadRules();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update rule: $e')));
      }
    }
  }

  Future<void> _runNow(AutomationRule rule) async {
    setState(() => _runningRuleId = rule.id);
    try {
      final result =
          await ref.read(automationEngineProvider).executeRuleNow(rule);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result),
          backgroundColor: result.contains('Failed') ? Colors.red[700] : Colors.green[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        await _loadRules();
      }
    } finally {
      if (mounted) setState(() => _runningRuleId = null);
    }
  }

  Future<void> _confirmDelete(AutomationRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ClayDialog(
        title  : 'Delete Workflow',
        content: Text(
          'Delete "${rule.name}"? This cannot be undone.',
          style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 14, height: 1.4),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.outfit(
                color: ClayColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          ClayButton(
            onTap: () => Navigator.of(ctx).pop(true),
            borderRadius : 14,
            padding      : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            baseColor    : ClayColors.redAccent,
            highlightColor: ClayColors.redHighlight,
            shadowColor  : ClayColors.redShadow,
            child: Text('Delete', style: GoogleFonts.outfit(
                color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(automationEngineProvider).deleteRule(rule.id);
        await _loadRules();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete rule: $e')));
        }
      }
    }
  }

  String _nextRunLabel(AutomationRule rule) {
    switch (rule.triggerType) {
      case TriggerType.scheduled:
        if (rule.scheduledTime == null) return 'No time set';
        if (rule.scheduledTime!.isBefore(DateTime.now())) return 'Completed';
        return 'At ${DateFormat.MMMd().add_jm().format(rule.scheduledTime!)}';

      case TriggerType.recurring:
        if (rule.repeatInterval == null) return '';
        final last = rule.lastExecutedAt ?? rule.createdAt;
        final next = last.add(rule.repeatInterval!);
        if (next.isBefore(DateTime.now())) return 'Due soon';
        final diff = next.difference(DateTime.now());
        if (diff.inMinutes < 60) return 'In ${diff.inMinutes}m';
        if (diff.inHours  < 24) return 'In ${diff.inHours}h';
        return 'In ${diff.inDays}d';

      case TriggerType.conditionBased:
        return 'Checks every ${_durationLabel(rule.checkInterval)}';

      case TriggerType.conversationPattern:
        return 'Active (On Keyword)';

      case TriggerType.onClipboardCopy:
        return 'Active (On Copy)';

      case TriggerType.onNotificationReceived:
        return 'Active (On Notif)';
    }
  }

  String _durationLabel(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours   < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  String _formatLastExecution(DateTime? dt) {
    if (dt == null) return 'Never executed';
    return 'Last run ${DateFormat.MMMd().add_jm().format(dt)}';
  }

  IconData _triggerIcon(TriggerType t) => switch (t) {
    TriggerType.scheduled    => Icons.alarm_rounded,
    TriggerType.recurring    => Icons.loop_rounded,
    TriggerType.conditionBased => Icons.rule_rounded,
    TriggerType.conversationPattern => Icons.chat_bubble_outline_rounded,
    TriggerType.onClipboardCopy => Icons.copy_rounded,
    TriggerType.onNotificationReceived => Icons.notifications_active_rounded,
  };

  Color _stepColor(String type) => switch (type) {
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
    _ => const Color(0xFFBC4B2E),
  };

  IconData _stepIcon(String type) => switch (type) {
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
    _ => Icons.circle_outlined,
  };

  String _stepLabel(String type) => switch (type) {
    'readClipboard' => 'Clipboard',
    'readScreen' => 'Screen OCR',
    'readNotifications' => 'Notifications',
    'webSearch' => 'Search',
    'aiGenerate' => 'AI',
    'saveMemory' => 'Memory',
    'speakText' => 'TTS',
    'showNotification' => 'Notif',
    'toggleFlashlight' => 'Flashlight',
    'openApp' => 'App',
    'sendSMS' => 'SMS',
    'dial_contact' => 'Call',
    'open_settings' => 'Settings',
    'open_camera' => 'Camera',
    'ai_digest' => 'AI Digest',
    _ => type,
  };

  Widget _buildWorkflowSequence(List<WorkflowStep> steps) {
    final widgets = <Widget>[];
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final color = _stepColor(step.type);
      final icon = _stepIcon(step.type);
      
      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: color.withOpacity(0.08),
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 10, color: color),
              const SizedBox(width: 4),
              Text(
                _stepLabel(step.type),
                style: GoogleFonts.outfit(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
      
      if (i < steps.length - 1) {
        widgets.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Icon(Icons.arrow_forward_rounded, size: 10, color: ClayColors.textHint),
          ),
        );
      }
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: widgets,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation  : 0,
        iconTheme  : const IconThemeData(color: ClayColors.textDark),
        title: Text('AI Agentic Workflows',
            style: GoogleFonts.outfit(
                color: ClayColors.goldAccent, fontWeight: FontWeight.bold)),
      ),
      body: _buildBody(),
      floatingActionButton: ClayButton(
        onTap: () {
          Navigator.push(context,
            createClayRoute(const AutomationRuleFormScreen()),
          ).then((_) => _loadRules());
        },
        borderRadius   : 28,
        depth          : 6.0,
        baseColor      : ClayColors.goldAccent,
        highlightColor : ClayColors.goldHighlight,
        shadowColor    : ClayColors.goldShadow,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.add_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text('New Workflow', style: GoogleFonts.outfit(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: ClayColors.goldAccent));
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: ClayContainer(
          borderRadius: 24,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: ClayColors.redAccent),
            const SizedBox(height: 16),
            Text('Something went wrong', style: GoogleFonts.outfit(
              fontSize: 16, fontWeight: FontWeight.bold, color: ClayColors.textDark)),
            const SizedBox(height: 8),
            Text(_error!, style: GoogleFonts.outfit(
              color: ClayColors.textMuted, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ClayButton(
              onTap: _loadRules,
              borderRadius   : 14,
              baseColor      : ClayColors.goldAccent,
              highlightColor : ClayColors.goldHighlight,
              shadowColor    : ClayColors.goldShadow,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text('Retry', style: GoogleFonts.outfit(
                  color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      ));
    }
    if (_rules == null || _rules!.isEmpty) return _buildEmptyState();
    return RefreshIndicator(
      onRefresh: _loadRules,
      color: ClayColors.goldAccent,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _rules!.length,
        itemBuilder: (context, index) {
          final rule = _rules![index];
          return TweenAnimationBuilder<double>(
            duration: Duration(milliseconds: 280 + (index * 70)),
            tween: Tween(begin: 0.0, end: 1.0),
            curve: Curves.easeOutCubic,
            builder: (ctx, v, child) => Transform.translate(
              offset: Offset(0, 24 * (1 - v)),
              child: Opacity(opacity: v, child: child),
            ),
            child: _buildRuleCard(rule),
          );
        },
      ),
    );
  }

  Widget _buildRuleCard(AutomationRule rule) {
    final isRunning = _runningRuleId == rule.id;

    // Resolve steps
    final List<WorkflowStep> steps;
    if (rule.isWorkflow) {
      steps = rule.workflowSteps;
    } else {
      final jsonStr = rule.actionJson ?? '';
      final type = jsonStr.isNotEmpty ? (jsonDecode(jsonStr)['name'] as String? ?? 'aiTask') : 'aiTask';
      final params = jsonStr.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(jsonStr)['arguments'] as Map? ?? {}) : <String, dynamic>{};
      steps = [WorkflowStep(id: 'step_1', type: type, params: params)];
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Dismissible(
        key: Key(rule.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: ClayColors.redAccent.withOpacity(0.8),
            borderRadius: BorderRadius.circular(22)),
          child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
        ),
        confirmDismiss: (_) async {
          await _confirmDelete(rule);
          return false;
        },
        child: ClayContainer(
          borderRadius: 22,
          baseColor    : ClayColors.warmGrey,
          highlightColor: ClayColors.highlight,
          shadowColor  : ClayColors.shadow,
          depth        : 6.0,
          padding      : const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                // Workflow Default Badge
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ClayColors.goldAccent.withOpacity(0.12)),
                  child: const Icon(Icons.alt_route_rounded, color: ClayColors.goldAccent, size: 22),
                ),
                const SizedBox(width: 12),

                // Name + trigger
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rule.name, style: GoogleFonts.outfit(
                      color: ClayColors.textDark,
                      fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(_triggerIcon(rule.triggerType),
                          size: 12, color: ClayColors.textMuted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(rule.triggerDescription,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 11)),
                      ),
                    ]),
                  ],
                )),

                // Enable/disable switch
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: rule.isEnabled,
                    activeColor    : ClayColors.goldAccent,
                    activeTrackColor: ClayColors.goldHighlight,
                    inactiveThumbColor: ClayColors.textHint,
                    inactiveTrackColor: const Color(0xFFE5E2DA),
                    onChanged: (v) => _toggleEnabled(rule.id, v),
                  ),
                ),
              ]),

              // Sequence steps
              const SizedBox(height: 12),
              _buildWorkflowSequence(steps),

              const SizedBox(height: 12),

              // Bottom row: last-run + next-run + Run Now button
              Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_formatLastExecution(rule.lastExecutedAt),
                      style: GoogleFonts.outfit(
                        color: ClayColors.textHint, fontSize: 11)),
                    const SizedBox(height: 1),
                    Text(_nextRunLabel(rule),
                      style: GoogleFonts.outfit(
                        color: ClayColors.goldAccent,
                        fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                )),

                // Edit button
                GestureDetector(
                  onTap: () => Navigator.push(context,
                    createClayRoute(AutomationRuleFormScreen(existingRule: rule))
                  ).then((_) => _loadRules()),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ClayColors.textHint.withOpacity(0.1)),
                    child: const Icon(Icons.edit_rounded,
                        size: 16, color: ClayColors.textMuted),
                  ),
                ),
                const SizedBox(width: 8),

                // Run Now button
                GestureDetector(
                  onTap: isRunning ? null : () => _runNow(rule),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: isRunning
                          ? null
                          : const LinearGradient(
                              colors: [ClayColors.goldAccent, Color(0xFFD84315)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight),
                      color: isRunning ? ClayColors.textHint.withOpacity(0.1) : null,
                    ),
                    child: isRunning
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: ClayColors.goldAccent))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('Run Now', style: GoogleFonts.outfit(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ]),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 20),
        ClayContainer(
          borderRadius: 24,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClayContainer(
              width: 68, height: 68, borderRadius: 20, depth: 3.0,
              baseColor    : ClayColors.goldAccent.withOpacity(0.15),
              highlightColor: ClayColors.highlight,
              shadowColor  : ClayColors.shadow,
              child: const Icon(Icons.auto_awesome_outlined,
                  size: 32, color: ClayColors.goldAccent),
            ),
            const SizedBox(height: 20),
            Text('No workflows yet', style: GoogleFonts.outfit(
              fontSize: 17, fontWeight: FontWeight.bold, color: ClayColors.textDark)),
            const SizedBox(height: 8),
            Text(
              'Build sequential multi-step AI Agentic Workflows that process clipboard, screen OCR, notifications, search, memory, and TTS automatically.',
              style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ClayButton(
              onTap: () => Navigator.push(context,
                createClayRoute(const AutomationRuleFormScreen()),
              ).then((_) => _loadRules()),
              borderRadius   : 18,
              baseColor      : ClayColors.goldAccent,
              highlightColor : ClayColors.goldHighlight,
              shadowColor    : ClayColors.goldShadow,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Text('Create First Workflow', style: GoogleFonts.outfit(
                  color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
        const SizedBox(height: 80),
      ]),
    );
  }
}
