# Implementation Plan: Multi-Engine AI Models

## Overview

This plan implements the dual-engine architecture for AURA Mobile in Dart/Flutter. Work
starts at the data layer (the `AIEngine` enum and the extended `ModelInfo` entity plus
catalog), preserves the existing GGUF engine, adds the new `LiteRtService`, then introduces
the `EngineRouter` that sits behind the unchanged `LLMService` interface. Function calling,
LiteRT download/storage handling, the model-selector UI, the split-ABI build, and the final
provider wiring follow. Each step builds on prior steps and ends by integrating into the app
so no orchestrator/UI code is left disconnected.

Property-based tests (one per design property) are added next to the code they validate and
are marked optional with `*`. The existing GGUF/Qwen path and the `OrchestratorService`
contract remain unchanged except for the new function-calling branch.

## Tasks

- [x] 1. Add engine enum and extend the ModelInfo entity
  - [x] 1.1 Create AIEngine and InferenceSpeed enums
    - Create `lib/domain/entities/ai_engine.dart` with `enum AIEngine { gguf, litert }` and a static `fromId(String)` that throws on unknown values
    - Add `enum InferenceSpeed { fast, medium, slow }` in the same file
    - _Requirements: 1.1, 4.2_

  - [x] 1.2 Extend ModelInfo with engine and capability fields
    - Edit `lib/domain/entities/model_info.dart` to add `engine` (default `AIEngine.gguf`), `supportsToolCalling` (default false), `supportsVision` (default false), `inferenceSpeed` (default `InferenceSpeed.medium`), and `minRamMB`
    - Add `double get sizeMB => sizeBytes / (1024 * 1024)` and `bool get qualifiesFastBadge`
    - Keep the default `engine` as `gguf` so existing Qwen entries stay `gguf` without edits
    - _Requirements: 4.1, 4.2, 4.3_

  - [x]* 1.3 Write unit tests for ModelInfo defaults and AIEngine.fromId
    - Verify default field values, `sizeMB`/`qualifiesFastBadge` getters, and that `AIEngine.fromId` throws on unknown ids
    - _Requirements: 1.1, 4.1, 4.2, 4.3_

- [x] 2. Expand the model catalog
  - [x] 2.1 Add Gemma catalog entries and annotate engines
    - Edit the `modelCatalog` list in `lib/domain/entities/model_info.dart`
    - Set `engine: AIEngine.gguf` explicitly on the four Qwen 2.5 entries and assign each a `minRamMB`
    - Add Gemma 3 1B (`litert`, fast), Gemma 3n E2B (`litert`, medium), Gemma 4 E2B (`litert`, tool-calling true, medium), Gemma 4 E4B (`litert`, tool-calling true, slow) with unique ids, valid `sizeBytes`, and `minRamMB`
    - _Requirements: 4.4, 4.5, 4.6, 4.7, 4.8, 4.9, 4.10_

  - [x]* 2.2 Write property test for catalog invariants
    - **Property 10: Catalog invariants**
    - **Validates: Requirements 4.1, 4.2, 4.8, 4.9, 4.10**

  - [x]* 2.3 Write unit tests for required Gemma catalog entries
    - Assert the four Gemma entries exist with the expected engine and tool-calling flags
    - _Requirements: 4.4, 4.5, 4.6, 4.7_

- [x] 3. Preserve the GGUF engine as the `gguf` branch
  - [x] 3.1 Confirm LLMServiceImpl conforms as the GGUF engine
    - In `lib/data/datasources/llm_service.dart`, ensure `LLMServiceImpl` implements the full `LLMService` interface unchanged, retaining ChatML formatting, `_cleanModelOutput`, and file-name-based `ModelTier` detection
    - _Requirements: 2.1, 2.2, 2.3, 2.6_

  - [x]* 3.2 Write property test for GGUF output cleaning
    - **Property 4: GGUF output cleaning removes stop markers**
    - **Validates: Requirements 2.3**

  - [x]* 3.3 Write property test for GGUF model tier mapping
    - **Property 5: GGUF model tier mapping**
    - **Validates: Requirements 2.6**

- [x] 4. Implement the LiteRtService (LiteRT engine)
  - [x] 4.1 Add flutter_gemma and create the LiteRtService skeleton
    - Add the `flutter_gemma` dependency to `pubspec.yaml`
    - Create `lib/data/datasources/litert_service.dart` with `LiteRtService implements LLMService`: hold the plugin handle and `InferenceModel?`, implement `initialize` (cheap plugin handle prep), `isModelLoaded`, `modelTier` (from a catalog-supplied tier field with a setter)
    - _Requirements: 3.1, 8.4_

  - [x] 4.2 Implement LiteRtService.loadModel with validation and timeout
    - Validate the `.task` / `.litertlm` extension; on unsupported format throw `ValidationException.unsupportedFormat` and leave any previously loaded model loaded
    - Install via `ModelFileManager`, create the `InferenceModel` with a 30-second timeout; on failure clear the model and throw a load/init error reporting `isModelLoaded == false`
    - _Requirements: 3.3, 3.6, 3.7, 3.8, 3.9, 10.1_

  - [x] 4.3 Implement Gemma prompt formatting and streaming chat
    - Add `formatGemmaPrompt` producing the `<start_of_turn>user … <end_of_turn><start_of_turn>model` template (embedding the system prompt when present, never ChatML markers)
    - Implement `chat` to create a session, submit the formatted prompt, and yield tokens as a stream that closes on completion; throw a "no model loaded" error when no model is loaded
    - _Requirements: 3.2, 3.4, 3.5, 3.10_

  - [x]* 4.4 Write property test for LiteRT load state tracking
    - **Property 6: LiteRT load state tracking**
    - **Validates: Requirements 3.3, 3.6**

  - [x]* 4.5 Write property test for Gemma prompt formatting
    - **Property 7: Gemma prompt formatting**
    - **Validates: Requirements 3.4**

  - [x]* 4.6 Write property test for LiteRT response streaming round-trip
    - **Property 8: LiteRT response streaming round-trip**
    - **Validates: Requirements 3.5**

  - [x]* 4.7 Write property test for LiteRT error conditions
    - **Property 9: LiteRT error conditions**
    - **Validates: Requirements 3.7, 3.8, 3.9, 3.10**

  - [x]* 4.8 Write integration test for flutter_gemma delegation
    - With a mocked `flutter_gemma`, verify `LiteRtService` routes inference through the package
    - _Requirements: 3.2_

- [x] 5. Implement the Engine_Router
  - [x] 5.1 Create the EngineRouter skeleton
    - Create `lib/data/datasources/engine_router.dart` with `EngineRouter implements LLMService`, holding the GGUF engine, the LiteRtService, the `DeviceService`, and the active `ModelInfo?`
    - Implement `initialize` (GGUF eager, LiteRT lazy), the `_active` engine resolver, `isModelLoaded`, and `modelTier`
    - _Requirements: 1.2, 1.6, 1.7_

  - [x] 5.2 Implement loadModelInfo with RAM gate and commit-on-success
    - Run the pre-flight RAM check via `DeviceService` before any engine load: undeterminable RAM → device-compatibility error; `minRamMB > deviceRamMB` → memory-insufficiency error stating required vs available; otherwise proceed
    - Select the engine by the model's engine field, delegate the load, and set the active model only after the engine reports `isModelLoaded == true`; on any failure return an error and retain the previous active model
    - Implement `loadModel(String)` to resolve the `ModelInfo` from the catalog by file name (restart-recovery path)
    - _Requirements: 1.4, 1.5, 8.1, 8.2, 8.4, 8.5, 8.6, 10.2, 10.6_

  - [x] 5.3 Implement delegating chat with no-model and chat-failure handling
    - Delegate `chat` to the active engine; when none is active return a "no model loaded" error and leave the active model unset
    - Wrap LiteRT chat errors so a failure returns a handled chat-failure error without crashing and keeps the active model loaded
    - Keep `gguf` models selectable and loadable while LiteRT is unavailable
    - _Requirements: 1.3, 1.8, 1.9, 2.2, 10.3, 10.4, 10.5_

  - [x]* 5.4 Write property test for active-engine delegation
    - **Property 1: Active-engine delegation**
    - **Validates: Requirements 1.3, 1.6, 1.7, 1.9, 2.2**

  - [x]* 5.5 Write property test for engine selection committing only on success
    - **Property 2: Engine selection commits only on success**
    - **Validates: Requirements 1.4**

  - [x]* 5.6 Write property test for failed/blocked load preserving the active model
    - **Property 3: Failed or blocked load preserves the previous active model**
    - **Validates: Requirements 1.5, 2.7, 6.8, 8.5, 10.2, 10.6**

  - [x]* 5.7 Write property test for the RAM gate decision
    - **Property 25: RAM gate decides loading**
    - **Validates: Requirements 8.1, 8.2, 8.3, 8.6**

  - [x]* 5.8 Write property test for LiteRT tier from metadata
    - **Property 26: LiteRT model tier from metadata**
    - **Validates: Requirements 8.4**

  - [x]* 5.9 Write property test for GGUF availability independence
    - **Property 27: GGUF availability is independent of LiteRT**
    - **Validates: Requirements 10.3**

  - [x]* 5.10 Write property test for contained chat failure
    - **Property 28: Chat failure is contained and non-destructive**
    - **Validates: Requirements 10.4, 10.5**

  - [x]* 5.11 Write unit tests for the chat signature boundaries
    - Verify `chat` accepts `maxTokens >= 1` and `temperature` in `[0.0, 2.0]`
    - _Requirements: 1.8_

- [x] 6. Checkpoint - engine layer complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement native function calling
  - [x] 7.1 Create function-calling data types
    - Create `lib/features/orchestrator/tool_definition.dart` with `ToolDefinition`, `ToolParameter` (name + required), `FunctionCallRequest`, and the sealed `FunctionCallResult` hierarchy (`Parsed`, `Unparseable`, `UnknownTool`, `MissingParams`)
    - _Requirements: 5.1, 5.2_

  - [x] 7.2 Implement the FunctionCallCoordinator
    - Create `lib/features/orchestrator/function_call_coordinator.dart` with `parse(raw, knownTools)` and `validate(request)` covering unparseable input, unknown tool, and missing required parameters
    - _Requirements: 5.2, 5.5, 5.6, 5.7_

  - [x] 7.3 Wire the orchestrator to use function calling for capable models
    - In `lib/features/orchestrator/orchestrator_service.dart`, when the active model has `supportsToolCalling == true` provide the full tool-definition set on each inference call, then parse/validate/dispatch to the existing tool handlers; otherwise keep the existing rule-based intent detection
    - _Requirements: 5.1, 5.3, 5.4, 2.5_

  - [x]* 7.4 Write property test for tool definitions provided to capable models
    - **Property 11: Tool definitions provided to capable models**
    - **Validates: Requirements 5.1**

  - [x]* 7.5 Write property test for function-call parse round-trip
    - **Property 12: Function-call parse round-trip**
    - **Validates: Requirements 5.2**

  - [x]* 7.6 Write property test for valid function-call dispatch
    - **Property 13: Valid function-call dispatch**
    - **Validates: Requirements 5.3**

  - [x]* 7.7 Write property test for tool-calling vs rule-based routing
    - **Property 14: Tool-calling vs rule-based routing**
    - **Validates: Requirements 2.5, 5.4**

  - [x]* 7.8 Write property test for function-call error conditions
    - **Property 15: Function-call error conditions invoke no handler**
    - **Validates: Requirements 5.5, 5.6, 5.7**

- [x] 8. Checkpoint - function calling complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Extend ModelManager for the LiteRT format
  - [x] 9.1 Branch download recognition and validation on engine
    - In `lib/data/datasources/model_manager.dart`, branch `isModelDownloaded`, `verifyAndCleanupModel`, and integrity checks on `model.engine`: keep the GGUF magic-byte check; for `litert` validate the `.task` / `.litertlm` container header and size; keep `getModelPath` file-name based
    - _Requirements: 2.4, 7.7_

  - [x]* 9.2 Write property test for download recognition by file presence
    - **Property 23: Download recognition by file presence**
    - **Validates: Requirements 2.4, 7.7**

- [x] 10. Implement LiteRT download management
  - [x] 10.1 Handle LiteRT downloads through the existing pipeline
    - In `lib/presentation/providers/model_selector_provider.dart`, route `litert` downloads through the existing download pipeline: store at the catalog file name, report monotonic non-decreasing progress in `[0,1]`, retry up to 3 total attempts, remove the partial file and report failure after exhaustion, mark downloaded on completion, reduce reported storage on delete, and block the download with an insufficient-storage error when disk space is below the file size
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.8_

  - [x]* 10.2 Write property test for download destination file name
    - **Property 19: Download destination matches catalog file name**
    - **Validates: Requirements 7.1**

  - [x]* 10.3 Write property test for bounded monotonic progress
    - **Property 20: Download progress is bounded and monotonic**
    - **Validates: Requirements 7.2**

  - [x]* 10.4 Write property test for download retry exhaustion
    - **Property 21: Download retry exhaustion**
    - **Validates: Requirements 7.4, 7.5**

  - [x]* 10.5 Write property test for delete reducing reported storage
    - **Property 22: Delete reduces reported storage by file size**
    - **Validates: Requirements 7.6**

  - [x]* 10.6 Write property test for insufficient disk space blocking download
    - **Property 24: Insufficient disk space blocks download**
    - **Validates: Requirements 7.8**

  - [x]* 10.7 Write unit test for download-complete marking
    - Verify a fully received file marks the model as downloaded
    - _Requirements: 7.3_

- [x] 11. Update the Model Selector UI
  - [x] 11.1 Implement engine grouping and badge/support derivation
    - Create `lib/presentation/providers/model_catalog_grouping.dart` with pure helpers: partition the catalog into one group per engine value, derive the qualifying capability badge set (tool-calling, vision, fast), and compute the `supported` flag as `deviceRamMB >= minRamMB`
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 8.3_

  - [x] 11.2 Render grouped models, badges, sizes, and selection wiring
    - In `lib/presentation/pages/model_selector_screen.dart`, render a heading per engine group, every qualifying capability badge per model, and each model's download size (MB) and minimum RAM (MB)
    - Disable selection and show "not supported" when `minRamMB > deviceRamMB`; on select call `router.loadModelInfo(model)`, and on failure show a load-failure message while retaining the previous selected model
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 8.3_

  - [x]* 11.3 Write property test for engine grouping partition
    - **Property 16: Engine grouping partitions the catalog**
    - **Validates: Requirements 6.1**

  - [x]* 11.4 Write property test for capability badge derivation
    - **Property 17: Capability badge derivation**
    - **Validates: Requirements 6.2, 6.3, 6.4, 6.5**

  - [x]* 11.5 Write property test for model card size and RAM display
    - **Property 18: Model card shows size and RAM**
    - **Validates: Requirements 6.6**

  - [x]* 11.6 Write unit test for select-to-load wiring
    - Verify selecting a downloaded model requests a load through the engine indicated by its engine field
    - _Requirements: 6.7_

- [x] 12. Configure the split-ABI Android build
  - [x] 12.1 Enable per-ABI APKs and exclude LiteRT model files
    - Add a `splits { abi { … } }` block in `android/app/build.gradle.kts` so each package contains only its architecture's native binaries; ensure no LiteRT model files are bundled as assets (downloaded post-install only)
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

  - [x]* 12.2 Write build/smoke assertion for split config and no bundled models
    - Assert the split-ABI configuration is present and that the build output bundles zero LiteRT model files
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

- [x] 13. Wire the Engine_Router into the application
  - [x] 13.1 Bind EngineRouter as the LLMService provider
    - In `lib/core/providers/ai_providers.dart`, construct the `EngineRouter` with both engines and the `DeviceService`, and bind it as the `LLMService` consumed by the `OrchestratorService` and chat flow; keep LiteRT initialization lazy
    - _Requirements: 1.2, 1.3, 10.3_

  - [x]* 13.2 Write integration test for end-to-end engine switching
    - With mocked engines, verify loading a `gguf` then a `litert` model routes `chat`/`modelTier` to the correct engine and that a failed switch preserves the prior active model
    - _Requirements: 1.3, 1.4, 1.5_

- [x] 14. Final checkpoint - full feature integrated
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional test tasks and can be skipped for a faster MVP.
- Each task references specific requirement sub-clauses for traceability.
- Property tests are placed next to the code they validate; each implements exactly one design property and is tagged `Feature: multi-engine-ai-models, Property {n}` per the design's testing strategy.
- The existing GGUF/Qwen path and the `LLMService` interface stay unchanged; the only orchestrator change is the new function-calling branch.
- Requirements verified by example/integration/smoke tests instead of properties: 1.1, 1.2, 1.8, 2.1, 3.1, 3.2, 4.3–4.7, 6.7, 7.3, 9.1–9.4, 10.1.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "3.1", "7.1", "12.1"] },
    { "id": 1, "tasks": ["1.2", "4.1", "3.2", "3.3", "7.2", "12.2"] },
    { "id": 2, "tasks": ["2.1", "1.3", "4.2", "9.1", "11.1"] },
    { "id": 3, "tasks": ["2.2", "2.3", "4.3", "9.2", "10.1", "7.3"] },
    { "id": 4, "tasks": ["4.4", "4.5", "4.6", "4.7", "4.8", "5.1", "7.4", "7.5", "7.6", "7.7", "7.8", "10.2", "10.3", "10.4", "10.5", "10.6", "10.7"] },
    { "id": 5, "tasks": ["5.2"] },
    { "id": 6, "tasks": ["5.3", "11.2"] },
    { "id": 7, "tasks": ["5.4", "5.5", "5.6", "5.7", "5.8", "5.9", "5.10", "5.11", "11.3", "11.4", "11.5", "11.6", "13.1"] },
    { "id": 8, "tasks": ["13.2"] }
  ]
}
```
