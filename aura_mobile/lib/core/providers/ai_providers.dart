import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/core/services/download_service.dart';
import 'package:aura_mobile/core/services/llm_selection_store.dart';
import 'package:aura_mobile/core/services/provider_api_key_store.dart';
import 'package:aura_mobile/data/datasources/litert_service.dart';
import 'package:aura_mobile/data/datasources/llm_router.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/data/datasources/openai_compatible_llm_service.dart';
import 'package:aura_mobile/data/datasources/function_gemma_service.dart';
import 'package:aura_mobile/data/datasources/embedding_service.dart';
import 'package:aura_mobile/data/datasources/image_generation_service.dart';
import 'package:aura_mobile/domain/services/llm_intent_classifier.dart';

/// Existing private on-device LiteRT engine. Its download/load behavior is
/// unchanged and it remains available when an online model is selected.
final liteRtServiceProvider = Provider<LiteRtService>((ref) => LiteRtService());

final providerApiKeyStoreProvider = Provider<ProviderApiKeyStore>(
  (ref) => ProviderApiKeyStore(),
);

final llmSelectionStoreProvider = Provider<LLMSelectionStore>(
  (ref) => LLMSelectionStore(),
);

final onlineLLMServiceProvider = Provider<OpenAICompatibleLLMService>(
  (ref) => OpenAICompatibleLLMService(),
);

/// Explicitly routes the same Aura orchestration flow to local or online AI.
/// Aura never sends content online unless the user selects an online model.
final llmRouterProvider = Provider<LLMRouter>((ref) {
  return LLMRouter(
    offlineService: ref.watch(liteRtServiceProvider),
    onlineService: ref.watch(onlineLLMServiceProvider),
    keyStore: ref.watch(providerApiKeyStoreProvider),
    selectionStore: ref.watch(llmSelectionStoreProvider),
  );
});

/// Stable abstraction consumed by chat, voice, documents, and orchestrator.
final llmServiceProvider = Provider<LLMService>(
  (ref) => ref.watch(llmRouterProvider),
);

final llmIntentClassifierProvider = Provider(
  (ref) => LLMIntentClassifier(ref.watch(llmServiceProvider)),
);

/// Download service for model files (foreground service + progress reporting).
final downloadServiceProvider = Provider<DownloadService>(
  (ref) => DownloadService(),
);

/// Free online text-to-image generation (Pollinations.ai — no key required).
final imageGenerationServiceProvider = Provider(
  (ref) => ImageGenerationService(),
);

// ═══ UTILITY MODEL ECOSYSTEM ═══════════════════════════════════════════════

/// Tracks availability of utility models (FunctionGemma, EmbeddingGemma) on disk.
/// Re-exported from utility_model_manager.dart for convenience.
// utilityModelManagerProvider is defined in utility_model_manager.dart

/// FunctionGemma service — classifies natural language into device action calls.
/// Progressive enhancement: active only when FunctionGemma model is downloaded.
final functionGemmaServiceProvider = Provider<FunctionGemmaService>((ref) {
  return FunctionGemmaService();
});

/// EmbeddingGemma service — produces 768-dim vectors for similarity lookups.
/// Not true semantic embeddings yet; see EmbeddingService docs.
/// Progressive enhancement: active only when EmbeddingGemma model is downloaded.
final embeddingServiceProvider = Provider<EmbeddingService>((ref) {
  return EmbeddingService();
});
