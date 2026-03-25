import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:aura_mobile/domain/services/workflow_splitter_service.dart';

// ─── Workflow Providers ───────────────────────────────────────────────────────

final workflowSplitterServiceProvider = Provider<WorkflowSplitterService>((ref) {
  return WorkflowSplitterService(
    ref.watch(llmIntentClassifierProvider),
    ref.watch(llmServiceProvider),
    ref.watch(intentDetectionServiceProvider),
  );
});

// NOTE: WorkflowEngineService is constructed inside orchestratorServiceProvider
// (see features/orchestrator/orchestrator_service.dart) because WorkflowEngineService
// depends on OrchestratorService.processMessage, and Riverpod cannot handle
// the circular dependency. We pass the function reference at construction time instead.
