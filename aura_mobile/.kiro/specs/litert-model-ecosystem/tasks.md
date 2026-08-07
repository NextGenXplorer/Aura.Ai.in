# Implementation Plan: LiteRT Model Ecosystem

## Overview

This plan implements the expanded LiteRT model ecosystem for AURA Mobile. It adds 5 new chat LLMs (Phi-4-mini, Llama 3.2 1B/3B, Qwen3 4B, SmolLM 135M), 2 utility models with progressive enhancement (FunctionGemma for intent detection, EmbeddingGemma for semantic search), 4 MediaPipe vision tasks, and a restructured 3-section Model Catalog UI.

Work proceeds from foundational data types (ModelCategory, PromptTemplate, updated ModelInfo), through new services (UtilityModelManager, PromptTemplateFactory, FunctionGemmaService, EmbeddingService, MediaPipeTasksService), into service routing updates (IntentDetection, Memory, Document), and finally the UI and integration wiring.

The progressive enhancement pattern guarantees that existing regex-based intent detection and keyword-based search remain fully functional when utility models are absent. All utility model failures fall back silently.

Property-based tests are marked optional with `*`. Each task references specific requirements it fulfills.

## Tasks

- [ ] 1. Foundation: ModelCategory enum, PromptTemplate, and updated ModelInfo
  - [ ] 1.1 Add ModelCategory and PromptTemplate enums to ModelInfo
    - Edit `lib/domain/entities/model_info.dart`
    - Add `enum ModelCategory { chat, utility, vision }`
    - Add `enum PromptTemplate { gemma, chatml, phi, llama, smollm }`
    - Add `category` field (default `ModelCategory.chat`) and `promptTemplate` field (default `PromptTemplate.gemma`) to `ModelInfo`
    - Add `sizeFormatted` getter for human-readable sizes
    - Ensure all existing Gemma entries receive `category: ModelCategory.chat` and `promptTemplate: PromptTemplate.gemma` with zero breaking changes
    - _Requirements: 2.1, 2.2, 1.7_

  - [ ] 1.2 Add catalog filtering helpers
    - Add `getChatModels()`, `getUtilityModels()`, `getVisionModels()` functions that filter `modelCatalog` by category
    - _Requirements: 2.4_

  - [ ]* 1.3 Write property test for category exclusivity
    - **Property 7: Category Exclusivity** — every `ModelInfo` has exactly one `ModelCategory`; utility models are never selectable as chat
    - **Validates: Requirements 2.1, 2.8**

- [ ] 2. Expanded chat model catalog entries
  - [ ] 2.1 Add Phi-4-mini catalog entry
    - Add `ModelInfo` with id `phi4-mini`, sizeBytes ~2500 MB, minRamMB 4096, `InferenceSpeed.medium`, category `chat`, promptTemplate `chatml`
    - _Requirements: 1.1_

  - [ ] 2.2 Add Llama 3.2 1B catalog entry
    - Add `ModelInfo` with id `llama32-1b`, sizeBytes ~1000 MB, minRamMB 2048, `InferenceSpeed.fast`, category `chat`, promptTemplate `llama`
    - _Requirements: 1.2_

  - [ ] 2.3 Add Llama 3.2 3B catalog entry
    - Add `ModelInfo` with id `llama32-3b`, sizeBytes ~2000 MB, minRamMB 4096, `InferenceSpeed.medium`, category `chat`, promptTemplate `llama`
    - _Requirements: 1.3_

  - [ ] 2.4 Add Qwen3 4B catalog entry
    - Add `ModelInfo` with id `qwen3-4b`, sizeBytes ~3000 MB, minRamMB 4096, `InferenceSpeed.slow`, category `chat`, promptTemplate `chatml`
    - _Requirements: 1.4_

  - [ ] 2.5 Add SmolLM 135M catalog entry
    - Add `ModelInfo` with id `smollm-135m`, sizeBytes ~70 MB, minRamMB 1024, `InferenceSpeed.fast`, category `chat`, promptTemplate `smollm`
    - _Requirements: 1.5_

  - [ ] 2.6 Add FunctionGemma 270M utility catalog entry
    - Add `ModelInfo` with id `functiongemma-270m`, sizeBytes 270 MB, minRamMB 2048, category `utility`, description "Enhances intent detection — converts natural language to device action calls."
    - _Requirements: 3.1_

  - [ ] 2.7 Add EmbeddingGemma 300M utility catalog entry
    - Add `ModelInfo` with id `embeddinggemma-300m`, sizeBytes 308 MB, minRamMB 2048, category `utility`, description "Enables semantic search — find memories and documents by meaning, not just keywords."
    - _Requirements: 4.1_

  - [ ]* 2.8 Write unit tests for all new catalog entries
    - Verify each entry has correct id, category, promptTemplate, sizeBytes range, and minRamMB
    - _Requirements: 1.1–1.5, 3.1, 4.1_

- [ ] 3. UtilityModelManager (availability tracking)
  - [ ] 3.1 Create UtilityModelManager StateNotifier
    - Create `lib/core/services/utility_model_manager.dart`
    - Implement `UtilityModelState` with `isFunctionGemmaAvailable` and `isEmbeddingGemmaAvailable` booleans
    - Implement `UtilityModelManager extends StateNotifier<UtilityModelState>` with `checkAvailability()`, `onDownloadComplete(fileName)`, `onModelDeleted(fileName)`, and path getters
    - Define `utilityModelManagerProvider` as a Riverpod `StateNotifierProvider`
    - _Requirements: 3.9, 4.13, 7.2, 7.3, 7.7_

  - [ ]* 3.2 Write property test for availability flag consistency
    - **Property 8: Availability Flag Consistency** — after `onDownloadComplete`, flag is true; after `onModelDeleted`, flag is false; no app restart required
    - **Validates: Requirements 7.7, 7.3**

- [ ] 4. PromptTemplateFactory and LiteRtService integration
  - [ ] 4.1 Create PromptTemplateFactory
    - Create `lib/data/datasources/prompt_templates.dart`
    - Implement `PromptTemplateFactory.format(template, prompt, {systemPrompt})` with cases for Gemma, ChatML, Phi, Llama, SmolLM templates
    - Gemma: `<start_of_turn>user\n{system}\n\n{prompt}<end_of_turn>\n<start_of_turn>model\n`
    - ChatML: `<|im_start|>system\n{system}<|im_end|>\n<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n`
    - Llama: `<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{system}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n{prompt}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n`
    - _Requirements: 1.7_

  - [ ] 4.2 Integrate PromptTemplateFactory into LiteRtService
    - Modify `lib/data/datasources/litert_service.dart` to use `PromptTemplateFactory.format()` based on the loaded model's `promptTemplate` field instead of hardcoded `formatGemmaPrompt()`
    - Keep `formatGemmaPrompt()` as a backward-compatible static method
    - _Requirements: 1.6, 1.7_

  - [ ]* 4.3 Write property test for prompt template correctness
    - **Property 6: Prompt Template Correctness** — each template produces exactly its expected markers and no markers from other templates
    - **Validates: Requirements 1.7**

  - [ ]* 4.4 Write unit tests for PromptTemplateFactory
    - Test each template variant with and without system prompt; verify correct markers, no cross-contamination
    - _Requirements: 1.7_

- [ ] 5. FunctionGemmaService
  - [ ] 5.1 Create FunctionGemmaService
    - Create `lib/data/datasources/function_gemma_service.dart`
    - Implement `loadModel(path)` with concurrent/hot-swap detection
    - Implement `classifyIntent(message)` returning `Map<String, dynamic>?` with 500ms timeout
    - Implement `_parseResult(output)` validating JSON with `name` + `arguments` keys
    - Define `functionToIntentMap` mapping all 16 function names to IntentType strings
    - _Requirements: 3.4, 3.5, 3.6, 3.7, 5.2, 5.3, 5.8_

  - [ ] 5.2 Implement hot-swap fallback for FunctionGemma
    - Implement `_runHotSwap(message)`: unload chat → load FunctionGemma → infer → unload → reload chat
    - Implement message buffering during hot-swap and brief loading indicator
    - _Requirements: 5.3, 5.5, 5.6, 5.7_

  - [ ]* 5.3 Write unit tests for FunctionGemma JSON parsing
    - Test valid JSON, missing `name` field, invalid JSON, empty string, extra whitespace, and function-to-intent mapping
    - _Requirements: 3.4, 3.5, 3.6_

  - [ ]* 5.4 Write property test for silent fallback (FunctionGemma)
    - **Property 3: Silent Fallback — FunctionGemma** — if inference returns null, final intent MUST equal regex result
    - **Validates: Requirements 3.6**

- [ ] 6. EmbeddingService
  - [ ] 6.1 Create EmbeddingService
    - Create `lib/data/datasources/embedding_service.dart`
    - Implement `loadModel(path)` for dedicated embedding pipeline (separate from chat)
    - Implement `embed(text)` returning `List<double>` (768-dim) or empty list on failure
    - Implement static `cosineSimilarity(a, b)` returning value in [-1.0, 1.0] or 0.0 for edge cases
    - _Requirements: 4.4, 4.5, 4.12, 4.14_

  - [ ] 6.2 Implement background re-embedding on first download
    - Schedule isolate via `compute()` to iterate un-embedded memories/chunks in batches of 50
    - Generate embeddings and update DB rows without blocking UI
    - _Requirements: 4.8, 4.9_

  - [ ]* 6.3 Write property test for cosine similarity bounds
    - **Property 10: Cosine Similarity Bounds** — returns [-1.0, 1.0] for non-empty equal-length vectors; 0.0 for empty or mismatched
    - **Validates: Requirements 4.5**

  - [ ]* 6.4 Write unit tests for EmbeddingService
    - Test identical, orthogonal, opposite, empty, and mismatched vectors
    - Test embed returns empty list when model not loaded
    - _Requirements: 4.5, 4.10_

  - [ ]* 6.5 Write property test for silent fallback (EmbeddingGemma)
    - **Property 4: Silent Fallback — EmbeddingGemma** — if embed throws or returns empty, retrieval falls back to keyword search with no user-visible error
    - **Validates: Requirements 4.10**

- [ ] 7. Updated IntentDetectionService routing
  - [ ] 7.1 Add FunctionGemma progressive routing to IntentDetectionService
    - Modify `lib/domain/services/intent_detection_service.dart`
    - Inject `UtilityModelManager` and `FunctionGemmaService` dependencies
    - Before regex: check `isFunctionGemmaAvailable` → call `classifyIntent(message)` → map result → return or fall through to regex
    - Zero behavioral change when FunctionGemma is not downloaded
    - _Requirements: 3.2, 3.3, 3.5, 3.6, 3.8_

  - [ ]* 7.2 Write property test for intent detection invariant
    - **Property 1: Progressive Enhancement — Intent Detection Invariant** — when `isFunctionGemmaAvailable == false`, results are identical to current regex implementation
    - **Validates: Requirements 3.2**

- [ ] 8. Updated MemoryService routing
  - [ ] 8.1 Add semantic search routing to MemoryService
    - Modify `lib/domain/services/memory_service.dart`
    - Inject `UtilityModelManager` and `EmbeddingService`
    - In `saveMemory()`: generate embedding if EmbeddingGemma available, store in `Memory.embedding`
    - In `retrieveRelevantMemories()`: if available, embed query → cosine similarity search → top-N; else keyword fallback
    - On exception: log warning, fall back to keyword search
    - _Requirements: 4.2, 4.4, 4.5, 4.10, 4.11_

  - [ ] 8.2 Add embedding column to Memory database schema
    - Add `ALTER TABLE memories ADD COLUMN embedding BLOB` migration
    - Store embeddings as serialized `Float32List` BLOBs (768 * 4 = 3072 bytes)
    - _Requirements: 4.4, 4.8_

  - [ ]* 8.3 Write property test for semantic search invariant (Memory)
    - **Property 2: Progressive Enhancement — Semantic Search Invariant** — when `isEmbeddingGemmaAvailable == false`, results are identical to keyword-based implementation
    - **Validates: Requirements 4.2**

- [ ] 9. Updated DocumentService routing
  - [ ] 9.1 Add semantic search routing to DocumentService
    - Modify `lib/domain/services/document_service.dart`
    - Inject `UtilityModelManager` and `EmbeddingService`
    - In `_processChunks()`: generate embedding if available, store in `DocumentChunk.embedding`
    - In `retrieveRelevantContext()`: if available, embed query → cosine similarity → top-N; else keyword fallback
    - On exception: log warning, fall back to keyword search
    - _Requirements: 4.3, 4.6, 4.7, 4.10, 4.11_

  - [ ] 9.2 Add embedding column to DocumentChunk database schema
    - Add `ALTER TABLE document_chunks ADD COLUMN embedding BLOB` migration
    - _Requirements: 4.6, 4.9_

  - [ ]* 9.3 Write property test for semantic search invariant (Document)
    - **Property 2 (continued)** — when `isEmbeddingGemmaAvailable == false`, `retrieveRelevantContext()` results are identical to keyword scoring
    - **Validates: Requirements 4.3**

- [ ] 10. MediaPipe Tasks integration
  - [ ] 10.1 Add google_mlkit_* packages to pubspec.yaml
    - Add `google_mlkit_face_detection: ^0.12.0`
    - Add `google_mlkit_object_detection: ^0.14.0`
    - Add `google_mlkit_selfie_segmentation: ^0.6.0`
    - Add `google_mlkit_pose_detection: ^0.12.0`
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

  - [ ] 10.2 Create MediaPipeTasksService
    - Create `lib/core/services/mediapipe_tasks_service.dart`
    - Implement `MediaPipeResult` structured result class
    - Implement `detectFaces(File)`, `detectObjects(File)`, `removeBackground(File)`, `detectPose(File)`
    - Each method returns `MediaPipeResult` with success/failure, summary, and structured data
    - Handle camera permission denial with actionable error message
    - Handle unsupported image format with descriptive error
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.6, 6.9, 6.10_

  - [ ] 10.3 Add MediaPipe regex triggers to IntentDetectionService
    - Add regex patterns: "scan this", "what is this", "identify this", "what is in this photo" → object detection; "detect face", "find faces" → face detection; "remove background" → segmentation; "detect pose", "analyze posture" → pose estimation
    - _Requirements: 6.7_

  - [ ] 10.4 Add MediaPipe functions to FunctionGemma vocabulary
    - Ensure `functionToIntentMap` includes `detectFaces`, `detectObjects`, `removeBackground`, `detectPose` → `scanImage`
    - _Requirements: 6.8_

  - [ ] 10.5 Wire MediaPipeTasksService into OrchestratorService
    - Route `scanImage` intent to appropriate MediaPipe task based on trigger phrase or FunctionGemma function name
    - Display results in chat interface
    - _Requirements: 6.6_

  - [ ]* 10.6 Write unit tests for MediaPipeTasksService
    - Test each task returns structured `MediaPipeResult` with expected fields
    - Test error cases return failure results with actionable messages
    - _Requirements: 6.6, 6.9, 6.10_

- [ ] 11. Updated Model Selector UI (3-section catalog)
  - [ ] 11.1 Restructure Model Catalog into 3 sections
    - Modify `lib/presentation/screens/model_catalog_screen.dart` (or equivalent)
    - Render three scrollable sections with headers: "Chat Models", "Utility Models", "Vision Models"
    - Chat section: existing model selection + download behavior
    - Utility section: model name, download size, one-sentence description, download/delete button only (no select)
    - Vision section: placeholder text "Vision LLM models (SmolVLM, FastVLM) are coming in a future update."
    - _Requirements: 2.4, 2.5, 2.6, 2.7, 2.8, 8.1, 8.2, 8.3_

  - [ ] 11.2 Add "Active" badge for downloaded utility models
    - When utility model file is present on disk (from `UtilityModelState`), show "Active" badge
    - _Requirements: 2.6_

  - [ ] 11.3 Add disk space check and download info for utility models
    - Display file size in MB, estimated download time at 10 Mbps, and available disk space
    - Disable download button with message when space insufficient (file size + 100 MB buffer)
    - _Requirements: 7.4, 7.5_

  - [ ]* 11.4 Write widget tests for categorized catalog UI
    - Verify three sections render, utility models show descriptions, utility models cannot be selected as chat, vision shows placeholder, downloaded utility shows Active badge
    - _Requirements: 2.4, 2.5, 2.6, 2.7, 2.8, 8.1, 8.2, 8.3_

- [ ] 12. Integration wiring (providers, app startup, download hooks)
  - [ ] 12.1 Register new providers in ai_providers.dart
    - Add `utilityModelManagerProvider` (StateNotifier)
    - Add `functionGemmaServiceProvider` with unloadChat/reloadChat callbacks
    - Add `embeddingServiceProvider` (dedicated pipeline)
    - Add `mediaPipeTasksServiceProvider`
    - _Requirements: 5.1, 5.4_

  - [ ] 12.2 Wire app startup availability check
    - On app launch, call `UtilityModelManager.checkAvailability()` to scan disk for model files
    - If FunctionGemma available, pre-load model via `FunctionGemmaService.loadModel(path)`
    - If EmbeddingGemma available, load via `EmbeddingService.loadModel(path)`
    - _Requirements: 3.9, 4.13, 7.2_

  - [ ] 12.3 Wire download completion hooks
    - When DownloadService completes a utility model download, call `UtilityModelManager.onDownloadComplete(fileName)`
    - When delete action completes, call `UtilityModelManager.onModelDeleted(fileName)`
    - Ensure progressive enhancement takes effect immediately without app restart
    - _Requirements: 7.3, 7.7, 7.8, 3.8, 4.11_

  - [ ] 12.4 Wire concurrent download support
    - Ensure DownloadService supports downloading utility models while chat model is loaded without interrupting chat session
    - _Requirements: 7.6_

  - [ ] 12.5 Implement runtime concurrent loading detection
    - At startup, attempt secondary inference instance; cache result for session
    - Route FunctionGemma to concurrent or hot-swap based on detection
    - _Requirements: 5.2, 5.3, 5.8_

  - [ ]* 12.6 Write property test for model isolation
    - **Property 5: Model Isolation** — loading/unloading utility model MUST NOT unload or interfere with active chat model (except explicit hot-swap)
    - **Validates: Requirements 5.1, 5.4**

  - [ ]* 12.7 Write property test for hot-swap atomicity
    - **Property 9: Hot-Swap Atomicity** — chat model MUST be fully reloaded before buffered messages are processed; zero message loss
    - **Validates: Requirements 5.6**

  - [ ]* 12.8 Write integration test for end-to-end progressive enhancement
    - With mocked services, verify: download utility → flag true → next call uses enhanced path; delete → flag false → next call uses fallback
    - _Requirements: 3.8, 4.11, 7.7_

- [ ] 13. Final checkpoint — full feature integrated
  - Verify all tests pass, all services properly wired, progressive enhancement working end-to-end. Ask user if questions arise.

## Notes

- Tasks marked with `*` are optional property/unit test tasks and can be skipped for a faster MVP.
- Each task references specific requirement sub-clauses for traceability.
- The progressive enhancement pattern ensures zero breaking changes: when utility models are absent, all behavior is identical to the current production app.
- All new `ModelInfo` fields have default values — existing code compiles without modification.
- MediaPipe vision tasks require zero user downloads (model weights bundled in SDK packages).
- The EmbeddingService runs on a dedicated pipeline that never interferes with the active chat model.
- FunctionGemma uses concurrent loading when possible; falls back to hot-swap with message buffering.
- Database migrations (embedding columns) are additive and non-breaking.

## Task Dependency Graph

```json
{
  "waves": [
    {
      "id": 0,
      "description": "Foundation types and enums",
      "tasks": ["1.1", "1.2"]
    },
    {
      "id": 1,
      "description": "Catalog entries and UtilityModelManager",
      "tasks": ["1.3", "2.1", "2.2", "2.3", "2.4", "2.5", "2.6", "2.7", "3.1"]
    },
    {
      "id": 2,
      "description": "Prompt templates and availability tests",
      "tasks": ["2.8", "3.2", "4.1", "4.2"]
    },
    {
      "id": 3,
      "description": "Core services: FunctionGemma, EmbeddingService, PromptTemplate tests",
      "tasks": ["4.3", "4.4", "5.1", "6.1"]
    },
    {
      "id": 4,
      "description": "Service internals: hot-swap, re-embedding, parsing tests",
      "tasks": ["5.2", "5.3", "5.4", "6.2", "6.3", "6.4", "6.5"]
    },
    {
      "id": 5,
      "description": "Service routing updates",
      "tasks": ["7.1", "7.2", "8.1", "8.2", "9.1", "9.2"]
    },
    {
      "id": 6,
      "description": "Service routing tests and MediaPipe",
      "tasks": ["8.3", "9.3", "10.1", "10.2", "10.3", "10.4"]
    },
    {
      "id": 7,
      "description": "MediaPipe wiring and UI",
      "tasks": ["10.5", "10.6", "11.1", "11.2", "11.3"]
    },
    {
      "id": 8,
      "description": "UI tests and integration wiring",
      "tasks": ["11.4", "12.1", "12.2", "12.3", "12.4", "12.5"]
    },
    {
      "id": 9,
      "description": "Integration tests and final verification",
      "tasks": ["12.6", "12.7", "12.8", "13"]
    }
  ],
  "dependencies": {
    "1.2": ["1.1"],
    "1.3": ["1.1"],
    "2.1": ["1.1"],
    "2.2": ["1.1"],
    "2.3": ["1.1"],
    "2.4": ["1.1"],
    "2.5": ["1.1"],
    "2.6": ["1.1"],
    "2.7": ["1.1"],
    "2.8": ["2.1", "2.2", "2.3", "2.4", "2.5", "2.6", "2.7"],
    "3.1": ["1.1"],
    "3.2": ["3.1"],
    "4.1": ["1.1"],
    "4.2": ["4.1"],
    "4.3": ["4.1"],
    "4.4": ["4.1"],
    "5.1": ["3.1", "4.1"],
    "5.2": ["5.1"],
    "5.3": ["5.1"],
    "5.4": ["5.1", "7.1"],
    "6.1": ["3.1"],
    "6.2": ["6.1", "8.2", "9.2"],
    "6.3": ["6.1"],
    "6.4": ["6.1"],
    "6.5": ["6.1", "8.1"],
    "7.1": ["3.1", "5.1"],
    "7.2": ["7.1"],
    "8.1": ["3.1", "6.1"],
    "8.2": ["8.1"],
    "8.3": ["8.1"],
    "9.1": ["3.1", "6.1"],
    "9.2": ["9.1"],
    "9.3": ["9.1"],
    "10.1": [],
    "10.2": ["10.1"],
    "10.3": ["10.2", "7.1"],
    "10.4": ["5.1", "10.2"],
    "10.5": ["10.2", "7.1"],
    "10.6": ["10.2"],
    "11.1": ["1.2", "3.1"],
    "11.2": ["11.1", "3.1"],
    "11.3": ["11.1"],
    "11.4": ["11.1", "11.2", "11.3"],
    "12.1": ["3.1", "5.1", "6.1", "10.2"],
    "12.2": ["12.1", "3.1"],
    "12.3": ["12.1", "3.1"],
    "12.4": ["12.1"],
    "12.5": ["5.1", "5.2", "12.1"],
    "12.6": ["12.1", "12.2"],
    "12.7": ["5.2", "12.5"],
    "12.8": ["12.2", "12.3", "7.1", "8.1", "9.1"],
    "13": ["12.6", "12.7", "12.8", "11.4", "10.5", "10.6"]
  }
}
```
