# Requirements Document

## Introduction

This document specifies five high-impact productivity features for AURA Mobile, an offline, on-device AI assistant built with Flutter. These features enhance the app's utility by enabling conversation export/sharing, document-based Q&A via RAG, context window visibility, smart clipboard assistance, and user-configurable proactive automations. All features leverage existing infrastructure (Riverpod state management, sqflite persistence, workmanager background tasks, flutter_local_notifications, share_plus, and the dual-engine LLM service).

## Glossary

- **Chat_Export_Service**: The service responsible for converting chat conversations from `ChatState.messages` into exportable formats (PDF, Markdown) and triggering platform share intents via `share_plus`.
- **RAG_Agent**: The agent (`RAGAgent`) responsible for answering user queries by retrieving relevant document chunks from `DocumentService.retrieveRelevantContext()` and feeding them as context to the LLM for grounded responses.
- **Context_Window_Indicator**: A UI widget in the chat screen that displays the current token usage relative to the 4096-token context window limit.
- **Clipboard_Bubble_UI**: A floating overlay widget that appears when `ClipboardAiService` detects new clipboard content, displaying suggested actions for the detected content type.
- **Automation_Engine**: The system that manages user-defined scheduled/conditional rules, persists them to the local database, registers background tasks via `workmanager`, and dispatches actions through the `OrchestratorService` when triggers fire.
- **Orchestrator**: The `OrchestratorService` that routes user messages through intent detection and dispatches to appropriate handlers (LLM, memory, web, app control, etc.).
- **Context_Builder**: The `ContextBuilderService` that assembles prompts including system instructions, memories, document context, and chat history for LLM inference.
- **Document_Service**: The existing `DocumentService` that handles PDF ingestion, text chunking, embedding generation, and vector similarity retrieval.
- **LLM_Service**: The `LLMService` providing on-device AI inference via dual engines (GGUF/fllama and LiteRT/flutter_gemma) with a 4096-token context window.
- **Token_Count**: An approximate measure of text length used by the LLM, where 1 token ≈ 4 characters of English text.
- **Automation_Rule**: A user-defined trigger-action pair specifying when (schedule or condition) and what (action routed through the Orchestrator) should execute automatically.
- **Turn**: A single message exchange consisting of one user message and one assistant response, counted as one turn for context window tracking purposes.

## Requirements

### Requirement 1: Export Conversation as Markdown

**User Story:** As a user, I want to export my chat conversation as a Markdown file, so that I can save or reference the conversation outside the app.

#### Acceptance Criteria

1. WHEN the user taps the export button and selects "Markdown" format, THE Chat_Export_Service SHALL convert all messages in the current `ChatState.messages` list into a Markdown-formatted string where each message is rendered as a bold role label (e.g., **User**, **Assistant**) followed by a timestamp in "yyyy-MM-dd HH:mm" format on the same line, and the message body on the next line, with each message separated by a horizontal rule.
2. WHEN the Markdown content is generated, THE Chat_Export_Service SHALL write the content to a temporary file named using the pattern `chat_export_<yyyy-MM-dd_HHmmss>.md` in the app's temporary directory, where the timestamp reflects the moment of export.
3. WHEN the temporary file is created, THE Chat_Export_Service SHALL invoke `share_plus` to present the platform share sheet with the file attached.
4. IF the current conversation contains zero messages, THEN THE Chat_Export_Service SHALL display a snackbar message indicating that there is nothing to export, and the snackbar SHALL remain visible for at least 3 seconds.
5. WHEN the export completes or the share sheet is dismissed, THE Chat_Export_Service SHALL delete the temporary file from storage. IF the deletion fails, THEN THE Chat_Export_Service SHALL log the failure and continue without displaying an error to the user.
6. IF the file write operation or the share sheet invocation fails, THEN THE Chat_Export_Service SHALL display a snackbar message indicating that the export could not be completed, and SHALL not leave a partial temporary file on disk.

### Requirement 2: Export Conversation as PDF

**User Story:** As a user, I want to export my chat conversation as a PDF document, so that I can share a formatted version via email or messaging apps.

#### Acceptance Criteria

1. WHEN the user taps the export button and selects "PDF" format, THE Chat_Export_Service SHALL generate a PDF document containing all messages from `ChatState.messages` displayed in chronological order, where each message includes the sender role label, the timestamp in the device's locale format, and the message body rendered with a minimum font size of 10pt and a maximum of 1000 messages.
2. WHEN the PDF document is generated, THE Chat_Export_Service SHALL write it to a temporary file named using the pattern `chat_export_<yyyy-MM-dd_HHmmss>.pdf` in the app's temporary directory, where the timestamp reflects the moment of export.
3. WHEN the temporary PDF file is created, THE Chat_Export_Service SHALL invoke `share_plus` to present the platform share sheet with the PDF file attached.
4. IF PDF generation fails due to insufficient storage, THEN THE Chat_Export_Service SHALL display an error message indicating insufficient storage space and SHALL NOT present the share sheet.
5. IF `ChatState.messages` is empty when the user taps the export button and selects "PDF" format, THEN THE Chat_Export_Service SHALL display an informational message indicating there are no messages to export and SHALL NOT generate a PDF file.
6. IF PDF generation fails due to a reason other than insufficient storage, THEN THE Chat_Export_Service SHALL display an error message indicating that the export could not be completed and SHALL NOT present the share sheet.
7. WHILE PDF generation is in progress, THE Chat_Export_Service SHALL display a loading indicator and SHALL cancel the operation if it exceeds 30 seconds, displaying a timeout error message to the user.

### Requirement 3: Share Conversation to Specific Apps

**User Story:** As a user, I want to share my exported conversation directly to WhatsApp or email, so that I can quickly send conversations to specific contacts.

#### Acceptance Criteria

1. WHEN the platform share sheet is presented, THE Chat_Export_Service SHALL include the exported file (PDF or Markdown) as a shareable attachment with the appropriate MIME type (`application/pdf` for PDF, `text/markdown` for Markdown) accessible to all installed sharing targets including WhatsApp and email clients.
2. WHEN sharing a Markdown export, THE Chat_Export_Service SHALL include both the file attachment and the Markdown content as plain text in the share intent, so that apps not supporting file attachments can still receive the conversation text.
3. IF the share sheet invocation fails or `share_plus` throws an exception, THEN THE Chat_Export_Service SHALL display an error message indicating that the share could not be completed and SHALL clean up any temporary files.

### Requirement 4: RAG Document Query via RAG_Agent

**User Story:** As a user, I want to ask questions about my uploaded documents and receive grounded answers, so that I can quickly find information in my personal files.

#### Acceptance Criteria

1. WHEN the user sends a message and the Orchestrator detects intent `document_query`, THE RAG_Agent SHALL call `DocumentService.retrieveRelevantContext()` with the user's query to retrieve at most 10 matching document chunks ranked by similarity score.
2. WHEN `DocumentService.retrieveRelevantContext()` returns one or more document chunks, THE RAG_Agent SHALL construct a prompt containing the retrieved chunks as context and the user's question, and stream the LLM response back to the user.
3. IF `DocumentService.retrieveRelevantContext()` returns an empty result set, THEN THE RAG_Agent SHALL inform the user that no relevant information was found in their uploaded documents.
4. IF the AI model is not loaded when a document query is received, THEN THE RAG_Agent SHALL inform the user that a model must be loaded before document queries can be answered and SHALL NOT call `DocumentService.retrieveRelevantContext()`.
5. WHEN the RAG_Agent streams a response sourced from document chunks, THE RAG_Agent SHALL append a citation list after the response body identifying each source document by its file name.
6. IF the LLM fails or stops producing tokens during a RAG response stream, THEN THE RAG_Agent SHALL return an error message indicating that the response could not be completed and SHALL retain the model in a loaded state for subsequent queries.
7. WHEN multiple retrieved chunks originate from different documents, THE RAG_Agent SHALL include a separate citation entry for each distinct source document referenced in the answer.

### Requirement 5: Context Window Token Count Display

**User Story:** As a user, I want to see how much of the AI's context window is being used, so that I can understand when the model might start forgetting earlier parts of our conversation.

#### Acceptance Criteria

1. THE Context_Window_Indicator SHALL display a visual meter (progress bar or gauge) showing the ratio of estimated tokens used to the 4096-token context window capacity, accompanied by a numeric label displaying the estimated token count and the 4096-token maximum (e.g., "1200 / 4096").
2. WHEN the user sends or receives a message, THE Context_Window_Indicator SHALL update the token count estimate within 500 milliseconds, based on the current prompt assembled by Context_Builder (including system prompt, memories, document context, and chat history).
3. WHEN the estimated token usage exceeds 75% of the 4096-token capacity (3072 tokens), THE Context_Window_Indicator SHALL change its visual state to a warning color (amber).
4. WHEN the estimated token usage exceeds 90% of the 4096-token capacity (3686 tokens), THE Context_Window_Indicator SHALL change its visual state to a critical color (red).
5. WHEN the estimated token usage drops to 75% or below of the 4096-token capacity after having previously exceeded 75%, THE Context_Window_Indicator SHALL revert its visual state from the warning color to the default color.
6. WHEN the estimated token usage drops to 90% or below of the 4096-token capacity after having previously exceeded 90%, THE Context_Window_Indicator SHALL revert its visual state from the critical color to the warning color if usage remains above 75%, or to the default color if usage is at or below 75%.
7. THE Context_Window_Indicator SHALL estimate token count by dividing the total number of characters in the assembled prompt (including whitespace and special characters) by 4 and rounding up to the nearest integer.
8. WHEN no messages have been exchanged in the current session, THE Context_Window_Indicator SHALL display the token count reflecting only the system prompt and any pre-loaded context from Context_Builder.

### Requirement 6: Context Window History Limit Display

**User Story:** As a user, I want to know how many conversation turns the model currently remembers, so that I have clear expectations about conversation continuity.

#### Acceptance Criteria

1. THE Context_Window_Indicator SHALL display the number of conversation history turns currently included in the context (out of the maximum allowed: 4 for small models, 6 for medium models, 10 for large models), where a turn is defined as one user message and one assistant response counted together as a single turn.
2. WHEN the model tier changes (e.g., user switches models), THE Context_Window_Indicator SHALL update the displayed maximum history turns to reflect the new tier's limit within 500 milliseconds of the model change completing.
3. WHEN a new message is sent or received, THE Context_Window_Indicator SHALL recalculate and display the current turn count based on the number of history entries included in the last assembled prompt.

### Requirement 7: Clipboard Bubble UI Overlay Display

**User Story:** As a user, I want to see a floating bubble with AI-suggested actions when I copy text, so that I can quickly act on clipboard content without opening the full app.

#### Acceptance Criteria

1. WHEN `ClipboardAiService` detects new clipboard content and the clipboard feature is enabled, THE Clipboard_Bubble_UI SHALL appear as a floating overlay widget positioned with its bottom edge 80dp above the bottom of the screen, horizontally centered.
2. WHEN the Clipboard_Bubble_UI appears, THE Clipboard_Bubble_UI SHALL display the detected content type (URL, phone, email, code, address, or text) and a preview of the clipboard content (truncated to 80 characters with an ellipsis appended if truncated).
3. WHEN the Clipboard_Bubble_UI appears, THE Clipboard_Bubble_UI SHALL display a list of suggested actions returned by `ClipboardAiService.getSuggestedActions()` for the detected content type, showing a maximum of 4 actions.
4. WHEN the user taps a suggested action in the Clipboard_Bubble_UI, THE Clipboard_Bubble_UI SHALL invoke `ClipboardAiService.executeAction()` with the selected action ID and dismiss the bubble within 300 milliseconds.
5. IF the user taps outside the Clipboard_Bubble_UI or swipes it away, THEN THE Clipboard_Bubble_UI SHALL dismiss without executing any action.
6. WHEN the Clipboard_Bubble_UI has been visible for 8 seconds without user interaction, THE Clipboard_Bubble_UI SHALL auto-dismiss with a fade-out animation lasting 400 milliseconds.
7. THE Clipboard_Bubble_UI SHALL follow the existing overlay pattern established by `VoiceAssistantOverlay` (wrapping MaterialApp in the builder, using Stack with AnimatedPositioned).
8. IF `ClipboardAiService` detects new clipboard content while the Clipboard_Bubble_UI is already visible, THEN THE Clipboard_Bubble_UI SHALL dismiss the current bubble and display a new bubble with the updated content and suggested actions within 500 milliseconds.
9. IF `ClipboardAiService.executeAction()` returns null or throws an error after the user taps a suggested action, THEN THE Clipboard_Bubble_UI SHALL dismiss the bubble and display a brief error indication for 2 seconds before disappearing.

### Requirement 8: Clipboard Bubble AI Response Display

**User Story:** As a user, I want to see the AI's response to clipboard actions inline in the bubble, so that I get results without navigating to the chat screen.

#### Acceptance Criteria

1. WHEN a clipboard action returns a Stream of AI response text (e.g., summarize, explain code, translate), THE Clipboard_Bubble_UI SHALL display a loading indicator and expand to show a scrollable response area below the action buttons, rendering each text token as it arrives from the stream.
2. WHEN the AI response stream completes, THE Clipboard_Bubble_UI SHALL hide the loading indicator and display a "Copy Result" button allowing the user to copy the full response text to the system clipboard.
3. IF a clipboard action is a direct dispatch (returns null, e.g., open browser, call number), THEN THE Clipboard_Bubble_UI SHALL dismiss within one animation frame after dispatching the action.
4. IF the AI response stream emits an error before or during token delivery, THEN THE Clipboard_Bubble_UI SHALL stop the loading indicator, display an error message indicating that the action failed, and retain any partial response text already rendered.
5. WHILE the Clipboard_Bubble_UI is displaying a streaming AI response or a completed AI response, THE Clipboard_Bubble_UI SHALL suppress the 8-second auto-dismiss timer defined in Requirement 7.
6. IF the user dismisses the Clipboard_Bubble_UI (tap outside or swipe) while an AI response stream is active, THEN THE Clipboard_Bubble_UI SHALL cancel the active stream subscription and dismiss without copying any result.

### Requirement 9: Create Automation Rule

**User Story:** As a user, I want to create custom automation rules with time-based or condition-based triggers, so that the AI performs tasks proactively on my behalf.

#### Acceptance Criteria

1. WHEN the user opens the automation management screen, THE Automation_Engine SHALL display a form allowing the user to define a rule with: a name between 1 and 100 characters, a trigger type (scheduled time, recurring schedule, or condition-based), and an action instruction (natural language text between 1 and 500 characters processed by the Orchestrator).
2. WHEN the user saves an automation rule with a scheduled trigger, THE Automation_Engine SHALL validate that a scheduled-time trigger specifies a date and time in the future, and that a recurring-schedule trigger specifies a repeat interval of at least 15 minutes, persist the rule to the local database via `DatabaseHelper`, and register the corresponding one-time or periodic background task via `workmanager`.
3. WHEN the user saves an automation rule with a condition-based trigger, THE Automation_Engine SHALL persist the rule and register a periodic check task via `workmanager` that evaluates the condition at a user-specified interval between 15 minutes and 24 hours inclusive, defaulting to 1 hour if the user does not specify an interval.
4. THE Automation_Engine SHALL validate that every rule has a name between 1 and 100 characters, a trigger configuration that satisfies the constraints for its type (future date-time for scheduled, repeat interval of at least 15 minutes for recurring, evaluation interval between 15 minutes and 24 hours for condition-based), and a non-empty action instruction of at most 500 characters before saving.
5. IF the user attempts to save a rule with invalid or incomplete fields, THEN THE Automation_Engine SHALL prevent saving and display a validation error message for each field that fails validation, indicating the specific constraint that was not met.
6. IF the Automation_Engine successfully persists a rule but `workmanager` fails to register the background task, THEN THE Automation_Engine SHALL remove the persisted rule from the local database, display an error message indicating that the rule could not be activated, and leave no orphaned rule in the database.
7. THE Automation_Engine SHALL allow the user to create a maximum of 50 automation rules; IF the user attempts to create a rule when 50 rules already exist, THEN THE Automation_Engine SHALL prevent creation and display an error message indicating the rule limit has been reached.

### Requirement 10: Execute Automation Rule

**User Story:** As a user, I want my saved automation rules to execute automatically at the specified triggers, so that I receive proactive assistance without manual intervention.

#### Acceptance Criteria

1. WHEN a scheduled automation rule's trigger time arrives, THE Automation_Engine SHALL send the rule's action instruction to the Orchestrator via `OrchestratorService.processMessage()` for processing.
2. WHEN a condition-based automation rule's periodic check evaluates the condition as true, THE Automation_Engine SHALL send the rule's action instruction to the Orchestrator for processing.
3. WHEN an automation rule executes successfully, THE Automation_Engine SHALL deliver the result to the user via `flutter_local_notifications` with the AI's response as the notification body, truncated to 256 characters with an ellipsis if the response exceeds that length.
4. IF an automation rule execution fails (model not loaded, Orchestrator error), THEN THE Automation_Engine SHALL deliver an error notification to the user indicating the failure reason and log the failure with a timestamp for retry at the next scheduled check.
5. WHILE the device is offline and the app is in the background, THE Automation_Engine SHALL execute rules using `workmanager` background execution with the on-device LLM (no network required).
6. WHEN an automation rule executes, THE Automation_Engine SHALL update the rule's last execution timestamp in the database regardless of success or failure.

### Requirement 11: Manage Automation Rules

**User Story:** As a user, I want to view, edit, enable/disable, and delete my automation rules, so that I maintain control over what actions run automatically.

#### Acceptance Criteria

1. WHEN the user opens the automation management screen, THE Automation_Engine SHALL display a list of all saved automation rules showing each rule's name, trigger description, enabled/disabled status, and last execution time, or a "Never executed" indicator if the rule has not yet run.
2. WHEN the user toggles a rule's enabled status to enabled, THE Automation_Engine SHALL update the rule's status to enabled in the database and register the corresponding `workmanager` task for that rule.
3. WHEN the user toggles a rule's enabled status to disabled, THE Automation_Engine SHALL update the rule's status to disabled in the database and cancel the corresponding `workmanager` task for that rule.
4. WHEN the user initiates deletion of an automation rule, THE Automation_Engine SHALL present a confirmation prompt before proceeding with the deletion.
5. WHEN the user confirms deletion of an automation rule, THE Automation_Engine SHALL remove the rule from the database and cancel its registered `workmanager` task.
6. WHEN the user edits an automation rule and saves changes, THE Automation_Engine SHALL cancel the existing `workmanager` task, update the rule in the database, and register a new task with the updated configuration.
7. IF a `workmanager` task fails to register or cancel during a rule status change, edit, or deletion, THEN THE Automation_Engine SHALL display an error message indicating the operation failed and revert the rule to its previous state in the database.
