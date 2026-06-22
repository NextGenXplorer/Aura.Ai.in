# Implementation Plan: Productivity Features

## Overview

This plan implements five productivity features for AURA Mobile: Chat Export (Markdown & PDF), RAG Agent refactor, Context Window Indicator, Clipboard Bubble UI overlay, and an Automation Engine with background execution. Tasks are organized by feature area with shared infrastructure first, then feature-specific implementation, and integration wiring last.

## Tasks

- [x] 1. Add dependency and database migration
  - [x] 1.1 Add `pdf` package to pubspec.yaml
    - Add `pdf: ^3.10.0` to the dependencies section of `pubspec.yaml`
    - Run `flutter pub get` to resolve
    - _Requirements: 2.1_

  - [x] 1.2 Add database version 5 migration for automation_rules table
    - In `lib/data/datasources/database_helper.dart`, bump version from 4 to 5
    - Add `if (oldVersion < 5)` block in `_onUpgrade` creating the `automation_rules` table
    - Add the CREATE TABLE statement to `_onCreate` as well for fresh installs
    - Schema: id TEXT PRIMARY KEY, name TEXT NOT NULL, triggerType TEXT NOT NULL, scheduledTime INTEGER, repeatIntervalMinutes INTEGER, condition TEXT, checkIntervalMinutes INTEGER DEFAULT 60, actionInstruction TEXT NOT NULL, isEnabled INTEGER DEFAULT 1, lastExecutedAt INTEGER, createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL
    - _Requirements: 9.2, 9.3_

- [x] 2. Implement Chat Export Service
  - [x] 2.1 Create ChatExportService with Markdown conversion
    - Create `lib/features/export/application/chat_export_service.dart`
    - Implement `convertToMarkdown(List<Map<String, String>> messages)` — bold role labels, "yyyy-MM-dd HH:mm" timestamps, message body, horizontal rule separators
    - Implement `exportAsMarkdown()` — write temp file `chat_export_<timestamp>.md`, invoke share_plus with MIME type `text/markdown` and plain text fallback, clean up temp file
    - Return `ExportResult.empty` for empty message lists, show snackbar
    - Handle write failures: return `ExportResult.error`, delete partial files
    - Register as `chatExportServiceProvider` with Riverpod
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 3.1, 3.2, 3.3_

  - [ ]* 2.2 Write property test for Markdown serialization
    - **Property 1: Markdown serialization preserves all messages**
    - Generate random message lists (1–100 messages, roles from {'user', 'assistant'}, Unicode content)
    - Assert: output contains every message's bold role label, timestamp in "yyyy-MM-dd HH:mm", and full body text; messages separated by horizontal rules
    - **Validates: Requirements 1.1**

  - [x] 2.3 Implement PDF generation
    - Add `generatePdf(List<Map<String, String>> messages)` using the `pdf` package
    - Render messages in chronological order with role label, locale timestamp, body (min 10pt font, max 1000 messages)
    - Return `Uint8List` of PDF content
    - Implement `exportAsPdf()` — write temp file `chat_export_<timestamp>.pdf`, invoke share_plus with MIME type `application/pdf`, clean up
    - Handle timeout (>30s → cancel, return `ExportResult.timeout`)
    - Handle insufficient storage (return `ExportResult.insufficientStorage`)
    - Handle empty messages (return `ExportResult.empty`)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 3.1, 3.3_

  - [ ]* 2.4 Write property test for PDF message preservation
    - **Property 2: PDF generation preserves all messages in order**
    - Generate random message lists (1–50 messages for test speed)
    - Assert: PDF bytes are non-empty, PDF text extraction contains all message bodies in input order
    - **Validates: Requirements 2.1**

  - [x] 2.5 Create Export UI (bottom sheet and button)
    - Add an export button (icon) to `ChatScreen` app bar
    - Create an export bottom sheet widget with "Markdown" and "PDF" format selection
    - Show loading indicator during PDF generation
    - Display snackbar messages for empty, error, timeout, and insufficient storage states
    - _Requirements: 1.4, 2.5, 2.7_

- [ ] 3. Checkpoint - Ensure export feature tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Refactor RAG Agent with real implementation
  - [x] 4.1 Implement RAGAgent document retrieval and LLM grounding
    - Refactor `lib/features/agents/application/rag_agent.dart` — replace stub
    - Inject `DocumentService`, `ContextBuilderService`, `LLMService` via constructor
    - In `process()`: call `DocumentService.retrieveRelevantContext(input, limit: 10)` to get chunks
    - Implement `buildRagPrompt(query, chunks, sourceDocuments)` — include all chunks as context + user query
    - Implement `formatCitations(sourceDocuments)` — deduplicated list of source filenames
    - Stream LLM response, then append formatted citations
    - Handle edge cases: no chunks found → yield "no relevant information found"; model not loaded → yield informational message without calling DocumentService; LLM failure → yield error, retain loaded state
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7_

  - [ ]* 4.2 Write property test for RAG prompt construction
    - **Property 3: RAG prompt contains all retrieved chunks and the user query**
    - Generate random chunk lists (1–10 items) and random query strings
    - Assert: `buildRagPrompt()` output contains every chunk's text and the original query
    - **Validates: Requirements 4.2**

  - [ ]* 4.3 Write property test for citation deduplication
    - **Property 4: RAG citations list all distinct source documents**
    - Generate random source document lists with duplicates
    - Assert: `formatCitations()` output has exactly one entry per distinct filename, no duplicates, no omissions
    - **Validates: Requirements 4.5, 4.7**

- [x] 5. Implement Context Window Indicator
  - [x] 5.1 Create ContextWindowNotifier provider
    - Create `lib/presentation/providers/context_window_provider.dart`
    - Define `ContextWindowState` (estimatedTokens, maxTokens=4096, currentTurns, maxTurns, colorState, modelTier)
    - Define `ContextWindowColorState` enum (normal, warning, critical)
    - Implement `estimateTokens(String text)` — `(text.length / 4).ceil()`, empty → 0
    - Implement `colorStateForTokens(tokens, maxTokens)` — normal ≤75%, warning 75-90%, critical >90%
    - Implement `calculateTurns(messages, tier)` — `min(messages.length ~/ 2, tierMax)` where tierMax is 4/6/10
    - Implement `recalculate(messages)` — call ContextBuilderService.buildPrompt, estimate tokens, determine color and turns
    - Listen to chat state changes for reactive updates
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 6.1, 6.2, 6.3_

  - [ ]* 5.2 Write property tests for token estimation and thresholds
    - **Property 5: Token estimation is ceil(charCount / 4)**
    - Generate random strings (length 0–10000), assert `estimateTokens(s)` == `(s.length / 4).ceil()` (0 for empty)
    - **Property 6: Context indicator color state is determined by token thresholds**
    - Generate random token counts [0, 4096], assert correct color state at boundary values
    - **Property 7: Turn count equals min(message pairs, tier maximum)**
    - Generate random message lists and random tier, assert `calculateTurns` == `min(len ~/ 2, tierMax)`
    - **Validates: Requirements 5.3, 5.4, 5.5, 5.6, 5.7, 6.1**

  - [x] 5.3 Create ContextWindowIndicator widget
    - Create `lib/presentation/widgets/context_window_indicator.dart`
    - Display progress bar showing token usage ratio with numeric label "X / 4096"
    - Display turn count "N / M turns"
    - Apply color changes: default → amber at 75%, red at 90%
    - Integrate into `ChatScreen` (below app bar or as a compact bar)
    - Updates within 500ms of message send/receive (via provider watch)
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.1, 6.2, 6.3_

- [ ] 6. Checkpoint - Ensure context window and RAG tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement Clipboard Bubble UI Overlay
  - [x] 7.1 Create ClipboardBubbleNotifier provider
    - Create `lib/presentation/providers/clipboard_bubble_provider.dart`
    - Define `ClipboardBubbleState` enum (hidden, showing, streaming, completed, error)
    - Define `ClipboardBubbleData` class (state, event, actions, responseText, errorMessage, timerSuppressed)
    - Implement `truncatePreview(text, maxLength: 80)` — return text if ≤80 chars, else substring(0,80) + '…'
    - Implement `showBubble(ClipboardEvent)` — set state to showing, populate actions from ClipboardAiService.getSuggestedActions(), start 8s auto-dismiss timer
    - Implement `executeAction(actionId)` — call ClipboardAiService.executeAction(), if Stream returned → set streaming state, render tokens, on complete → show "Copy Result" button; if null → dismiss immediately
    - Implement `dismiss()` — cancel active stream, reset state to hidden
    - Handle new clipboard event while visible: dismiss current, show new within 500ms
    - Suppress auto-dismiss timer during streaming/completed states
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.8, 7.9, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

  - [ ]* 7.2 Write property test for clipboard preview truncation
    - **Property 8: Clipboard preview truncation**
    - Generate random strings (length 0–500), assert `truncatePreview(s)` returns s if ≤80, else s.substring(0,80)+'…'
    - **Validates: Requirements 7.2**

  - [x] 7.3 Create ClipboardBubbleOverlay widget
    - Create `lib/presentation/widgets/clipboard_bubble_overlay.dart`
    - Wrap in MaterialApp `builder:` alongside VoiceAssistantOverlay (Stack with both overlays)
    - Position: bottom edge 80dp above screen bottom, horizontally centered
    - Display: content type badge, truncated preview, up to 4 action buttons
    - AI response area: expandable scrollable region below actions, loading indicator during stream, "Copy Result" button on complete
    - Animations: fade-out on auto-dismiss (400ms), quick dismiss on action tap (300ms)
    - Tap outside or swipe away → dismiss
    - Error state: show error for 2s then dismiss
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

  - [x] 7.4 Wire ClipboardBubbleOverlay into main.dart
    - Update `main.dart` builder to wrap VoiceAssistantOverlay's child with ClipboardBubbleOverlay (or Stack both)
    - Connect ClipboardAiService events to ClipboardBubbleNotifier.showBubble()
    - Ensure clipboard events trigger bubble display when feature is enabled
    - _Requirements: 7.1, 7.7_

- [ ] 8. Checkpoint - Ensure clipboard bubble tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Implement Automation Engine
  - [x] 9.1 Create AutomationRule domain model
    - Create `lib/features/automation/domain/automation_rule.dart`
    - Define `TriggerType` enum (scheduled, recurring, conditionBased)
    - Define `AutomationRule` class with all fields per design (id, name, triggerType, scheduledTime, repeatInterval, condition, checkInterval, actionInstruction, isEnabled, lastExecutedAt, createdAt, updatedAt)
    - Define `ValidationError` class (field, message)
    - _Requirements: 9.1, 9.4_

  - [x] 9.2 Create AutomationRepository data layer
    - Create `lib/features/automation/data/automation_repository.dart`
    - Implement CRUD operations: insertRule, updateRule, deleteRule, getRule, getAllRules, getRuleCount
    - Use `DatabaseHelper` for sqflite access
    - Map between AutomationRule and database row (DateTime ↔ milliseconds, Duration ↔ minutes)
    - Register as `automationRepositoryProvider`
    - _Requirements: 9.2, 11.1_

  - [x] 9.3 Create AutomationEngine service with validation and CRUD
    - Create `lib/features/automation/application/automation_engine.dart`
    - Implement `validateRule(rule)` — check name 1-100 chars, actionInstruction 1-500 chars, trigger constraints (future time, ≥15min interval, check interval 15min-24h)
    - Implement `createRule()` — validate, check 50-rule limit, persist, register workmanager task, rollback on failure
    - Implement `updateRule()` — cancel old task, update DB, register new task
    - Implement `deleteRule()` — cancel task, remove from DB
    - Implement `setEnabled()` — toggle + register/cancel workmanager task
    - Implement `getAllRules()`
    - Implement `truncateNotification(response, maxLength: 256)` — truncate with ellipsis
    - Register as `automationEngineProvider`
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 11.2, 11.3, 11.5, 11.6, 11.7_

  - [ ]* 9.4 Write property tests for automation validation and truncation
    - **Property 9: Automation rule validation accepts valid rules and rejects invalid ones**
    - Generate random AutomationRule instances (valid and invalid), assert validateRule returns empty list iff all constraints met
    - **Property 10: Notification response truncation**
    - Generate random strings (0–1000 chars), assert truncateNotification returns s if ≤256 else s.substring(0,256)+'…'
    - **Validates: Requirements 9.2, 9.3, 9.4, 10.3**

  - [x] 9.5 Extend workmanager callbackDispatcher for automation tasks
    - In `lib/core/services/background_service.dart`, add handler for `automation_rule_task`
    - Extract ruleId from inputData, initialize DatabaseHelper and AutomationRepository in background isolate
    - Load rule, check if enabled, execute action via OrchestratorService.processMessage()
    - Deliver result via flutter_local_notifications (truncated to 256 chars)
    - On failure: send error notification, log
    - Always update rule's lastExecutedAt timestamp
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6_

  - [ ]* 9.6 Write unit tests for automation rule execution flow
    - Mock OrchestratorService, DatabaseHelper, NotificationService
    - Test: successful execution updates lastExecutedAt and sends notification
    - Test: failed execution sends error notification and still updates timestamp
    - Test: disabled rule skips execution
    - **Validates: Requirements 10.1, 10.4, 10.6**

- [x] 10. Implement Automation Management UI
  - [x] 10.1 Create AutomationManagementScreen
    - Create `lib/presentation/screens/automation_management_screen.dart`
    - Display list of all rules: name, trigger description, enabled toggle, last execution time (or "Never executed")
    - Add FAB or button to create new rule
    - Enable/disable toggle calls `automationEngine.setEnabled()`
    - Delete with confirmation dialog, calls `automationEngine.deleteRule()`
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

  - [x] 10.2 Create rule creation/edit form
    - Create rule form widget with: name field (1-100 chars), trigger type selector, trigger config fields (datetime picker for scheduled, interval picker for recurring, condition text + check interval for condition-based), action instruction textarea (1-500 chars)
    - Show validation errors per field on save attempt
    - On save: call `automationEngine.createRule()` or `updateRule()`
    - Handle workmanager registration failure: show error, revert
    - _Requirements: 9.1, 9.4, 9.5, 11.6, 11.7_

  - [x] 10.3 Add navigation to AutomationManagementScreen
    - Add route or navigation entry from settings/main menu to the automation screen
    - _Requirements: 11.1_

- [x] 11. Final integration and wiring
  - [x] 11.1 Wire ContextWindowNotifier into ChatScreen message flow
    - After each message send/receive in ChatNotifier, call `contextWindowNotifier.recalculate(messages)`
    - Ensure update completes within 500ms
    - On model tier change, trigger recalculate with new tier
    - _Requirements: 5.2, 6.2, 6.3_

  - [x] 11.2 Connect ClipboardAiService events to bubble notifier
    - Ensure that when `_handleMethodCall` receives clipboard content, it triggers `ClipboardBubbleNotifier.showBubble()`
    - This may require adding a callback/listener pattern or using a StreamController in ClipboardAiService that the notifier watches
    - _Requirements: 7.1_

  - [ ]* 11.3 Write integration tests for key flows
    - Test export flow: messages → Markdown/PDF → temp file → share_plus called → cleanup
    - Test RAG flow: intent detection → RAGAgent → DocumentService mock → LLM mock → response with citations
    - Test automation create flow: create rule → DB persisted → workmanager registered
    - **Validates: Requirements 1.1, 4.2, 9.2**

- [ ] 12. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- The `pdf` package is the only new dependency; all other integrations use existing packages
- RAGAgent refactor replaces existing stub code — no new file creation needed for that file
- ClipboardBubbleOverlay follows the VoiceAssistantOverlay pattern already in main.dart
- Background automation execution runs in a workmanager isolate with minimal service initialization

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "9.1"] },
    { "id": 1, "tasks": ["2.1", "4.1", "5.1", "7.1", "9.2"] },
    { "id": 2, "tasks": ["2.2", "2.3", "4.2", "4.3", "5.2", "7.2", "9.3"] },
    { "id": 3, "tasks": ["2.4", "2.5", "5.3", "7.3", "9.4", "9.5"] },
    { "id": 4, "tasks": ["7.4", "9.6", "10.1"] },
    { "id": 5, "tasks": ["10.2", "10.3", "11.1", "11.2"] },
    { "id": 6, "tasks": ["11.3"] }
  ]
}
```
