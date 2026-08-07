import 'dart:io';
import 'package:aura_mobile/domain/entities/document.dart';
import 'package:aura_mobile/domain/repositories/document_repository.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';
import 'package:aura_mobile/core/services/utility_model_manager.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/data/datasources/embedding_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:read_pdf_text/read_pdf_text.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:aura_mobile/data/repositories/document_repository_impl.dart';

final documentServiceProvider = Provider(
  (ref) => DocumentService(
    ref.read(documentRepositoryProvider),
    ref.read(utilityModelManagerProvider.notifier),
    ref.read(embeddingServiceProvider),
  ),
);

class DocumentService {
  final DocumentRepository _repository;
  final UtilityModelManager _utilityModelManager;
  final EmbeddingService _embeddingService;
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  // Configuration
  static const int _maxFileSizeMB = 50;
  static const int _chunkSize = 500;

  DocumentService(
    this._repository,
    this._utilityModelManager,
    this._embeddingService,
  );

  /// Pick and process a document from file picker
  Future<void> pickAndProcessDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.single.path == null) {
        _errorHandler.logDebug('File picker cancelled by user');
        return;
      }

      File file = File(result.files.single.path!);
      await processDocument(file);
    } catch (e) {
      if (e is AuraException) {
        rethrow;
      }
      throw StorageException.databaseError('pickDocument', e);
    }
  }

  /// Process a document file with comprehensive error handling
  Future<void> processDocument(File file) async {
    try {
      // 1. Validate file exists
      if (!await file.exists()) {
        throw StorageException.fileNotFound(file.path);
      }

      // 2. Validate file size
      final fileSizeBytes = await file.length();
      final fileSizeMB = fileSizeBytes / (1024 * 1024);

      if (fileSizeMB > _maxFileSizeMB) {
        throw ValidationException.fileTooLarge(
          fileSizeMB.ceil(),
          _maxFileSizeMB,
        );
      }

      _errorHandler.logInfo(
        'Processing document: ${p.basename(file.path)} (${fileSizeMB.toStringAsFixed(2)} MB)',
      );

      // 3. Extract text from PDF
      String text;
      try {
        text =
            await _errorHandler.executeWithRetry(
              operation: () => ReadPdfText.getPDFtext(file.path),
              operationName: 'Extract PDF text',
              maxAttempts: 2,
            ) ??
            '';
      } catch (e) {
        throw StorageException.fileCorrupted(file.path);
      }

      // 4. Validate extracted content
      if (text.trim().isEmpty) {
        throw ValidationException.invalidInput(
          'PDF content',
          'The PDF appears to be empty or contains only images',
        );
      }

      if (text.length < 50) {
        throw ValidationException.invalidInput(
          'PDF content',
          'The PDF content is too short (minimum 50 characters)',
        );
      }

      _errorHandler.logInfo('Extracted ${text.length} characters from PDF');

      // 5. Create document entity
      final docId = const Uuid().v4();
      final document = Document(
        id: docId,
        filename: p.basename(file.path),
        path: file.path,
        uploadDate: DateTime.now(),
      );

      // 6. Save document metadata
      try {
        await _repository.saveDocument(document);
      } catch (e) {
        throw StorageException.databaseError('saveDocument', e);
      }

      // 7. Chunk text
      final chunks = _chunkText(text, _chunkSize);
      _errorHandler.logInfo('Created ${chunks.length} chunks');

      // 8. Generate embeddings and save chunks
      await _processChunks(docId, chunks);

      _errorHandler.logInfo('Document processing completed: $docId');
    } catch (e) {
      if (e is AuraException) {
        _errorHandler.handleError(e);
        rethrow;
      }

      // Wrap unexpected errors
      throw StorageException.databaseError('processDocument', e);
    }
  }

  /// Process document chunks — generates embeddings with EmbeddingGemma when
  /// available, otherwise saves with empty embeddings (keyword search fallback).
  Future<void> _processChunks(String docId, List<String> chunks) async {
    List<DocumentChunk> successfulChunks = [];

    for (int i = 0; i < chunks.length; i++) {
      final chunkContent = chunks[i];

      // Generate embedding if EmbeddingGemma is available (progressive enhancement)
      List<double> embedding = [];
      if (_utilityModelManager.state.isEmbeddingGemmaAvailable) {
        try {
          embedding = await _embeddingService.embed(chunkContent);
        } catch (e) {
          _errorHandler.logWarning('Chunk embedding failed: $e');
        }
      }

      successfulChunks.add(
        DocumentChunk(
          id: const Uuid().v4(),
          documentId: docId,
          content: chunkContent,
          chunkIndex: i,
          embedding: embedding.isNotEmpty ? embedding : [],
        ),
      );

      // Progress logging every 10 chunks
      if ((i + 1) % 10 == 0) {
        _errorHandler.logDebug('Processed ${i + 1}/${chunks.length} chunks');
      }
    }

    if (successfulChunks.isEmpty) {
      throw AIServiceException(
        message: 'No chunks were successfully processed',
        technicalDetails: 'All chunks failed for document $docId',
        recoverySuggestion: 'Try reloading the AI model',
        errorCode: 'DOCUMENT_NO_CHUNKS_PROCESSED',
      );
    }

    try {
      await _repository.saveChunks(successfulChunks);
      _errorHandler.logInfo(
        'Saved ${successfulChunks.length}/${chunks.length} chunks',
      );
    } catch (e) {
      // Rollback document if chunks can't be saved
      try {
        await _repository.deleteDocument(docId);
      } catch (_) {
        // Ignore rollback errors
      }
      throw StorageException.databaseError('saveChunks', e);
    }
  }

  /// Chunk text with word boundary preservation
  List<String> _chunkText(String text, int chunkSize) {
    try {
      List<String> chunks = [];
      final cleanText = text.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (cleanText.isEmpty) return chunks;

      int start = 0;
      while (start < cleanText.length) {
        int end = start + chunkSize;

        if (end >= cleanText.length) {
          chunks.add(cleanText.substring(start));
          break;
        }

        // Backtrack to last space to avoid splitting words
        int lastSpace = cleanText.lastIndexOf(' ', end);
        if (lastSpace != -1 && lastSpace > start) {
          end = lastSpace;
        }

        final chunk = cleanText.substring(start, end).trim();
        if (chunk.isNotEmpty) {
          chunks.add(chunk);
        }

        start = end + 1; // Skip the space
      }

      return chunks;
    } catch (e) {
      _errorHandler.logWarning('Text chunking failed: $e');
      // Fallback: return the full text as a single chunk
      return [text];
    }
  }

  /// Check if documents exist in the repository
  Future<bool> hasDocuments() async {
    try {
      final docs = await _repository.getAllChunks();
      return docs.isNotEmpty;
    } catch (e) {
      _errorHandler.logWarning('hasDocuments check failed: $e');
      return false;
    }
  }

  /// Retrieve relevant document chunks for a query.
  ///
  /// Uses vector similarity when an embedding model is available (currently a
  /// weak lexical vectoriser, not true semantic embeddings) and keyword
  /// matching otherwise, which is the active path today.
  Future<List<String>> retrieveRelevantContext(
    String query, {
    int limit = 5,
  }) async {
    // Validation
    if (query.trim().isEmpty) {
      _errorHandler.logDebug('Empty query for document retrieval');
      return [];
    }

    try {
      // Progressive Enhancement: semantic search if EmbeddingGemma available
      if (_utilityModelManager.state.isEmbeddingGemmaAvailable) {
        try {
          final queryEmbedding = await _embeddingService.embed(query);
          if (queryEmbedding.isNotEmpty) {
            final allChunks = await _repository.getAllChunks();
            final withEmbeddings = allChunks
                .where((c) => c.embedding != null && c.embedding!.isNotEmpty)
                .toList();
            if (withEmbeddings.isNotEmpty) {
              final scored = withEmbeddings.map((c) {
                final score = EmbeddingService.cosineSimilarity(
                  queryEmbedding,
                  c.embedding!,
                );
                return MapEntry(c, score);
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
            'Semantic chunk search failed, using keyword fallback: $e',
          );
        }
      }

      // Fallback: existing keyword-based retrieval
      List<DocumentChunk> allChunks;
      try {
        allChunks = await _repository.getAllChunks();
      } catch (e) {
        throw StorageException.databaseError('getAllChunks', e);
      }

      if (allChunks.isEmpty) {
        _errorHandler.logDebug('No document chunks found');
        return [];
      }

      // Simple keyword match scoring
      final queryWords = query.toLowerCase().split(RegExp(r'\s+'));
      final scoredChunks = allChunks
          .map((chunk) {
            final content = chunk.content.toLowerCase();
            int score = 0;
            for (final word in queryWords) {
              if (word.length > 2 && content.contains(word)) {
                score++;
              }
            }
            return MapEntry(chunk, score);
          })
          .where((entry) => entry.value > 0)
          .toList();

      scoredChunks.sort((a, b) => b.value.compareTo(a.value));

      final results = scoredChunks
          .take(limit)
          .map((entry) => entry.key.content)
          .toList();

      _errorHandler.logDebug(
        'Document search returned ${results.length} chunks',
      );

      return results;
    } catch (e) {
      if (e is AuraException) {
        _errorHandler.handleError(e);
        rethrow;
      }

      _errorHandler.logWarning('Document context retrieval failed: $e');
      return [];
    }
  }

  /// Get all documents (for management UI)
  Future<List<Document>> getAllDocuments() async {
    try {
      return await _repository.getAllDocuments();
    } catch (e) {
      throw StorageException.databaseError('getAllDocuments', e);
    }
  }

  /// Delete a document and all its chunks
  Future<void> deleteDocument(String docId) async {
    try {
      // Delete document (implementation should cascade delete chunks)
      await _repository.deleteDocument(docId);
      _errorHandler.logInfo('Document deleted: $docId');
    } catch (e) {
      throw StorageException.databaseError('deleteDocument', e);
    }
  }

  /// Clear all documents
  Future<void> clearAllDocuments() async {
    try {
      final documents = await _repository.getAllDocuments();
      for (var doc in documents) {
        await deleteDocument(doc.id);
      }
      _errorHandler.logInfo('All documents cleared');
    } catch (e) {
      throw StorageException.databaseError('clearAllDocuments', e);
    }
  }
}
