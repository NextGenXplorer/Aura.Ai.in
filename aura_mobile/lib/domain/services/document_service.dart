
import 'dart:io';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/domain/entities/document.dart';
import 'package:aura_mobile/domain/repositories/document_repository.dart';
import 'package:aura_mobile/domain/services/vector_store_service.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';
import 'package:aura_mobile/core/services/error_handler_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:read_pdf_text/read_pdf_text.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:aura_mobile/data/repositories/document_repository_impl.dart';

final documentServiceProvider = Provider((ref) => DocumentService(
  ref.read(runAnywhereProvider),
  ref.read(documentRepositoryProvider),
  VectorStoreService(),
));

class DocumentService {
  final RunAnywhere _aiService;
  final DocumentRepository _repository;
  final VectorStoreService _vectorStore;
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  // Configuration
  static const int _maxFileSizeMB = 50;
  static const int _chunkSize = 500;
  static const double _similarityThreshold = 0.65;

  DocumentService(this._aiService, this._repository, this._vectorStore);

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
        text = await _errorHandler.executeWithRetry(
          operation: () => ReadPdfText.getPDFtext(file.path),
          operationName: 'Extract PDF text',
          maxAttempts: 2,
        ) ?? '';
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

  /// Process document chunks with partial failure handling
  Future<void> _processChunks(String docId, List<String> chunks) async {
    if (!_aiService.isModelLoaded) {
      throw AIServiceException.modelNotLoaded();
    }

    List<DocumentChunk> successfulChunks = [];
    int failedChunks = 0;

    for (int i = 0; i < chunks.length; i++) {
      final chunkContent = chunks[i];

      try {
        // Generate embedding with retry
        final embedding = await _errorHandler.executeWithRetry(
          operation: () => _aiService.getEmbeddings(chunkContent),
          operationName: 'Generate chunk $i embedding',
          maxAttempts: 3,
        );

        if (embedding != null && embedding.isNotEmpty) {
          successfulChunks.add(DocumentChunk(
            id: const Uuid().v4(),
            documentId: docId,
            content: chunkContent,
            chunkIndex: i,
            embedding: embedding,
          ));
        } else {
          failedChunks++;
          _errorHandler.logWarning('Chunk $i: empty embedding returned');
        }
      } catch (e) {
        failedChunks++;
        _errorHandler.logWarning(
          'Failed to generate embedding for chunk $i: $e',
        );

        // Allow up to 20% failure rate
        if (failedChunks > chunks.length * 0.2) {
          throw AIServiceException(
            message: 'Too many chunk processing failures',
            technicalDetails: 'Failed $failedChunks/${chunks.length} chunks',
            recoverySuggestion: 'The AI model may be unstable. Try reloading the model.',
            errorCode: 'DOCUMENT_CHUNK_PROCESSING_FAILED',
          );
        }
      }

      // Progress logging every 10 chunks
      if ((i + 1) % 10 == 0) {
        _errorHandler.logDebug('Processed ${i + 1}/${chunks.length} chunks');
      }
    }

    // Save all successful chunks in a batch
    if (successfulChunks.isEmpty) {
      throw AIServiceException(
        message: 'No chunks were successfully processed',
        technicalDetails: 'All embeddings failed for document $docId',
        recoverySuggestion: 'Try reloading the AI model',
        errorCode: 'DOCUMENT_NO_CHUNKS_PROCESSED',
      );
    }

    try {
      await _repository.saveChunks(successfulChunks);
      _errorHandler.logInfo(
        'Saved ${successfulChunks.length}/${chunks.length} chunks (${failedChunks} failed)',
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

  /// Retrieve relevant document chunks for a query
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
      // 1. Check if model is loaded
      if (!_aiService.isModelLoaded) {
        throw AIServiceException.modelNotLoaded();
      }

      // 2. Generate query embedding with retry
      List<double>? queryEmbedding;
      try {
        queryEmbedding = await _errorHandler.executeWithRetry(
          operation: () => _aiService.getEmbeddings(query),
          operationName: 'Generate document query embedding',
          maxAttempts: 2,
        );
      } catch (e) {
        throw AIServiceException.embeddingFailed(query, e);
      }

      if (queryEmbedding == null || queryEmbedding.isEmpty) {
        _errorHandler.logWarning('Empty embedding for document query');
        return [];
      }

      // 3. Fetch all chunks
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

      // 4. Calculate similarities
      final scoredChunks = allChunks
          .where((chunk) => chunk.embedding != null && chunk.embedding!.isNotEmpty)
          .map((chunk) {
        try {
          final score = _vectorStore.cosineSimilarity(
            queryEmbedding!,
            chunk.embedding!,
          );
          return MapEntry(chunk, score);
        } catch (e) {
          _errorHandler.logDebug(
            'Similarity calculation failed for chunk ${chunk.id}: $e',
          );
          return MapEntry(chunk, 0.0);
        }
      }).toList();

      // 5. Sort and filter
      scoredChunks.sort((a, b) => b.value.compareTo(a.value));

      final results = scoredChunks
          .take(limit)
          .where((entry) => entry.value > _similarityThreshold)
          .map((entry) => entry.key.content)
          .toList();

      _errorHandler.logDebug(
        'Document search returned ${results.length} chunks (threshold: $_similarityThreshold)',
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
