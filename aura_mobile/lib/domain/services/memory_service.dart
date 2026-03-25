import 'package:flutter/material.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:aura_mobile/domain/repositories/memory_repository.dart';
import 'package:aura_mobile/domain/entities/memory.dart';
import 'package:aura_mobile/domain/services/vector_store_service.dart';
import 'package:aura_mobile/domain/services/date_time_parser.dart';
import 'package:aura_mobile/core/services/notification_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/core/providers/repository_providers.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final memoryServiceProvider = Provider((ref) => MemoryService(
  ref.read(runAnywhereProvider),
  ref.read(memoryRepositoryProvider),
  VectorStoreService(),
));

class MemoryService {
  final RunAnywhere _aiService;
  final MemoryRepository _repository;
  final VectorStoreService _vectorStore;
  final DateTimeParser _dateTimeParser = DateTimeParser();
  final NotificationService _notificationService = NotificationService();
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  MemoryService(this._aiService, this._repository, this._vectorStore);

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

      // 3. Generate Embedding (critical operation)
      List<double> embedding = [];

      if (!_aiService.isModelLoaded) {
        _errorHandler.logWarning(
          'AI model not loaded when saving memory. Saving without embeddings.',
        );
        // Continue without embeddings - we can use keyword search as fallback
      } else {
        try {
          embedding = await _errorHandler.executeWithRetry(
            operation: () => _aiService.getEmbeddings(content),
            operationName: 'Generate memory embedding',
            maxAttempts: 2,
            onFinalError: (error) {
              _errorHandler.logWarning(
                'Failed to generate embedding for memory after retries: $error',
              );
              return <double>[]; // Return empty list to continue without embeddings
            },
          ) ?? [];
        } catch (e) {
          _errorHandler.logWarning('Embedding generation failed: $e');
          // Continue without embeddings
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

  /// Retrieve relevant memories with robust error handling and fallbacks
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
      // 1. Fetch all memories (with error handling)
      List<Memory> allMemories;
      try {
        allMemories = await _repository.getMemories();
      } catch (e) {
        throw StorageException.databaseError('getMemories', e);
      }

      if (allMemories.isEmpty) {
        _errorHandler.logDebug('No memories found in database');
        return [];
      }

      // 2. Try vector search first (if model is loaded)
      if (_aiService.isModelLoaded) {
        try {
          final queryEmbedding = await _errorHandler.executeWithRetry(
            operation: () => _aiService.getEmbeddings(query),
            operationName: 'Generate query embedding',
            maxAttempts: 2,
          );

          if (queryEmbedding != null && queryEmbedding.isNotEmpty) {
            final vectorResults = _performVectorSearch(
              queryEmbedding,
              allMemories,
              limit,
            );

            if (vectorResults.isNotEmpty) {
              _errorHandler.logDebug(
                'Vector search returned ${vectorResults.length} results',
              );
              return vectorResults;
            }
          }
        } catch (e) {
          _errorHandler.logWarning('Vector search failed: $e. Falling back to keyword search.');
        }
      } else {
        _errorHandler.logDebug('Model not loaded. Using keyword search.');
      }

      // 3. Fallback to keyword search
      try {
        final keywordResults = await _repository.searchMemories(query);
        final results = keywordResults
            .take(limit)
            .map((m) => m.content)
            .toList();

        _errorHandler.logDebug(
          'Keyword search returned ${results.length} results',
        );
        return results;
      } catch (e) {
        // Keyword search is already a fallback, so if it fails, return empty list
        _errorHandler.logWarning('Keyword search also failed: $e');
        return [];
      }
    } catch (e) {
      if (e is AuraException) {
        _errorHandler.handleError(e);
        rethrow;
      }

      // Return empty list rather than failing completely
      _errorHandler.logWarning('Memory retrieval failed: $e');
      return [];
    }
  }

  /// Perform vector similarity search
  List<String> _performVectorSearch(
    List<double> queryEmbedding,
    List<Memory> memories,
    int limit,
  ) {
    try {
      // Calculate similarities
      final scoredMemories = memories
          .where((mem) => mem.embedding != null && mem.embedding!.isNotEmpty)
          .map((mem) {
        try {
          final score = _vectorStore.cosineSimilarity(
            queryEmbedding,
            mem.embedding!,
          );
          return MapEntry(mem, score);
        } catch (e) {
          _errorHandler.logDebug(
            'Similarity calculation failed for memory ${mem.id}: $e',
          );
          return MapEntry(mem, 0.0);
        }
      }).toList();

      // Sort by score (descending)
      scoredMemories.sort((a, b) => b.value.compareTo(a.value));

      // Filter by threshold and limit
      const double similarityThreshold = 0.7;
      return scoredMemories
          .take(limit)
          .where((entry) => entry.value > similarityThreshold)
          .map((entry) => entry.key.content)
          .toList();
    } catch (e) {
      _errorHandler.logWarning('Vector search processing failed: $e');
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
