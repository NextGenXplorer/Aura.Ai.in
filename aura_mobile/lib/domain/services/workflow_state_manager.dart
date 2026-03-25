import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:aura_mobile/domain/models/workflow_plan.dart';
import 'package:aura_mobile/domain/models/workflow_step.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';

/// Workflow execution state
enum WorkflowStatus {
  pending,
  running,
  paused,
  completed,
  failed,
  cancelled;

  String toJson() => name;
  static WorkflowStatus fromJson(String json) => values.byName(json);
}

/// Persisted workflow state for resume capability
class WorkflowState {
  final String id;
  final String originalMessage;
  final WorkflowPlan plan;
  final int currentStepIndex;
  final WorkflowStatus status;
  final DateTime createdAt;
  final DateTime lastUpdated;
  final Map<String, String> extractedData;
  final List<String> completedSteps;
  final String? lastError;
  final int retryCount;

  const WorkflowState({
    required this.id,
    required this.originalMessage,
    required this.plan,
    required this.currentStepIndex,
    required this.status,
    required this.createdAt,
    required this.lastUpdated,
    this.extractedData = const {},
    this.completedSteps = const [],
    this.lastError,
    this.retryCount = 0,
  });

  bool get isComplete => currentStepIndex >= plan.length;
  bool get canResume => status == WorkflowStatus.paused || status == WorkflowStatus.failed;
  WorkflowStep? get currentStep =>
      currentStepIndex < plan.length ? plan.steps[currentStepIndex] : null;

  WorkflowState copyWith({
    int? currentStepIndex,
    WorkflowStatus? status,
    DateTime? lastUpdated,
    Map<String, String>? extractedData,
    List<String>? completedSteps,
    String? lastError,
    int? retryCount,
  }) {
    return WorkflowState(
      id: id,
      originalMessage: originalMessage,
      plan: plan,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      status: status ?? this.status,
      createdAt: createdAt,
      lastUpdated: lastUpdated ?? DateTime.now(),
      extractedData: extractedData ?? this.extractedData,
      completedSteps: completedSteps ?? this.completedSteps,
      lastError: lastError ?? this.lastError,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalMessage': originalMessage,
      'plan': {
        'steps': plan.steps.map((s) => s.toMap()).toList(),
        'failFast': plan.failFast,
      },
      'currentStepIndex': currentStepIndex,
      'status': status.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
      'extractedData': extractedData,
      'completedSteps': completedSteps,
      'lastError': lastError,
      'retryCount': retryCount,
    };
  }

  factory WorkflowState.fromJson(Map<String, dynamic> json) {
    final planJson = json['plan'] as Map<String, dynamic>;
    final steps = (planJson['steps'] as List)
        .map((s) => WorkflowStep.fromMap(s as Map<String, dynamic>))
        .toList();

    return WorkflowState(
      id: json['id'] as String,
      originalMessage: json['originalMessage'] as String,
      plan: WorkflowPlan(
        steps: steps,
        failFast: planJson['failFast'] as bool? ?? false,
      ),
      currentStepIndex: json['currentStepIndex'] as int,
      status: WorkflowStatus.fromJson(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      extractedData: Map<String, String>.from(json['extractedData'] as Map? ?? {}),
      completedSteps: List<String>.from(json['completedSteps'] as List? ?? []),
      lastError: json['lastError'] as String?,
      retryCount: json['retryCount'] as int? ?? 0,
    );
  }
}

/// Manages workflow persistence and resumption
class WorkflowStateManager {
  static const String _keyPrefix = 'workflow_state_';
  static const String _activeWorkflowsKey = 'active_workflows';
  static const Duration _expirationDuration = Duration(hours: 24);

  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  /// Create a new workflow state
  WorkflowState createWorkflowState(String originalMessage, WorkflowPlan plan) {
    return WorkflowState(
      id: const Uuid().v4(),
      originalMessage: originalMessage,
      plan: plan,
      currentStepIndex: 0,
      status: WorkflowStatus.pending,
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
  }

  /// Save workflow state to persistent storage
  Future<void> saveWorkflowState(WorkflowState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix${state.id}';
      final json = jsonEncode(state.toJson());

      await prefs.setString(key, json);

      // Track active workflows
      final activeWorkflows = await getActiveWorkflowIds();
      if (!activeWorkflows.contains(state.id)) {
        activeWorkflows.add(state.id);
        await prefs.setStringList(_activeWorkflowsKey, activeWorkflows);
      }

      _errorHandler.logInfo('Saved workflow state: ${state.id}');
    } catch (e) {
      throw WorkflowException.saveFailed(e);
    }
  }

  /// Load workflow state from storage
  Future<WorkflowState?> loadWorkflowState(String workflowId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$workflowId';
      final json = prefs.getString(key);

      if (json == null) {
        return null;
      }

      final data = jsonDecode(json) as Map<String, dynamic>;
      final state = WorkflowState.fromJson(data);

      // Check if expired
      if (DateTime.now().difference(state.lastUpdated) > _expirationDuration) {
        _errorHandler.logWarning('Workflow $workflowId expired, removing');
        await deleteWorkflowState(workflowId);
        return null;
      }

      return state;
    } catch (e) {
      throw WorkflowException.loadFailed(workflowId, e);
    }
  }

  /// Get all active workflow IDs
  Future<List<String>> getActiveWorkflowIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_activeWorkflowsKey) ?? [];
  }

  /// Get all resumable workflows
  Future<List<WorkflowState>> getResumableWorkflows() async {
    final workflowIds = await getActiveWorkflowIds();
    final workflows = <WorkflowState>[];

    for (final id in workflowIds) {
      try {
        final state = await loadWorkflowState(id);
        if (state != null && state.canResume) {
          workflows.add(state);
        }
      } catch (e) {
        _errorHandler.logWarning('Failed to load workflow $id: $e');
      }
    }

    return workflows;
  }

  /// Delete workflow state
  Future<void> deleteWorkflowState(String workflowId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$workflowId';
      await prefs.remove(key);

      // Remove from active workflows
      final activeWorkflows = await getActiveWorkflowIds();
      activeWorkflows.remove(workflowId);
      await prefs.setStringList(_activeWorkflowsKey, activeWorkflows);

      _errorHandler.logInfo('Deleted workflow state: $workflowId');
    } catch (e) {
      _errorHandler.logWarning('Failed to delete workflow $workflowId: $e');
    }
  }

  /// Clean up expired workflows
  Future<void> cleanupExpiredWorkflows() async {
    final workflowIds = await getActiveWorkflowIds();
    final now = DateTime.now();

    for (final id in workflowIds) {
      try {
        final state = await loadWorkflowState(id);
        if (state == null || now.difference(state.lastUpdated) > _expirationDuration) {
          await deleteWorkflowState(id);
        }
      } catch (e) {
        _errorHandler.logWarning('Error cleaning up workflow $id: $e');
      }
    }

    _errorHandler.logInfo('Cleanup completed');
  }

  /// Clean up completed workflows
  Future<void> cleanupCompletedWorkflows() async {
    final workflowIds = await getActiveWorkflowIds();

    for (final id in workflowIds) {
      try {
        final state = await loadWorkflowState(id);
        if (state != null && state.status == WorkflowStatus.completed) {
          await deleteWorkflowState(id);
        }
      } catch (e) {
        _errorHandler.logWarning('Error cleaning up completed workflow $id: $e');
      }
    }
  }

  /// Update workflow progress
  Future<void> updateProgress(
    String workflowId, {
    int? currentStepIndex,
    WorkflowStatus? status,
    Map<String, String>? extractedData,
    List<String>? completedSteps,
    String? lastError,
    int? retryCount,
  }) async {
    final state = await loadWorkflowState(workflowId);
    if (state == null) {
      throw WorkflowException.workflowNotFound(workflowId);
    }

    final updatedState = state.copyWith(
      currentStepIndex: currentStepIndex,
      status: status,
      extractedData: extractedData,
      completedSteps: completedSteps,
      lastError: lastError,
      retryCount: retryCount,
    );

    await saveWorkflowState(updatedState);
  }
}
