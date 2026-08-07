import 'package:flutter/material.dart';
import 'package:aura_mobile/domain/repositories/memory_repository.dart';
import 'package:aura_mobile/domain/entities/memory.dart';
import 'package:aura_mobile/domain/services/date_time_parser.dart';
import 'package:aura_mobile/core/services/notification_service.dart';
import 'package:aura_mobile/core/services/utility_model_manager.dart';
import 'package:aura_mobile/core/providers/repository_providers.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';
import 'package:aura_mobile/data/datasources/embedding_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final memoryServiceProvider = Provider(
  (ref) => MemoryService(
    ref.read(memoryRepositoryProvider),
    ref.read(utilityModelManagerProvider.notifier),
    ref.read(embeddingServiceProvider),
  ),
);

class MemoryService {
  final MemoryRepository _repository;
  final UtilityModelManager _utilityModelManager;
  final EmbeddingService _embeddingService;
  final DateTimeParser _dateTimeParser = DateTimeParser();
  final NotificationService _notificationService = NotificationService();
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  MemoryService(
    this._repository,
    this._utilityModelManager,
    this._embeddingService,
  );

  /// Save a memory with robust error handling
  Future<void> saveMemory(String content) async {
    // 1. Validation
    if (content.trim().isEmpty) {
      throw ValidationException.emptyInput('Memory content');
    }

    if (content.length > 5000) {
      throw ValidationException.invalidInput(
        'Memory content',
        'Content too long (max 5000 characters)',
      );
    }

    try {
      // 2. Parse date/time from content (non-critical, don't fail if this errors)
      DateTime? eventDate;
      TimeOfDay? eventTime;

      try {
        final parsedDateTime = _dateTimeParser.parse(content);
        eventDate = parsedDateTime['date'] as DateTime?;
        eventTime = parsedDateTime['time'] as TimeOfDay?;
      } catch (e) {
        _errorHandler.logWarning('Date/time parsing failed for memory: $e');
        // Continue without date/time
      }

      // 3. Generate embedding if EmbeddingGemma is available (progressive enhancement)
      List<double> embedding = [];
      if (_utilityModelManager.state.isEmbeddingGemmaAvailable) {
        try {
          embedding = await _embeddingService.embed(content);
        } catch (e) {
          _errorHandler.logWarning('Embedding generation failed: $e');
        }
      }

      // 4. Create Memory entity
      final memory = Memory(
        id: const Uuid().v4(),
        content: content,
        category: 'general',
        timestamp: DateTime.now(),
        embedding: embedding.isNotEmpty ? embedding : null,
        eventDate: eventDate,
        eventTime: eventTime,
        reminderScheduled: eventDate != null,
      );

      // 5. Save to DB (critical operation)
      try {
        await _repository.saveMemory(memory);
        _errorHandler.logInfo('Memory saved successfully: ${memory.id}');
      } catch (e) {
        throw StorageException.databaseError('saveMemory', e);
      }

      // 6. Schedule notification if date exists (non-critical)
      if (eventDate != null) {
        try {
          await _notificationService.scheduleReminder(memory);
          _errorHandler.logInfo('Reminder scheduled for: $eventDate');
        } catch (e) {
          _errorHandler.logWarning(
            'Failed to schedule reminder notification: $e. Memory was still saved.',
          );
          // Don't throw - memory is already saved, notification is optional
        }
      }
    } catch (e) {
      if (e is AuraException) {
        rethrow;
      }
      // Wrap unexpected errors
      throw StorageException.databaseError('saveMemory', e);
    }
  }

  /// Retrieve relevant memories with robust error handling and fallbacks.
  ///
  /// Uses vector similarity when an embedding model is available (a weak
  /// lexical vectoriser today, not true semantic embeddings) and otherwise
  /// keyword pre-filtering, which is the active path.
  Future<List<String>> retrieveRelevantMemories(
    String query, {
    int limit = 3,
  }) async {
    // Validation
    if (query.trim().isEmpty) {
      _errorHandler.logDebug('Empty query for memory retrieval');
      return [];
    }

    try {
      // Progressive Enhancement: use semantic search if EmbeddingGemma available
      if (_utilityModelManager.state.isEmbeddingGemmaAvailable) {
        try {
          final queryEmbedding = await _embeddingService.embed(query);
          if (queryEmbedding.isNotEmpty) {
            // Cosine similarity search against stored embeddings
            final allMemories = await _repository.getMemories();
            final withEmbeddings = allMemories
                .where((m) => m.embedding != null && m.embedding!.isNotEmpty)
                .toList();
            if (withEmbeddings.isNotEmpty) {
              final scored = withEmbeddings.map((m) {
                final score = EmbeddingService.cosineSimilarity(
                  queryEmbedding,
                  m.embedding!,
                );
                return MapEntry(m, score);
              }).toList()..sort((a, b) => b.value.compareTo(a.value));

              return scored
                  .take(limit)
                  .where((e) => e.value > 0.5)
                  .map((e) => e.key.content)
                  .toList();
            }
          }
        } catch (e) {
          _errorHandler.logWarning(
            'Semantic search failed, using keyword fallback: $e',
          );
        }
      }

      // Fallback: keyword-based search (existing behavior)
      // 1. Try keyword search first (cheap, indexed by SQLite)
      List<Memory> candidates;
      try {
        candidates = await _repository.searchMemories(query);
      } catch (e) {
        // Fallback to fetching all if keyword search fails
        _errorHandler.logWarning('Keyword pre-filter failed: $e, fetching all');
        try {
          candidates = await _repository.getMemories();
        } catch (e2) {
          throw StorageException.databaseError('getMemories', e2);
        }
      }

      if (candidates.isEmpty) {
        _errorHandler.logDebug('No memory candidates found');
        return [];
      }

      // 2. If candidates are few enough, just return keyword results (fast path)
      if (candidates.length <= limit) {
        return candidates.map((m) => m.content).toList();
      }

      // 3. Return top keyword results directly.
      return candidates.take(limit).map((m) => m.content).toList();
    } catch (e) {
      if (e is AuraException) {
        _errorHandler.handleError(e);
        rethrow;
      }

      _errorHandler.logWarning('Memory retrieval failed: $e');
      return [];
    }
  }

  /// Delete a memory by ID
  Future<void> deleteMemory(String id) async {
    try {
      await _repository.deleteMemory(id);
      _errorHandler.logInfo('Memory deleted: $id');
    } catch (e) {
      throw StorageException.databaseError('deleteMemory', e);
    }
  }

  /// Get all memories (for management UI)
  Future<List<Memory>> getAllMemories() async {
    try {
      return await _repository.getMemories();
    } catch (e) {
      throw StorageException.databaseError('getAllMemories', e);
    }
  }

  /// Clear all memories
  Future<void> clearAllMemories() async {
    try {
      final memories = await _repository.getMemories();
      for (var memory in memories) {
        await _repository.deleteMemory(memory.id);
      }
      _errorHandler.logInfo('All memories cleared');
    } catch (e) {
      throw StorageException.databaseError('clearAllMemories', e);
    }
  }
}
