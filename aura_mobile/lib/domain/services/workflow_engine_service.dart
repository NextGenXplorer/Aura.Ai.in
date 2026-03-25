import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:aura_mobile/domain/models/workflow_plan.dart';
import 'package:aura_mobile/domain/models/workflow_step.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/workflow_state_manager.dart';
import 'package:aura_mobile/domain/services/workflow_validator.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';

// Forward declaration to avoid circular import.
typedef OrchestratorProcessFn = Stream<String> Function({
  required String message,
  required List<String> chatHistory,
  bool hasDocuments,
  bool isVoiceQuery,
  bool forceNormalChat,
});

// ─────────────────────────────────────────────────────────────────────────────
// WorkflowEngineService
//
// Executes a WorkflowPlan step-by-step, yielding:
//   • A step progress header for each step
//   • The full streaming output of that step via OrchestratorService
//   • Error messages on step failure (continues unless failFast = true)
//   • Advanced Entity Extraction (Deep Context)
// ─────────────────────────────────────────────────────────────────────────────
class WorkflowEngineService {
  final OrchestratorProcessFn _processMessage;
  final LLMService _llmService;
  final WorkflowStateManager _stateManager;
  final ErrorHandlerService _errorHandler;
  final WorkflowValidator _validator;

  static const int _maxRetries = 3;
  static const Duration _stepTimeout = Duration(minutes: 5);

  WorkflowEngineService(
    this._processMessage,
    this._llmService, {
    WorkflowStateManager? stateManager,
    ErrorHandlerService? errorHandler,
    WorkflowValidator? validator,
  })  : _stateManager = stateManager ?? WorkflowStateManager(),
        _errorHandler = errorHandler ?? ErrorHandlerService(),
        _validator = validator ?? WorkflowValidator();

  /// Execute [plan] step by step with retry and persistence support.
  Stream<String> execute(
    WorkflowPlan plan,
    List<String> chatHistory, {
    String? originalMessage,
    String? resumeWorkflowId,
  }) async* {
    // Validate the workflow plan before execution
    try {
      _validator.validatePlan(plan);
    } catch (e) {
      yield '❌ Workflow validation failed: ${e.toString()}\n';
      _errorHandler.handleError(e);
      return;
    }

    WorkflowState? workflowState;

    // Check if resuming existing workflow
    if (resumeWorkflowId != null) {
      // Validate resume parameters
      _validator.validateResume(
        resumeWorkflowId,
        0, // Will be updated when we load the state
        plan.steps.length,
      );
      workflowState = await _stateManager.loadWorkflowState(resumeWorkflowId);
      if (workflowState == null) {
        throw WorkflowException.workflowNotFound(resumeWorkflowId);
      }
      yield '🔄 Resuming workflow from step ${workflowState.currentStepIndex + 1}...\n\n';
    } else {
      // Create new workflow state
      workflowState = _stateManager.createWorkflowState(
        originalMessage ?? 'Multi-step workflow',
        plan,
      );
      await _stateManager.saveWorkflowState(workflowState);
    }

    final total = plan.steps.length;
    debugPrint('WORKFLOW_ENGINE: Starting plan with $total steps');

    String? previousResult;
    final Map<String, String> workflowData = Map.from(workflowState.extractedData);
    final List<String> completedSteps = List.from(workflowState.completedSteps);

    // Start from current step (for resume capability)
    for (var i = workflowState.currentStepIndex; i < total; i++) {
      final step = plan.steps[i];
      final stepNum = i + 1;

      // Update state: currently processing this step
      await _stateManager.updateProgress(
        workflowState.id,
        currentStepIndex: i,
        status: WorkflowStatus.running,
      );

      // 1. Variable Interpolation: Replace {key} with data from previously plucked entities
      var currentMessage = step.rawMessage;
      workflowData.forEach((key, value) {
        currentMessage = currentMessage.replaceAll('{$key}', value);
      });

      // 2. Fallback Context Injection (for "it", "that", etc.)
      if (previousResult != null) {
        currentMessage = _enrichMessageWithContext(step, currentMessage, previousResult);
      }

      // Step header
      yield _stepLabel(step, stepNum, total);

      final resultBuffer = StringBuffer();
      var stepFailed = false;
      var retryCount = 0;

      try {
        // Retry loop for failed steps
        while (retryCount <= _maxRetries) {
        try {
          // Execute step with timeout
          await for (final token in _executeStepWithTimeout(
            currentMessage,
            chatHistory,
            stepNum,
          )) {
            yield token;
            resultBuffer.write(token);
          }

          debugPrint('WORKFLOW_ENGINE: Step $stepNum completed successfully');
          stepFailed = false;
          break; // Success - exit retry loop
        } catch (e) {
          retryCount++;
          stepFailed = true;

          _errorHandler.logWarning('Step $stepNum failed (attempt $retryCount): $e');

          if (retryCount <= _maxRetries) {
            // Calculate retry delay
            final delay = _errorHandler.getRetryDelay(retryCount - 1);
            yield '\n⚠️ Step $stepNum failed. Retrying in ${delay.inSeconds}s... (attempt $retryCount/$_maxRetries)';

            await Future.delayed(delay);
            yield '\n🔄 Retrying step $stepNum...\n\n';

            // Clear buffer for retry
            resultBuffer.clear();
          } else {
            // Max retries exceeded
            final error = WorkflowException.maxRetriesExceeded(stepNum, step.rawMessage);
            _errorHandler.handleError(error);

            yield '\n\n❌ ${error.userMessage}';

            // Save failed state
            await _stateManager.updateProgress(
              workflowState.id,
              status: WorkflowStatus.failed,
              lastError: error.userMessage,
              retryCount: retryCount,
            );

            if (plan.failFast) {
              yield '\n\n⛔ Workflow aborted — step failed after retries.';
              return;
            }
          }
        }
      }

        // 3. Entity Extraction: If this step has an outputKey, pluck the requested data
        if (step.outputKey != null && step.extractionRequirement != null && resultBuffer.isNotEmpty) {
          yield '\n\n*🔍 Extracting ${step.outputKey}...*';
          final plucked = await _pluckEntity(step.extractionRequirement!, resultBuffer.toString());
          if (plucked != null) {
            workflowData[step.outputKey!] = plucked;
            debugPrint('WORKFLOW_ENGINE: Plucked ${step.outputKey} = $plucked');
          }
        }
      } catch (e) {
        stepFailed = true;
        debugPrint('WORKFLOW_ENGINE: Step $stepNum failed: $e');
        yield '\n⚠️ Step $stepNum encountered an error: ${_friendlyError(e)}';

        if (plan.failFast) {
          yield '\n\n⛔ Workflow aborted — earlier step failed.';
          return;
        }
      }

      // 4. Track completed step
      if (!stepFailed) {
        completedSteps.add(step.rawMessage);
        await _stateManager.updateProgress(
          workflowState.id,
          completedSteps: completedSteps,
          extractedData: workflowData,
        );
      }

      // 5. Cache result for context passing
      if (!stepFailed && _shouldPassContext(step)) {
        final result = resultBuffer.toString().trim();
        previousResult = result.length > 300 ? '${result.substring(0, 300)}...' : result;
      } else if (stepFailed) {
        previousResult = null;
      }

      if (i < total - 1) {
        yield '\n\n---\n\n';
      }
    }

    // Mark workflow as complete
    await _stateManager.updateProgress(
      workflowState.id,
      status: WorkflowStatus.completed,
      currentStepIndex: total,
    );

    debugPrint('WORKFLOW_ENGINE: Plan complete');
    yield '\n\n✅ Workflow complete';

    // Cleanup completed workflow after a delay
    final workflowId = workflowState.id;
    Future.delayed(const Duration(minutes: 5), () {
      _stateManager.deleteWorkflowState(workflowId);
    });
  }

  /// Execute a step with timeout protection
  Stream<String> _executeStepWithTimeout(
    String message,
    List<String> chatHistory,
    int stepNum,
  ) async* {
    final streamController = StreamController<String>();
    bool completed = false;

    // Start the message processing
    final processFuture = _processMessage(
      message: message,
      chatHistory: chatHistory,
      hasDocuments: false,
      isVoiceQuery: false,
      forceNormalChat: false,
    ).forEach((token) {
      if (!streamController.isClosed) {
        streamController.add(token);
      }
    }).then((_) {
      completed = true;
      if (!streamController.isClosed) {
        streamController.close();
      }
    }).catchError((error) {
      if (!streamController.isClosed) {
        streamController.addError(error);
        streamController.close();
      }
    });

    // Set up timeout
    final timeoutFuture = Future.delayed(_stepTimeout, () {
      if (!completed && !streamController.isClosed) {
        streamController.addError(
          WorkflowException.stepTimeout(stepNum, message),
        );
        streamController.close();
      }
    });

    // Yield tokens from the stream
    try {
      await for (final token in streamController.stream) {
        yield token;
      }
    } finally {
      if (!streamController.isClosed) {
        streamController.close();
      }
    }

    // Clean up futures
    await Future.any([processFuture, timeoutFuture]);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _stepLabel(WorkflowStep step, int stepNum, int total) {
    final icon = _intentIcon(step.hintType);
    final summary = _stepSummary(step);
    return '**[$stepNum/$total] $icon $summary**\n\n';
  }

  String _stepSummary(WorkflowStep step) {
    final hint = step.hintType;
    final msg = step.rawMessage;
    if (hint == null) return _titleCase(msg.length > 50 ? '${msg.substring(0, 47)}...' : msg);

    switch (hint) {
      case IntentType.webSearch:      return 'Searching the web...';
      case IntentType.reminderSet:    return 'Setting reminder...';
      case IntentType.openApp:        return 'Opening app...';
      case IntentType.dialContact:    return 'Calling contact...';
      case IntentType.sendSMS:        return 'Sending SMS...';
      case IntentType.emailDraft:     return 'Drafting email...';
      case IntentType.navigation:     return 'Navigating...';
      case IntentType.normalChat:     return 'Processing...';
      case IntentType.weatherSearch:  return 'Checking weather...';
      default:                        return 'Processing step...';
    }
  }

  String _intentIcon(IntentType? hint) {
    switch (hint) {
      case IntentType.webSearch:      return '🔍';
      case IntentType.reminderSet:    return '⏰';
      case IntentType.openApp:        return '🚀';
      case IntentType.dialContact:    return '📞';
      case IntentType.sendSMS:        return '📨';
      case IntentType.emailDraft:     return '✉️';
      case IntentType.navigation:     return '🗺️';
      case IntentType.weatherSearch:  return '🌤️';
      default:                        return '💬';
    }
  }

  bool _shouldPassContext(WorkflowStep step) =>
      step.hintType == IntentType.webSearch || step.hintType == IntentType.normalChat;

  String _enrichMessageWithContext(WorkflowStep step, String message, String previousResult) {
    final hasRef = RegExp(
      r'\b(about\s+that|the\s+result|that\s+info|it)\b',
      caseSensitive: false,
    ).hasMatch(message);

    if (!hasRef) return message;
    return '$message\n\n[Context from previous step: $previousResult]';
  }

  Future<String?> _pluckEntity(String requirement, String context) async {
    final prompt = '''
Extract information based on requirement: "$requirement"
Input Text:
"""
$context
"""
Return ONLY the extracted value or "NOT_FOUND". No explanation.
''';

    try {
      final buffer = StringBuffer();
      await for (final token in _llmService.chat(
        'Extract entity from context: "$context"',
        systemPrompt: prompt,
        maxTokens: 50,
      )) {
        buffer.write(token);
      }
      final result = buffer.toString().trim();
      return result == 'NOT_FOUND' ? null : result;
    } catch (e) {
      return null;
    }
  }

  String _friendlyError(Object e) => e.toString().split('\n').first;

  String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
