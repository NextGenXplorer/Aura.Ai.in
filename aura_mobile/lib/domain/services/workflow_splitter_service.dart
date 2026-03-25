import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:aura_mobile/data/datasources/llm_service.dart';
import 'package:aura_mobile/domain/models/workflow_plan.dart';
import 'package:aura_mobile/domain/models/workflow_step.dart';
import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:aura_mobile/domain/services/llm_intent_classifier.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WorkflowSplitterService
//
// Detects compound multi-intent commands and decomposes them into a
// WorkflowPlan. Supports Advanced Entity Extraction (Deep Context).
// ─────────────────────────────────────────────────────────────────────────────
class WorkflowSplitterService {
  final LLMIntentClassifier _classifier;
  final LLMService _llmService;
  final IntentDetectionService _intentService;

  WorkflowSplitterService(this._classifier, this._llmService, this._intentService);

  static final _connectorRe = RegExp(
    r'\s*,?\s+(?:and\s+then|after\s+that|followed\s+by|and\s+also|'
    r'then\s+also|after\s+which|next\s+up|subsequently|thereafter|'
    r'and\s+then\s+also|once\s+done|then|also|and)[,\s]+',
    caseSensitive: false,
  );

  static final _continuationRe = RegExp(
    r'^(that|it|this|the\s+result|those|them|the\s+first|the\s+second)\b',
    caseSensitive: false,
  );

  static final _hasConnectorRe = RegExp(
    r'\b(and\s+then|after\s+that|followed\s+by|and\s+also|then\s+also|'
    r'subsequently|thereafter|and\s+then\s+also|once\s+done|'
    r'then|also)\b',
    caseSensitive: false,
  );

  /// Analyzes a message and returns a [WorkflowPlan] if it contains multiple intents.
  Future<WorkflowPlan?> splitWorkflow(String message) async {
    final trimmed = message.trim();
    if (trimmed.length < 5) return null;

    final wordCount = trimmed.split(RegExp(r'\s+')).length;

    // 1. Rule-based split (Fast Layer)
    if (_hasConnectorRe.hasMatch(trimmed)) {
      final steps = _ruleSplit(trimmed);
      if (steps.length >= 2) {
        debugPrint('WORKFLOW_SPLITTER: Layer-1 rule split → ${steps.length} steps');
        final enriched = await _enrichSteps(steps);
        return WorkflowPlan(steps: enriched);
      }
    }

    // 2. LLM-based split (Smart Layer for data flow)
    if (wordCount > 8 && _llmService.isModelLoaded) {
      final steps = await _llmSplit(trimmed);
      if (steps != null && steps.length >= 2) {
        debugPrint('WORKFLOW_SPLITTER: Layer-2 LLM split → ${steps.length} steps');
        final enriched = await _enrichSteps(steps);
        return WorkflowPlan(steps: enriched);
      }
    }

    return null;
  }

  List<WorkflowStep> _ruleSplit(String message) {
    final delimited = message.replaceAllMapped(_connectorRe, (m) => '|');
    final parts = delimited
        .split('|')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && p.split(RegExp(r'\s+')).length > 1)
        .toList();

    final merged = <String>[];
    for (final part in parts) {
      if (merged.isNotEmpty && _continuationRe.hasMatch(part)) {
        merged[merged.length - 1] = '${merged.last} $part';
      } else {
        merged.add(part);
      }
    }
    
    return merged.map((m) => WorkflowStep(rawMessage: m)).toList();
  }

  Future<List<WorkflowStep>?> _llmSplit(String message) async {
    final prompt = '''
You are the AURA Workflow Architect. Decompose compound user commands into a logical sequence of actionable steps.

**Core Rules:**
1. Split based on "and then", "after that", "also", "then", and logical transitions.
2. Return a JSON array of steps.
3. Each step must have:
   - "rawMessage": The text command for this specific step.
   - "hintType": (Optional) The best match from: webSearch, weatherSearch, appControl, navigation, reminderSet, emailDraft, normalChat.
   - "outputKey": (Optional) A camelCase name if this step produces a specific value needed by a LATER step (e.g. "meetingLink", "personName").
   - "extractionRequirement": (Optional) If outputKey is set, describe WHAT EXACTLY to pluck from the result (e.g. "The Zoom link", "The person's full name", "The price listed").
4. **Data Flow**: If a later step depends on an "outputKey", use the placeholder "{outputKey}" in its "rawMessage".

**Example:**
Input: "Find the latest email from John and then add the meeting link to my calendar at 3pm."
Output: [
  {
    "rawMessage": "Search latest email from John",
    "hintType": "emailSearch",
    "outputKey": "meetingLink",
    "extractionRequirement": "The video meeting link (Zoom, Meet, etc.)"
  },
  {
    "rawMessage": "Add {meetingLink} to my calendar at 3pm",
    "hintType": "calendarAdd"
  }
]
''';

    try {
      final buffer = StringBuffer();
      await for (final token in _llmService.chat(
        'Split this command: "$message"',
        systemPrompt: prompt,
        maxTokens: 500,
        temperature: 0.2, // Low temperature for structured JSON output
      )) {
        buffer.write(token);
      }

      final raw = buffer.toString().trim();
      final jsonMatch = RegExp(r'\[.*\]', dotAll: true).firstMatch(raw);
      if (jsonMatch == null) return null;

      final decoded = jsonDecode(jsonMatch.group(0)!);
      if (decoded is List) {
        return decoded.map((e) {
          if (e is Map<String, dynamic>) {
            return WorkflowStep.fromMap(e);
          }
          return WorkflowStep(rawMessage: e.toString());
        }).toList();
      }
    } catch (e) {
      debugPrint('WORKFLOW_SPLITTER: LLM split failed: $e');
    }
    return null;
  }

  Future<List<WorkflowStep>> _enrichSteps(List<WorkflowStep> steps) async {
    final enriched = <WorkflowStep>[];
    for (final step in steps) {
      if (step.hintType != null) {
        enriched.add(step);
        continue;
      }

      try {
        final ruleIntent = await _intentService.detectIntent(step.rawMessage);
        if (ruleIntent != IntentType.normalChat) {
          enriched.add(step.withHint(ruleIntent));
        } else if (_llmService.isModelLoaded) {
          final classified = await _classifier.classify(step.rawMessage);
          if (classified != null) {
            enriched.add(step.withHint(classified.type, classified.parameters));
          } else {
            enriched.add(step.withHint(IntentType.normalChat));
          }
        } else {
          enriched.add(step.withHint(IntentType.normalChat));
        }
      } catch (e) {
        enriched.add(step);
      }
    }
    return enriched;
  }
}
