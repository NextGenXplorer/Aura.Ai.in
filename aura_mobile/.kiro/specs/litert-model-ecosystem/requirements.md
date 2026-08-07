# Requirements Document

## Introduction

This feature expands the AURA Mobile on-device AI model ecosystem. It adds 5 new chat LLMs from multiple vendors (Phi-4-mini, Llama 3.2 1B, Llama 3.2 3B, Qwen3 4B, SmolLM 135M), introduces 2 utility models that progressively enhance intent detection (FunctionGemma 270M) and semantic search (EmbeddingGemma 300M), integrates 4 MediaPipe vision tasks (face detection, object detection, image segmentation, pose estimation), and restructures the Model Catalog UI into 3 categorized sections (Chat, Utility, Vision).

All LLM models run exclusively through the LiteRT runtime (flutter_gemma / MediaPipe LLM Inference). MediaPipe Tasks run through their respective MediaPipe SDK pipelines. The progressive enhancement pattern guarantees that existing rule-based intent detection (50+ regex patterns) and keyword-based search remain fully functional when utility models are not downloaded.

## Glossary

- **LiteRT_Engine**: The `LiteRtService` class wrapping the `flutter_gemma` plugin, responsible for loading and running on-device LLM models in `.task` or `.litertlm` format via MediaPipe LLM Inference.
- **Model_Catalog**: The `modelCatalog` list in `lib/domain/entities/model_info.dart` containing all `ModelInfo` entries with metadata (id, name, size, RAM requirement, download URL, category, capabilities).
- **Chat_Model**: A generative LLM used for conversational responses. Exactly one Chat_Model may be loaded into the LiteRT_Engine at any time.
- **Utility_Model**: A small, purpose-built model (FunctionGemma or EmbeddingGemma) that enhances a specific app capability. Multiple Utility_Models may be downloaded and available on disk concurrently.
- **FunctionGemma**: A 270 MB LiteRT model (google/functiongemma-270m) trained to convert natural language input into structured JSON function calls for device actions.
- **EmbeddingGemma**: A 308 MB LiteRT model (google/embeddinggemma-300m) that generates 768-dimensional vector embeddings from text for semantic similarity search.
- **Progressive_Enhancement**: An architecture pattern where the presence of a downloaded Utility_Model file on disk automatically upgrades a service from its baseline implementation (regex or keyword) to a model-based implementation, with no user action beyond the initial download.
- **Intent_Detection_Service**: The `IntentDetectionService` class in `lib/domain/services/intent_detection_service.dart` using 50+ regex patterns to classify user messages into `IntentType` enum values.
- **Memory_Service**: The `MemoryService` class in `lib/domain/services/memory_service.dart` storing and retrieving user memories, currently using SQLite keyword-based `searchMemories()`.
- **Document_Service**: The `DocumentService` class in `lib/domain/services/document_service.dart` ingesting PDFs into chunks and retrieving them, currently using keyword scoring in `retrieveRelevantContext()`.
- **Download_Service**: The `DownloadService` class in `lib/core/services/download_service.dart` using `FlutterForegroundTask` for background downloads with progress reporting via `DownloadUpdate` stream.
- **MediaPipe_Task**: A pre-packaged on-device ML pipeline from the MediaPipe SDK (face detection, object detection, image segmentation, pose estimation) that ships bundled model weights within the SDK package and requires no separate user download.
- **Model_Category**: A classification enum with values: `chat`, `utility`, `vision`. Every `ModelInfo` entry belongs to exactly one category.
- **Hot_Swap**: The sequence of unloading the active Chat_Model, loading a Utility_Model, running inference, unloading the Utility_Model, and reloading the Chat_Model — all within a single request cycle.
- **Concurrent_Loading**: Running a Utility_Model through a separate MediaPipe LLM Inference instance (separate native session) while the Chat_Model remains loaded in the primary instance.
- **Semantic_Search**: Retrieving stored content (memories, document chunks) by computing cosine similarity between the query embedding and stored embeddings, returning results ranked by similarity score.
- **Embedding_Pipeline**: A separate MediaPipe inference instance (or AI Edge RAG API) dedicated to running EmbeddingGemma, distinct from the generative Chat_Model session.

## Requirements

### Requirement 1: Expanded Chat Model Catalog

**User Story:** As a user, I want access to additional chat LLM options beyond Gemma, so that I can choose a model that best fits my device capabilities and use-case preferences.

#### Acceptance Criteria

1. THE Model_Catalog SHALL include a `ModelInfo` entry for Phi-4-mini with id `phi4-mini`, download size 2500 MB (±200 MB), minimum RAM 4096 MB, InferenceSpeed `medium`, and category `chat`.
2. THE Model_Catalog SHALL include a `ModelInfo` entry for Llama 3.2 1B with id `llama32-1b`, download size 1000 MB (±150 MB), minimum RAM 2048 MB, InferenceSpeed `fast`, and category `chat`.
3. THE Model_Catalog SHALL include a `ModelInfo` entry for Llama 3.2 3B with id `llama32-3b`, download size 2000 MB (±200 MB), minimum RAM 4096 MB, InferenceSpeed `medium`, and category `chat`.
4. THE Model_Catalog SHALL include a `ModelInfo` entry for Qwen3 4B with id `qwen3-4b`, download size 3000 MB (±300 MB), minimum RAM 4096 MB, InferenceSpeed `slow`, and category `chat`.
5. THE Model_Catalog SHALL include a `ModelInfo` entry for SmolLM 135M with id `smollm-135m`, download size 70 MB (±10 MB), minimum RAM 1024 MB, InferenceSpeed `fast`, and category `chat`.
6. WHEN the user selects any newly added Chat_Model for loading, THE LiteRT_Engine SHALL load the model file using the same `FlutterGemma.installModel()` and `FlutterGemma.getActiveModel()` API sequence used for existing Gemma models.
7. WHEN the LiteRT_Engine loads a newly added Chat_Model, THE LiteRT_Engine SHALL apply the model-appropriate prompt template (Gemma turn markers for Gemma models, ChatML for Phi/Llama/Qwen/SmolLM) before passing the prompt to the inference session.
8. IF a newly added Chat_Model file is corrupted or fails to load, THEN THE LiteRT_Engine SHALL throw an `AIServiceException.modelLoadFailed` and leave no model loaded, consistent with existing error handling.

### Requirement 2: Model Catalog Categorization

**User Story:** As a user, I want the model catalog organized into clear sections, so that I can understand the purpose of each model and make informed download decisions.

#### Acceptance Criteria

1. THE `ModelInfo` class SHALL include a `category` field of type `ModelCategory` enum with values `chat`, `utility`, and `vision`.
2. THE Model_Catalog SHALL classify all existing Gemma models and newly added Chat_Models with category `chat`.
3. THE Model_Catalog SHALL classify FunctionGemma and EmbeddingGemma with category `utility`.
4. THE Model_Catalog UI SHALL render three distinct scrollable sections with headers "Chat Models", "Utility Models", and "Vision Models", displayed in that order.
5. THE Utility Models section SHALL display for each entry: model name, download size, a one-sentence description of the enhancement provided, and a download/delete action button.
6. WHEN a Utility_Model file is present on disk, THE Model_Catalog UI SHALL display an "Active" badge next to that Utility_Model entry.
7. THE Model_Catalog UI SHALL allow the user to download or delete any Utility_Model regardless of which Chat_Model is currently selected or loaded.
8. THE Model_Catalog UI SHALL NOT allow the user to "select" a Utility_Model as the active chat model; Utility_Models only support download and delete actions.

### Requirement 3: FunctionGemma Intent Detection — Progressive Enhancement

**User Story:** As a user, I want smarter intent detection that handles natural language better than regex patterns, so that my device action requests are understood more accurately without requiring me to use specific trigger phrases.

#### Acceptance Criteria

1. THE Model_Catalog SHALL include a `ModelInfo` entry for FunctionGemma with id `functiongemma-270m`, download size 270 MB, minimum RAM 2048 MB, category `utility`, and description "Enhances intent detection — converts natural language to device action calls."
2. WHILE the FunctionGemma model file does not exist in the app documents directory, THE Intent_Detection_Service SHALL use its existing regex-based `detectIntent()` method for all intent classification with zero behavioral change from current production behavior.
3. WHILE the FunctionGemma model file exists in the app documents directory, THE app SHALL route user messages through FunctionGemma inference for intent classification BEFORE falling through to the regex-based Intent_Detection_Service.
4. WHEN FunctionGemma classifies a user message, THE inference output SHALL be a JSON string parseable into a Dart `Map<String, dynamic>` with exactly two keys: `name` (a `String` matching a supported function name) and `arguments` (a `Map<String, dynamic>` of parameter names to values).
5. WHEN FunctionGemma returns a valid JSON function call, THE app SHALL map the `name` field to the corresponding `IntentType` enum value and execute the action using the same handler path as regex-detected intents.
6. IF FunctionGemma inference throws an exception, times out (exceeds 500 ms), or returns output that does not parse into the required JSON structure, THEN THE app SHALL discard the FunctionGemma result and immediately invoke the regex-based Intent_Detection_Service for the same message.
7. THE FunctionGemma function vocabulary SHALL include at minimum: `toggleTorch`, `openCamera`, `openSettings`, `dialContact`, `sendSMS`, `composeEmail`, `webSearch`, `setAlarm`, `createCalendarEvent`, `getNextEvent`, `startNavigation`, and `openApp`.
8. WHEN the user deletes the FunctionGemma file via the catalog UI, THE app SHALL detect file absence on the next intent classification call and route through the regex-based Intent_Detection_Service without requiring app restart or explicit state refresh.
9. WHEN the app starts, THE app SHALL check for FunctionGemma file existence at the path `{appDocumentsDir}/functiongemma-270m.task` and set an in-memory boolean flag (`isFunctionGemmaAvailable`) that the intent routing logic reads.
10. THE FunctionGemma inference latency (from input string to parsed JSON output, excluding model load if pre-loaded) SHALL remain below 200 ms on a device with 4 GB RAM and an ARM64 processor.

### Requirement 4: EmbeddingGemma Semantic Search — Progressive Enhancement

**User Story:** As a user, I want my saved memories and documents to be searchable by meaning rather than exact keywords, so that I can find relevant information even when I use different phrasing than what was stored.

#### Acceptance Criteria

1. THE Model_Catalog SHALL include a `ModelInfo` entry for EmbeddingGemma with id `embeddinggemma-300m`, download size 308 MB, minimum RAM 2048 MB, category `utility`, and description "Enables semantic search — find memories and documents by meaning, not just keywords."
2. WHILE the EmbeddingGemma model file does not exist in the app documents directory, THE Memory_Service `retrieveRelevantMemories()` SHALL use the existing `_repository.searchMemories(query)` keyword-based search with zero behavioral change.
3. WHILE the EmbeddingGemma model file does not exist in the app documents directory, THE Document_Service `retrieveRelevantContext()` SHALL use the existing keyword scoring algorithm with zero behavioral change.
4. WHILE the EmbeddingGemma model file exists in the app documents directory, THE Memory_Service SHALL generate a vector embedding for new memories at `saveMemory()` time and store the embedding in the `Memory.embedding` field.
5. WHILE the EmbeddingGemma model file exists in the app documents directory, THE Memory_Service `retrieveRelevantMemories()` SHALL embed the query string, compute cosine similarity against stored memory embeddings, and return the top `limit` results ranked by descending similarity score.
6. WHILE the EmbeddingGemma model file exists in the app documents directory, THE Document_Service SHALL generate vector embeddings for each document chunk at `_processChunks()` time and store embeddings in the `DocumentChunk.embedding` field.
7. WHILE the EmbeddingGemma model file exists in the app documents directory, THE Document_Service `retrieveRelevantContext()` SHALL embed the query string, compute cosine similarity against stored chunk embeddings, and return the top `limit` results ranked by descending similarity score.
8. WHEN EmbeddingGemma is first downloaded and memories with empty `embedding` fields exist in the database, THE app SHALL schedule a background isolate that iterates through un-embedded memories, generates embeddings, and updates the database records without blocking the main UI isolate.
9. WHEN EmbeddingGemma is first downloaded and document chunks with empty `embedding` fields exist in the database, THE app SHALL schedule a background isolate that iterates through un-embedded chunks, generates embeddings, and updates the database records without blocking the main UI isolate.
10. IF EmbeddingGemma inference throws an exception during a `retrieveRelevantMemories()` or `retrieveRelevantContext()` call, THEN THE respective service SHALL fall back to keyword-based search for that single request and log the error.
11. WHEN the user deletes the EmbeddingGemma file via the catalog UI, THE Memory_Service and Document_Service SHALL detect file absence on their next retrieval call and use keyword-based search without requiring app restart.
12. THE EmbeddingGemma model SHALL run through a dedicated Embedding_Pipeline instance that is separate from the LiteRT_Engine Chat_Model session, ensuring embedding generation never unloads or interferes with the active Chat_Model.
13. WHEN the app starts, THE app SHALL check for EmbeddingGemma file existence at the path `{appDocumentsDir}/embeddinggemma-300m.task` and set an in-memory boolean flag (`isEmbeddingGemmaAvailable`) that the Memory_Service and Document_Service read.
14. THE EmbeddingGemma embedding generation latency for a single text input (up to 512 tokens) SHALL remain below 100 ms on a device with 4 GB RAM and an ARM64 processor.

### Requirement 5: Multi-Model Loading Strategy

**User Story:** As a developer, I want a clear model-loading strategy that allows utility models to operate alongside the active chat model, so that progressive enhancement features do not disrupt the user's conversation flow.

#### Acceptance Criteria

1. THE LiteRT_Engine (`LiteRtService`) SHALL maintain its constraint of exactly one Chat_Model loaded via `FlutterGemma.getActiveModel()` at any time.
2. WHEN FunctionGemma inference is needed and the platform supports concurrent MediaPipe LLM Inference instances, THE app SHALL load FunctionGemma through a second `FlutterGemmaPlugin` instance (or equivalent separate native session) without calling `unload()` on the active Chat_Model.
3. WHEN FunctionGemma inference is needed and the platform does NOT support concurrent instances, THE app SHALL execute the Hot_Swap sequence: unload Chat_Model → load FunctionGemma → run inference → unload FunctionGemma → reload Chat_Model.
4. THE EmbeddingGemma model SHALL always run through the Embedding_Pipeline (MediaPipe Embedding API or AI Edge RAG library), which is architecturally independent of the `FlutterGemmaPlugin` instance used for Chat_Model inference.
5. IF Hot_Swap is required for FunctionGemma, THEN THE total elapsed time for the complete swap cycle SHALL remain below 2000 ms on a device with 4 GB RAM and an ARM64 processor.
6. WHILE a Hot_Swap operation is in progress, THE app SHALL buffer any new user chat messages in a queue and process them sequentially after the Chat_Model is reloaded, ensuring zero message loss.
7. WHILE a Hot_Swap operation is in progress, THE app SHALL display a brief loading indicator in the chat UI to inform the user that processing is momentarily paused.
8. THE app SHALL detect concurrent loading capability at runtime by attempting to create a secondary inference instance and catching any platform exception, caching the result for the app session lifetime.

### Requirement 6: MediaPipe Tasks Integration

**User Story:** As a user, I want to use my camera to identify objects, detect faces, remove backgrounds, and analyze body poses, so that I can interact with the physical world through the AI assistant without downloading additional large models.

#### Acceptance Criteria

1. THE app SHALL integrate the MediaPipe Face Detection task to detect face bounding boxes and landmarks in camera-captured images.
2. THE app SHALL integrate the MediaPipe Object Detection task to identify and label objects in camera-captured or gallery-selected images, returning object names with confidence scores.
3. THE app SHALL integrate the MediaPipe Image Segmentation task to produce a foreground mask suitable for background removal from camera-captured or gallery-selected images.
4. THE app SHALL integrate the MediaPipe Pose Landmark task to detect 33 body pose landmarks from camera-captured images and render them as an overlay.
5. THE MediaPipe task model files SHALL be included as bundled assets within the `google_mlkit_*` or `mediapipe_*` Flutter package dependencies, requiring zero additional downloads from the user.
6. WHEN a MediaPipe task completes processing, THE app SHALL display results in the chat interface within 3 seconds of image capture on a device with 4 GB RAM.
7. THE Intent_Detection_Service SHALL include regex patterns for MediaPipe task triggers: "scan this", "what is this", "identify this", "what is in this photo" (object detection), "detect face", "find faces" (face detection), "remove background" (segmentation), "detect pose", "analyze posture" (pose estimation).
8. WHEN FunctionGemma is available, THE FunctionGemma function vocabulary SHALL include: `detectFaces`, `detectObjects`, `removeBackground`, and `detectPose` mapping to the respective MediaPipe tasks.
9. IF camera permission is not granted, THEN THE app SHALL display an error message stating "Camera access is required for this feature. Please grant camera permission in Settings." and provide a button to open the app's permission settings.
10. IF a MediaPipe task fails due to an unsupported image format or processing error, THEN THE app SHALL display an error message describing the failure and suggesting the user try a different image.

### Requirement 7: Utility Model Download and Persistence

**User Story:** As a user, I want utility model downloads to persist across app restarts and be managed independently, so that I only download enhancements I want and they remain available without re-downloading.

#### Acceptance Criteria

1. WHEN a user taps the download button for a Utility_Model, THE Download_Service SHALL download the model file to `{appDocumentsDir}/{modelFileName}` using the existing `FlutterForegroundTask`-based foreground service with `DownloadUpdate` stream progress reporting.
2. WHEN the app launches, THE app SHALL check for file existence of each known Utility_Model at its expected path in the app documents directory and update the corresponding availability flag (`isFunctionGemmaAvailable`, `isEmbeddingGemmaAvailable`).
3. WHEN a user taps the delete button for a downloaded Utility_Model, THE app SHALL delete the model file from disk, set the corresponding availability flag to `false`, and ensure the next service call uses the fallback implementation.
4. THE Model_Catalog UI SHALL display for each Utility_Model: the file size in MB, an estimate of download time at 10 Mbps, and the current available disk space, all visible before the user initiates download.
5. IF the available disk space is less than the Utility_Model file size plus 100 MB buffer, THEN THE app SHALL disable the download button and display a message: "Not enough storage. {requiredMB} MB needed, {availableMB} MB available."
6. THE Download_Service SHALL support concurrent download of a Utility_Model file while the LiteRT_Engine has an active Chat_Model loaded, without causing the Chat_Model session to be interrupted or unloaded.
7. WHEN a Utility_Model download completes successfully, THE app SHALL immediately set the corresponding availability flag to `true` so that the progressive enhancement takes effect on the next relevant service call without requiring app restart.
8. IF a Utility_Model download fails or is cancelled, THEN THE app SHALL delete any partially downloaded file and leave the availability flag as `false`.

### Requirement 8: Vision Model Category Placeholder

**User Story:** As a user, I want to see that vision-capable LLM models are planned for the future, so that I understand the app's roadmap for image understanding.

#### Acceptance Criteria

1. THE Model_Catalog UI SHALL render the "Vision Models" section below the "Utility Models" section, even when the Model_Catalog contains zero entries with category `vision`.
2. WHEN no Vision models are available in the catalog, THE Vision section SHALL display the text: "Vision LLM models (SmolVLM, FastVLM) are coming in a future update."
3. THE `ModelInfo` class and `ModelCategory` enum SHALL support the `vision` category value from initial implementation, enabling future addition of Vision model entries without schema migration or breaking changes to the catalog data structure.
