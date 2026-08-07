# Requirements Document

## Introduction

AURA Mobile is an offline, on-device AI assistant that currently runs GGUF-format
large language models (the Qwen 2.5 family) through a single inference engine called
RunAnywhere, a wrapper around fllama/llama.cpp. This feature adds support for a second,
fundamentally different inference engine so the application can also run Google Gemma
models distributed in the LiteRT/MediaPipe format (`.task` / `.litertlm`), accessed
through the `flutter_gemma` package.

The two engines use different model file formats and different prompt templates
(ChatML `<|im_start|>` for GGUF/Qwen versus Gemma `<start_of_turn>` for LiteRT). The
newer Gemma models additionally support native function/tool calling, which is more
accurate than the existing rule-based intent detection.
wh
The core architectural goal is a dual-engine design that introduces an engine
abstraction layer behind the existing `LLMService` interface, so the orchestrator and
the rest of the application are unaffected. The existing RunAnywhere/GGUF engine and the
existing Qwen experience for current users MUST remain fully functional and unchanged.

The feature must also remain safe on real devices: the application must manage APK size,
guard against insufficient RAM, preserve backward compatibility for existing users, and
fall back gracefully when the LiteRT engine cannot initialize.

## Glossary

- **AURA**: The offline on-device AI assistant mobile application described by this document.
- **Inference_Engine**: A software component that loads an AI model and produces text output from a prompt. AURA supports two: the GGUF engine and the LiteRT engine.
- **GGUF_Engine**: The existing inference engine identified by the value `gguf`, implemented by RunAnywhere over fllama/llama.cpp, supporting GGUF-format models such as the Qwen 2.5 family.
- **LiteRT_Engine**: The new inference engine identified by the value `litert`, wrapping the `flutter_gemma` package over Google LiteRT-LM / MediaPipe LLM Inference, supporting `.task` and `.litertlm` model files.
- **AIEngine**: An enumeration of engine identifiers with exactly the values `gguf` and `litert`.
- **LLMService**: The existing abstract interface exposing `initialize`, `loadModel`, `chat`, `isModelLoaded`, and `modelTier`, consumed by the Orchestrator.
- **Engine_Router**: A component that implements the `LLMService` interface and delegates each call to the Inference_Engine associated with the currently active model.
- **LiteRtService**: A component that implements the `LLMService` interface by wrapping the `flutter_gemma` package, serving as the LiteRT_Engine.
- **ModelInfo**: The existing entity describing a catalog model, extended by this feature with an engine field and capability fields.
- **Model_Catalog**: The list of `ModelInfo` entries presented to the user for download and selection.
- **ModelTier**: The existing enumeration with values `small`, `medium`, and `large`, used to adapt prompt complexity to model size.
- **Orchestrator**: The existing `OrchestratorService` that routes user messages and calls `LLMService.chat` for all AI inference.
- **Model_Selector**: The existing UI and state (`ModelSelectorProvider`) that lists models and manages download, deletion, and selection.
- **Function_Calling**: A capability where a model emits structured tool-invocation requests; supported natively by capable LiteRT models such as Gemma 4.
- **Tool**: A named, parameterized action that the model can request through Function_Calling.
- **Capability_Badge**: A UI indicator on a model entry signaling a supported capability such as tool calling, vision, or fast inference.
- **Split_ABI_Build**: An Android build configuration that produces per-architecture application packages to limit installed binary size.
- **Device_RAM**: The total physical memory reported by the device, expressed in megabytes.

## Requirements

### Requirement 1: Engine Abstraction Layer

**User Story:** As an AURA developer, I want an engine abstraction behind the existing `LLMService` interface, so that the Orchestrator and application code can use multiple inference engines without changing.

#### Acceptance Criteria

1. THE AURA SHALL define an AIEngine enumeration containing exactly the values `gguf` and `litert`.
2. THE Engine_Router SHALL implement the LLMService interface comprising the `initialize`, `loadModel`, `chat`, `isModelLoaded`, and `modelTier` members.
3. WHEN the Orchestrator calls a LLMService member other than `loadModel`, THE Engine_Router SHALL delegate the call to the Inference_Engine of the active model, where the active model is the model set by the most recent successful `loadModel` call.
4. WHEN the Engine_Router receives a `loadModel` call, THE Engine_Router SHALL select the Inference_Engine by the model's engine field, delegating to the GGUF_Engine when the engine field equals `gguf` and to the LiteRT_Engine when the engine field equals `litert`, and SHALL set that model as the active model only after the selected Inference_Engine reports the model as loaded.
5. IF the Inference_Engine selected during a `loadModel` call reports that it cannot load the model, THEN THE Engine_Router SHALL return an error identifying the load failure and SHALL retain the previously active model, if any, as the active model.
6. WHILE a model whose engine field equals `gguf` is the active model, THE Engine_Router SHALL delegate every LLMService call to the GGUF_Engine.
7. WHILE a model whose engine field equals `litert` is the active model, THE Engine_Router SHALL delegate every LLMService call to the LiteRT_Engine.
8. THE Engine_Router SHALL expose the `chat` method with the existing signature accepting a prompt, an optional system prompt, a maximum token count of at least 1, and a temperature value between 0.0 and 2.0 inclusive.
9. IF the Engine_Router receives a LLMService call WHILE no model is active, THEN THE Engine_Router SHALL return an error indicating that no model is loaded and SHALL leave the active model unset.

### Requirement 2: Preserve the Existing GGUF Engine and Qwen Experience

**User Story:** As an existing AURA user running Qwen models, I want the current engine to keep working unchanged, so that updating the app does not disrupt my assistant.

#### Acceptance Criteria

1. THE AURA SHALL retain the RunAnywhere GGUF_Engine implementation, exposing the same LLMService members and method signatures that it exposed before this feature is installed.
2. WHEN a model whose engine field equals `gguf` is selected, THE AURA SHALL load and run the model through the GGUF_Engine.
3. WHEN the GGUF_Engine produces chat output, THE AURA SHALL apply the existing output-cleaning behavior to that output before returning it to the Orchestrator.
4. WHERE a `gguf` model file is present on device under the file name defined for that model, THE AURA SHALL recognize the model as downloaded and available for selection after an application restart without requiring re-download.
5. WHEN a `gguf` model is active, THE Orchestrator SHALL use the existing rule-based intent detection for that model.
6. THE AURA SHALL derive the ModelTier for a `gguf` model using the existing file-name-based detection, reporting one of the ModelTier values `small`, `medium`, or `large`.
7. IF the GGUF_Engine fails to load a selected `gguf` model, THEN THE AURA SHALL return an error identifying the load failure and keep the previously active model, if any, as the active model.

### Requirement 3: LiteRT Engine Integration

**User Story:** As an AURA user, I want to run Gemma LiteRT models on my device, so that I can use Google's on-device models offline.

#### Acceptance Criteria

1. THE LiteRtService SHALL implement the LLMService interface comprising the `initialize`, `loadModel`, `chat`, `isModelLoaded`, and `modelTier` members.
2. THE LiteRtService SHALL perform inference for LiteRT models by delegating to the `flutter_gemma` package.
3. WHEN the LiteRtService loads a model file with a `.task` or `.litertlm` extension, THE LiteRtService SHALL initialize an inference session for that model and report `isModelLoaded` as true.
4. WHEN the LiteRtService receives a `chat` call, THE LiteRtService SHALL format the prompt using the Gemma `<start_of_turn>` template.
5. WHEN the LiteRtService generates a response, THE LiteRtService SHALL emit the response as a stream of text tokens and SHALL close the stream when generation completes.
6. WHILE a LiteRT model is loaded, THE LiteRtService SHALL report `isModelLoaded` as true.
7. IF the LiteRtService fails to initialize the LiteRT_Engine, THEN THE LiteRtService SHALL return an error identifying the initialization failure and SHALL report `isModelLoaded` as false.
8. IF the LiteRtService is asked to load a model whose file format is not supported by the LiteRT_Engine, THEN THE LiteRtService SHALL return an error identifying the unsupported format and SHALL leave any previously loaded model loaded.
9. IF the LiteRtService fails to load a model whose file format is supported by the LiteRT_Engine, THEN THE LiteRtService SHALL return an error identifying the load failure.
10. IF the LiteRtService receives a `chat` call WHILE no LiteRT model is loaded, THEN THE LiteRtService SHALL return an error indicating that no model is loaded.

### Requirement 4: Model Catalog Expansion

**User Story:** As an AURA user, I want new Gemma models available in the catalog, so that I can choose a model that fits my device and needs.

#### Acceptance Criteria

1. THE ModelInfo entity SHALL include an engine field whose value is a member of the AIEngine enumeration.
2. THE ModelInfo entity SHALL include a tool-calling capability field holding a boolean value, a vision capability field holding a boolean value, and an inference speed category field whose value is a member of an enumeration containing exactly the values `fast`, `medium`, and `slow`.
3. WHERE a ModelInfo entry describes a Qwen 2.5 model, THE AURA SHALL set the engine field of that entry to `gguf`.
4. THE Model_Catalog SHALL include an entry for Gemma 3 1B with the engine field set to `litert`.
5. THE Model_Catalog SHALL include an entry for Gemma 3n E2B with the engine field set to `litert`.
6. THE Model_Catalog SHALL include an entry for Gemma 4 E2B with the engine field set to `litert` and the tool-calling capability field set to true.
7. THE Model_Catalog SHALL include an entry for Gemma 4 E4B with the engine field set to `litert` and the tool-calling capability field set to true.
8. THE AURA SHALL assign each Model_Catalog entry a download size expressed in megabytes that is greater than 0 and at most 99,999.
9. THE AURA SHALL assign each Model_Catalog entry a minimum RAM requirement expressed in megabytes that is greater than 0 and at most 65,536.
10. THE AURA SHALL assign each Model_Catalog entry a model identifier that is unique among all Model_Catalog entries.

### Requirement 5: Function Calling for Capable Models

**User Story:** As an AURA user with a tool-calling Gemma model, I want the assistant to invoke device actions through native function calling, so that intent handling is more accurate than text pattern matching.

#### Acceptance Criteria

1. WHILE the active model has the tool-calling capability field set to true, THE AURA SHALL provide the model on every inference call with the set of available Tool definitions, where each definition comprises a Tool name and the Tool's declared parameters.
2. WHEN a tool-calling model emits a Function_Calling request, THE AURA SHALL parse the request into exactly one Tool name and zero or more parameter name-value pairs.
3. WHEN a Function_Calling request is parsed, THE Orchestrator SHALL route the request to the handler associated with the named Tool and pass the parsed parameter values to that handler.
4. WHILE the active model has the tool-calling capability field set to false, THE Orchestrator SHALL use the existing rule-based intent detection for that model.
5. IF a tool-calling model emits a Function_Calling request that names an undefined Tool, THEN THE AURA SHALL return an error indicating that the requested Tool is unavailable and SHALL NOT invoke any Tool handler.
6. IF a Function_Calling request omits a parameter that the named Tool requires, THEN THE AURA SHALL return an error identifying each missing required parameter and SHALL NOT invoke the named Tool's handler.
7. IF a Function_Calling request cannot be parsed into a Tool name and parameter name-value pairs, THEN THE AURA SHALL return an error indicating that the request could not be parsed and SHALL NOT invoke any Tool handler.

### Requirement 6: Model Selector UI Updates

**User Story:** As an AURA user, I want the model selector to group models by engine and show capability badges, so that I can understand what each model offers before downloading.

#### Acceptance Criteria

1. THE Model_Selector SHALL assign each catalog model to exactly one group labeled by the value of the model's engine field and SHALL display a heading for each group.
2. WHERE a model has the tool-calling capability field set to true, THE Model_Selector SHALL display a tool-calling Capability_Badge on that model.
3. WHERE a model has the vision capability field set to true, THE Model_Selector SHALL display a vision Capability_Badge on that model.
4. WHERE a model has the inference speed category field set to the highest-speed value, THE Model_Selector SHALL display a fast Capability_Badge on that model.
5. WHERE a model has more than one capability field qualifying for a Capability_Badge, THE Model_Selector SHALL display every qualifying Capability_Badge on that model concurrently.
6. THE Model_Selector SHALL display each model's download size in megabytes and minimum RAM requirement in megabytes.
7. WHEN a user selects a downloaded model, THE Model_Selector SHALL request that the Engine_Router load that model through the engine indicated by the model's engine field.
8. IF the Engine_Router reports a failure loading a model selected by the user, THEN THE Model_Selector SHALL display a load-failure message and retain the previously active model, if any, as the selected model.

### Requirement 7: Download Management for the LiteRT Format

**User Story:** As an AURA user, I want to download, track, and delete LiteRT models like I do GGUF models, so that I can manage storage for both formats.

#### Acceptance Criteria

1. WHEN a user starts a download of a `litert` model, THE Model_Selector SHALL store the downloaded file under the file name defined for that model in the Model_Catalog.
2. WHILE a `litert` model download is in progress, THE Model_Selector SHALL report download progress as a value between 0 and 1 inclusive that does not decrease as additional bytes are received.
3. WHEN a `litert` model download completes with the entire file received, THE Model_Selector SHALL mark that model as downloaded.
4. IF a `litert` model download attempt fails, THEN THE Model_Selector SHALL retry the download until 3 total download attempts have been made.
5. IF all 3 download attempts for a `litert` model fail, THEN THE Model_Selector SHALL remove any partially downloaded file and report a download-failure error to the user.
6. WHEN a user deletes a downloaded `litert` model, THE Model_Selector SHALL remove the model file and report the total storage used reduced by that model's file size.
7. WHEN the application restarts AND a `litert` model file is present on device under the file name defined for that model in the Model_Catalog, THE Model_Selector SHALL recognize that model as downloaded.
8. IF the available disk space is less than the file size of a `litert` model, THEN THE Model_Selector SHALL report an insufficient-storage error and SHALL NOT start the download.

### Requirement 8: Device Compatibility and RAM Safety

**User Story:** As an AURA user on a device with limited memory, I want the app to prevent me from loading a model my device cannot run, so that the app does not crash.

#### Acceptance Criteria

1. WHEN a user attempts to load a model, THE AURA SHALL, before any model loading begins, compare the model's minimum RAM requirement in megabytes against the Device_RAM in megabytes.
2. IF a model's minimum RAM requirement in megabytes exceeds the Device_RAM in megabytes, THEN THE AURA SHALL prevent loading that model and report a memory-insufficiency message identifying both the required megabytes and the available megabytes.
3. WHERE Device_RAM is below the minimum RAM requirement of a model, THE Model_Selector SHALL indicate that the model is not supported on the device and disable selection of that model.
4. WHEN a `litert` model becomes the active model, THE AURA SHALL determine its ModelTier as exactly one of `small`, `medium`, or `large` from that model's catalog metadata and report that tier through the `modelTier` member.
5. WHEN a model load is prevented due to insufficient memory, THE AURA SHALL retain the previously active model, if any, as the active model and leave that previously active model loaded and usable.
6. IF the Device_RAM cannot be determined WHEN a user attempts to load a model, THEN THE AURA SHALL prevent loading that model and report a device-compatibility error indicating that available memory could not be verified.

### Requirement 9: APK Size Management

**User Story:** As an AURA user, I want the installed application to stay reasonably sized, so that adding a second engine does not bloat my device storage.

#### Acceptance Criteria

1. THE AURA SHALL produce a separate Android application package for each supported CPU architecture using a Split_ABI_Build configuration.
2. THE AURA SHALL distribute LiteRT model files as downloadable content retrieved after installation.
3. THE Android application package produced by AURA SHALL contain zero LiteRT model files.
4. WHERE a device installs a per-architecture application package, THE AURA SHALL include in that installed package only the native binaries for that device's architecture and SHALL exclude the native binaries for every other supported architecture.

### Requirement 10: Graceful Fallback on LiteRT Failure

**User Story:** As an AURA user, I want the app to keep working if the LiteRT engine cannot start, so that an engine problem does not break the whole assistant.

#### Acceptance Criteria

1. IF the LiteRT_Engine fails to initialize within 30 seconds of a `litert` model being selected, THEN THE AURA SHALL display an error message to the user indicating an engine-initialization failure.
2. IF the LiteRT_Engine fails to initialize for a selected `litert` model, THEN THE AURA SHALL retain the previously active model as the active model and decline to set the `litert` model as active.
3. WHILE the LiteRT_Engine is unavailable, THE AURA SHALL keep every `gguf` model available for selection and loading.
4. IF the LiteRtService raises an error during a `chat` call, THEN THE Engine_Router SHALL return an error message to the user indicating a chat failure without terminating the application.
5. WHEN a `chat` call delegated to the LiteRtService fails, THE Engine_Router SHALL keep the active model loaded and available for subsequent `chat` calls.
6. WHEN the LiteRT_Engine fails to initialize, THE AURA SHALL leave any active `gguf` model loaded and usable.
