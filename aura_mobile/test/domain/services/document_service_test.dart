import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:aura_mobile/domain/services/document_service.dart';
import 'package:aura_mobile/domain/repositories/document_repository.dart';
import 'package:aura_mobile/domain/entities/document.dart';
import 'package:aura_mobile/domain/services/vector_store_service.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';

import 'document_service_test.mocks.dart';

@GenerateMocks([RunAnywhere, DocumentRepository, VectorStoreService])
void main() {
  late DocumentService documentService;
  late MockRunAnywhere mockAiService;
  late MockDocumentRepository mockRepository;
  late MockVectorStoreService mockVectorStore;

  setUp(() {
    mockAiService = MockRunAnywhere();
    mockRepository = MockDocumentRepository();
    mockVectorStore = MockVectorStoreService();
    documentService = DocumentService(
      mockAiService,
      mockRepository,
      mockVectorStore,
    );
  });

  group('DocumentService - validation', () {
    test('hasDocuments should return true when chunks exist', () async {
      when(mockRepository.getAllChunks()).thenAnswer((_) async => [
            DocumentChunk(
              id: '1',
              documentId: 'doc1',
              content: 'test',
              chunkIndex: 0,
              embedding: [0.1, 0.2],
            ),
          ]);

      final result = await documentService.hasDocuments();

      expect(result, true);
    });

    test('hasDocuments should return false when no chunks exist', () async {
      when(mockRepository.getAllChunks()).thenAnswer((_) async => []);

      final result = await documentService.hasDocuments();

      expect(result, false);
    });

    test('hasDocuments should return false when repository throws', () async {
      when(mockRepository.getAllChunks()).thenThrow(Exception('Error'));

      final result = await documentService.hasDocuments();

      expect(result, false);
    });
  });

  group('DocumentService - retrieveRelevantContext', () {
    final testChunks = [
      DocumentChunk(
        id: '1',
        documentId: 'doc1',
        content: 'Content about AI',
        chunkIndex: 0,
        embedding: [0.1, 0.2, 0.3],
      ),
      DocumentChunk(
        id: '2',
        documentId: 'doc1',
        content: 'Content about machine learning',
        chunkIndex: 1,
        embedding: [0.9, 0.8, 0.7],
      ),
    ];

    test('should return empty list for empty query', () async {
      final results = await documentService.retrieveRelevantContext('');

      expect(results, isEmpty);
    });

    test('should throw AIServiceException when model not loaded', () async {
      when(mockAiService.isModelLoaded).thenReturn(false);

      expect(
        () => documentService.retrieveRelevantContext('test query'),
        throwsA(isA<AIServiceException>()),
      );
    });

    test('should return relevant chunks when successful', () async {
      when(mockAiService.isModelLoaded).thenReturn(true);
      when(mockAiService.getEmbeddings(any))
          .thenAnswer((_) async => [0.1, 0.2, 0.3]);
      when(mockRepository.getAllChunks())
          .thenAnswer((_) async => testChunks);
      when(mockVectorStore.cosineSimilarity(any, any)).thenReturn(0.9);

      final results = await documentService.retrieveRelevantContext('AI', limit: 5);

      verify(mockAiService.getEmbeddings('AI')).called(1);
      verify(mockVectorStore.cosineSimilarity(any, any)).called(greaterThan(0));
      expect(results, isNotEmpty);
    });

    test('should filter by similarity threshold', () async {
      when(mockAiService.isModelLoaded).thenReturn(true);
      when(mockAiService.getEmbeddings(any))
          .thenAnswer((_) async => [0.1, 0.2, 0.3]);
      when(mockRepository.getAllChunks())
          .thenAnswer((_) async => testChunks);
      // Return low similarity
      when(mockVectorStore.cosineSimilarity(any, any)).thenReturn(0.3);

      final results = await documentService.retrieveRelevantContext('AI', limit: 5);

      // Should be empty because similarity < 0.65 threshold
      expect(results, isEmpty);
    });

    test('should throw AIServiceException when embedding generation fails', () async {
      when(mockAiService.isModelLoaded).thenReturn(true);
      when(mockAiService.getEmbeddings(any))
          .thenThrow(Exception('Embedding failed'));

      expect(
        () => documentService.retrieveRelevantContext('test'),
        throwsA(isA<AIServiceException>()),
      );
    });

    test('should throw StorageException when repository fails', () async {
      when(mockAiService.isModelLoaded).thenReturn(true);
      when(mockAiService.getEmbeddings(any))
          .thenAnswer((_) async => [0.1, 0.2, 0.3]);
      when(mockRepository.getAllChunks())
          .thenThrow(Exception('Database error'));

      expect(
        () => documentService.retrieveRelevantContext('test'),
        throwsA(isA<StorageException>()),
      );
    });

    test('should respect limit parameter', () async {
      when(mockAiService.isModelLoaded).thenReturn(true);
      when(mockAiService.getEmbeddings(any))
          .thenAnswer((_) async => [0.1, 0.2, 0.3]);
      when(mockRepository.getAllChunks())
          .thenAnswer((_) async => testChunks);
      when(mockVectorStore.cosineSimilarity(any, any)).thenReturn(0.9);

      final results = await documentService.retrieveRelevantContext('AI', limit: 1);

      expect(results.length, lessThanOrEqualTo(1));
    });

    test('should return empty list when no chunks have embeddings', () async {
      when(mockAiService.isModelLoaded).thenReturn(true);
      when(mockAiService.getEmbeddings(any))
          .thenAnswer((_) async => [0.1, 0.2, 0.3]);
      when(mockRepository.getAllChunks()).thenAnswer((_) async => [
            DocumentChunk(
              id: '1',
              documentId: 'doc1',
              content: 'No embedding',
              chunkIndex: 0,
              embedding: null,
            ),
          ]);

      final results = await documentService.retrieveRelevantContext('test');

      expect(results, isEmpty);
    });
  });

  group('DocumentService - getAllDocuments', () {
    test('should return all documents', () async {
      final testDocs = [
        Document(
          id: '1',
          filename: 'test.pdf',
          path: '/path/test.pdf',
          uploadDate: DateTime.now(),
        ),
      ];

      when(mockRepository.getAllDocuments())
          .thenAnswer((_) async => testDocs);

      final results = await documentService.getAllDocuments();

      expect(results, testDocs);
      verify(mockRepository.getAllDocuments()).called(1);
    });

    test('should throw StorageException when fetch fails', () async {
      when(mockRepository.getAllDocuments())
          .thenThrow(Exception('Fetch failed'));

      expect(
        () => documentService.getAllDocuments(),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('DocumentService - deleteDocument', () {
    test('should delete document successfully', () async {
      when(mockRepository.deleteDocument(any))
          .thenAnswer((_) async => {});

      await documentService.deleteDocument('test-id');

      verify(mockRepository.deleteDocument('test-id')).called(1);
    });

    test('should throw StorageException when deletion fails', () async {
      when(mockRepository.deleteDocument(any))
          .thenThrow(Exception('Delete failed'));

      expect(
        () => documentService.deleteDocument('test-id'),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('DocumentService - clearAllDocuments', () {
    test('should clear all documents', () async {
      final testDocs = [
        Document(
          id: '1',
          filename: 'doc1.pdf',
          path: '/path/doc1.pdf',
          uploadDate: DateTime.now(),
        ),
        Document(
          id: '2',
          filename: 'doc2.pdf',
          path: '/path/doc2.pdf',
          uploadDate: DateTime.now(),
        ),
      ];

      when(mockRepository.getAllDocuments())
          .thenAnswer((_) async => testDocs);
      when(mockRepository.deleteDocument(any))
          .thenAnswer((_) async => {});

      await documentService.clearAllDocuments();

      verify(mockRepository.deleteDocument('1')).called(1);
      verify(mockRepository.deleteDocument('2')).called(1);
    });
  });
}
