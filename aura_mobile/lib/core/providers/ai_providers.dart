import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/data/datasources/engine_router.dart';
import 'package:aura_mobile/data/datasources/image_generation_service.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/services/llm_intent_classifier.dart';

// Core AI Services

/// The existing GGUF engine (RunAnywhere / fllama). Kept for backward
/// compatibility and used as the `ggufEngine` parameter of [EngineRouter].
final runAnywhereProvider = Provider((ref) => RunAnywhere());

/// The EngineRouter exposed with its concrete type so the Model Selector can
/// call [EngineRouter.loadModelInfo] directly.
final engineRouterProvider = Provider<EngineRouter>((ref) {
  final ggufEngine = LLMServiceImpl(ref.watch(runAnywhereProvider));
  final litertEngine = LiteRtService();
  final deviceService = ref.watch(deviceServiceProvider);

  return EngineRouter(
    ggufEngine: ggufEngine,
    litertEngine: litertEngine,
    deviceService: deviceService,
  );
});

/// The [LLMService] consumed by the [OrchestratorService] and chat flow.
///
/// Now backed by [EngineRouter], which delegates to the correct engine based on
/// the active model. LiteRT initialization remains lazy — the router's
/// [initialize] only brings up GGUF (Req 10.3).
final llmServiceProvider = Provider<LLMService>((ref) => ref.watch(engineRouterProvider));

final llmIntentClassifierProvider = Provider((ref) => LLMIntentClassifier(ref.watch(llmServiceProvider)));

/// Free online text-to-image generation (Pollinations.ai — no key required).
final imageGenerationServiceProvider =
    Provider((ref) => ImageGenerationService());
