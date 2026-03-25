import 'package:aura_mobile/domain/models/workflow_plan.dart';
import 'package:aura_mobile/domain/models/workflow_step.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';

/// Validates workflow plans and steps before execution
class WorkflowValidator {
  /// Validates an entire workflow plan
  ///
  /// Checks:
  /// - Plan has at least one step
  /// - No duplicate output keys
  /// - No circular dependencies
  /// - All steps are individually valid
  /// - Variable references are valid
  void validatePlan(WorkflowPlan plan) {
    // 1. Plan must have at least one step
    if (plan.steps.isEmpty) {
      throw ValidationException.invalidInput(
        'workflow plan',
        'Plan must have at least one step',
      );
    }

    // 2. Validate each step individually
    for (var i = 0; i < plan.steps.length; i++) {
      try {
        validateStep(plan.steps[i]);
      } catch (e) {
        throw ValidationException.invalidInput(
          'step ${i + 1}',
          e.toString(),
        );
      }
    }

    // 3. Check for duplicate output keys
    _validateNoDuplicateOutputKeys(plan);

    // 4. Validate variable dependencies
    _validateVariableDependencies(plan);

    // 5. Check for circular dependencies
    _validateNoCircularDependencies(plan);
  }

  /// Validates a single workflow step
  ///
  /// Checks:
  /// - Raw message is not empty
  /// - If outputKey is set, extractionRequirement must also be set
  /// - Variable names are valid (alphanumeric + underscore)
  void validateStep(WorkflowStep step) {
    // 1. Raw message must not be empty
    if (step.rawMessage.trim().isEmpty) {
      throw ValidationException.emptyInput(
        'Step message cannot be empty',
      );
    }

    // 2. If outputKey is set, extractionRequirement must also be set
    if (step.outputKey != null && step.extractionRequirement == null) {
      throw ValidationException.invalidInput(
        'step.outputKey',
        'Step with outputKey "${step.outputKey}" must have extractionRequirement',
      );
    }

    // 3. If extractionRequirement is set, outputKey must also be set
    if (step.extractionRequirement != null && step.outputKey == null) {
      throw ValidationException.invalidInput(
        'step.extractionRequirement',
        'Step with extractionRequirement must have outputKey',
      );
    }

    // 4. Validate outputKey format (alphanumeric + underscore only)
    if (step.outputKey != null && !_isValidVariableName(step.outputKey!)) {
      throw ValidationException.invalidInput(
        'step.outputKey',
        'outputKey "${step.outputKey}" contains invalid characters. Use only letters, numbers, and underscores',
      );
    }

    // 5. Check for reasonable message length
    if (step.rawMessage.length > 1000) {
      throw ValidationException.invalidInput(
        'step.rawMessage',
        'Message is too long (max 1000 characters)',
      );
    }
  }

  /// Validates that variable references in steps are defined by previous steps
  void _validateVariableDependencies(WorkflowPlan plan) {
    final definedVariables = <String>{};

    for (var i = 0; i < plan.steps.length; i++) {
      final step = plan.steps[i];
      final referencedVars = extractVariableReferences(step.rawMessage);

      // Check if all referenced variables are defined
      for (final varName in referencedVars) {
        if (!definedVariables.contains(varName)) {
          throw ValidationException.invalidInput(
            'step ${i + 1}',
            'References undefined variable "{$varName}". Variables must be defined in earlier steps',
          );
        }
      }

      // Add this step's output variable to defined set
      if (step.outputKey != null) {
        definedVariables.add(step.outputKey!);
      }
    }
  }

  /// Validates that no two steps define the same output key
  void _validateNoDuplicateOutputKeys(WorkflowPlan plan) {
    final seenKeys = <String>{};

    for (var i = 0; i < plan.steps.length; i++) {
      final step = plan.steps[i];
      if (step.outputKey != null) {
        if (seenKeys.contains(step.outputKey)) {
          throw ValidationException.invalidInput(
            'step ${i + 1}.outputKey',
            'Duplicate outputKey "${step.outputKey}". Each outputKey must be unique',
          );
        }
        seenKeys.add(step.outputKey!);
      }
    }
  }

  /// Validates that there are no circular dependencies in variable references
  void _validateNoCircularDependencies(WorkflowPlan plan) {
    // Build dependency graph
    final dependencies = <String, Set<String>>{};

    for (final step in plan.steps) {
      if (step.outputKey != null) {
        final refs = extractVariableReferences(step.rawMessage);
        dependencies[step.outputKey!] = refs;
      }
    }

    // Check for cycles using DFS
    for (final variable in dependencies.keys) {
      final visited = <String>{};
      final recursionStack = <String>{};

      if (_hasCycle(variable, dependencies, visited, recursionStack)) {
        throw ValidationException.invalidInput(
          'variable dependencies',
          'Circular dependency detected involving variable "$variable". Steps cannot reference variables that depend on themselves',
        );
      }
    }
  }

  /// Detects cycles in dependency graph using DFS
  bool _hasCycle(
    String variable,
    Map<String, Set<String>> dependencies,
    Set<String> visited,
    Set<String> recursionStack,
  ) {
    visited.add(variable);
    recursionStack.add(variable);

    // Check all dependencies of current variable
    final deps = dependencies[variable] ?? {};
    for (final dep in deps) {
      // If dependency is in recursion stack, we have a cycle
      if (recursionStack.contains(dep)) {
        return true;
      }

      // If not visited, check recursively
      if (!visited.contains(dep)) {
        if (_hasCycle(dep, dependencies, visited, recursionStack)) {
          return true;
        }
      }
    }

    recursionStack.remove(variable);
    return false;
  }

  /// Extracts variable references from a message string
  /// Example: "Use {var1} and {var2}" -> {"var1", "var2"}
  Set<String> extractVariableReferences(String message) {
    final pattern = RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}');
    final matches = pattern.allMatches(message);
    return matches.map((m) => m.group(1)!).toSet();
  }

  /// Checks if a variable name is valid (alphanumeric + underscore, must start with letter or underscore)
  bool _isValidVariableName(String name) {
    final pattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
    return pattern.hasMatch(name);
  }

  /// Validates workflow state before resuming
  ///
  /// Checks:
  /// - Workflow ID is not empty
  /// - Current step index is valid
  void validateResume(String workflowId, int currentStepIndex, int totalSteps) {
    if (workflowId.trim().isEmpty) {
      throw ValidationException.invalidInput('workflowId', 'Cannot be empty');
    }

    if (currentStepIndex < 0) {
      throw ValidationException.invalidInput(
        'currentStepIndex',
        'Invalid step index: $currentStepIndex (must be >= 0)',
      );
    }

    if (currentStepIndex >= totalSteps) {
      throw ValidationException.invalidInput(
        'currentStepIndex',
        'Invalid step index: $currentStepIndex (total steps: $totalSteps)',
      );
    }
  }

  /// Validates extracted data against requirements
  ///
  /// Checks if the extracted value is not empty and meets minimum requirements
  bool isValidExtractedData(String? data) {
    if (data == null) return false;
    final trimmed = data.trim();
    return trimmed.isNotEmpty && trimmed != 'NOT_FOUND';
  }
}
