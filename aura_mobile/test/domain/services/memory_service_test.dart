import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:aura_mobile/domain/services/memory_service.dart';
import 'package:aura_mobile/domain/repositories/memory_repository.dart';
import 'package:aura_mobile/domain/entities/memory.dart';
import 'package:aura_mobile/domain/services/vector_store_service.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';

import 'memory_service_test.mocks.dart';

@GenerateMocks([RunAnywhere, MemoryRepository, VectorStoreService])
void main() {
  late MemoryService memoryService;
  late MockRunAnywhere mockAiService;
  late MockMemoryRepository mockRepository;
  late MockVectorStoreService mockVectorStore;

  setUp(() {
    mockAiService = MockRunAnywhere();
    mockRepository = MockMemoryRepository();
    mockVectorStore = MockVectorStoreService();
    memoryService = MemoryService(mockAiService, mockRepository, mockVectorStore);
  });

  group('MemoryService - saveMemory', () {
    test('should throw ValidationException for empty content', () async {
      expect(
        () => memoryService.saveMemory(''),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should throw ValidationException for content too long', () async {
      final longContent = 'a' * 5001;

      expect(
        () => memoryService.saveMemory(longContent),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should save memory with embeddings when model is loaded', () async {
      when(mockAiService.isModelLoaded).thenReturn(true);
      when(mockAiService.getEmbeddings(any))
          .thenAnswer((_) async => [0.1, 0.2, 0.3]);
      when(mockRepository.saveMemory(any)).thenAnswer((_) async => {});

      await memoryService.saveMemory('Test memory content');

      verify(mockAiService.getEmbeddings('Test memory content')).called(1);
      verify(mockRepository.saveMemory(argThat(
        predicate<Memory>((m) =>
            m.content == 'Test memory content' && m.embedding != null && m.embedding!.isNotEmpty),
      ))).called(1);
    });

    test('should save memory without embeddings when model not loaded', () async {
      when(mockAiService.isModelLoaded).thenReturn(false);
      when(mockRepository.saveMemory(any)).thenAnswer((_) async => {});

      await memoryService.saveMemory('Test memory content');

      verifyNever(mockAiService.getEmbeddings(any));
      verify(mockRepository.saveMemory(argThat(
        predicate<Memory>((m) =>
            m.content == 'Test memory content' && m.embedding == null),
      ))).called(1);
    });

    test('should save memory without embeddings when embedding generation fails', () async {
      when(mockAiService.isModelLoaded).thenReturn(true);
      when(mockAiService.getEmbeddings(any))
          .thenThrow(Exception('Embedding failed'));
      when(mockRepository.saveMemory(any)).thenAnswer((_) async => {});

      await memoryService.saveMemory('Test memory content');

      verify(mockRepository.saveMemory(argThat(
        predicate<Memory>((m) =>
            m.content == 'Test memory content' && m.embedding == null),
      ))).called(1);
    });

    test('should throw StorageException when repository fails', () async {
      when(mockAiService.isModelLoaded).thenReturn(false);
      when(mockRepository.saveMemory(any))
          .thenThrow(Exception('Database error'));

      expect(
        () => memoryService.saveMemory('Test memory'),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('MemoryService - retrieveRelevantMemories', () {
    final testMemories = [
      Memory(
        id: '1',
        content: 'I like pizza',
        category: 'general',
        timestamp: DateTime.now(),
        embedding: [0.1, 0.2, 0.3],
      ),
      Memory(
        id: '2',
        content: 'I like pasta',
        category: 'general',
        timestamp: DateTime.now(),
        embedding: [0.9, 0.8, 0.7],
      ),
      Memory(
        id: '3',
        content: 'No embedding',
        category: 'general',
        timestamp: DateTime.now(),
        embedding: null,
      ),
    ];

    test('should return empty list for empty query', () async {
      final results = await memoryService.retrieveRelevantMemories('');

      expect(results, isEmpty);
    });

    test('should return empty list when no memories exist', () async {
      when(mockRepository.getMemories()).thenAnswer((_) async => []);

      final results = await memoryService.retrieveRelevantMemories('test query');

      expect(results, isEmpty);
    });

    test('should use vector search when model is loaded', () async {
      when(mockAiService.isModelLoaded).thenReturn(true);
      when(mockAiService.getEmbeddings(any))
          .thenAnswer((_) async => [0.1, 0.2, 0.3]);
      when(mockRepository.getMemories()).thenAnswer((_) async => testMemories);
      when(mockVectorStore.cosineSimilarity(any, any)).thenReturn(0.9);

      final results = await memoryService.retrieveRelevantMemories('pizza', limit: 3);

      verify(mockAiService.getEmbeddings('pizza')).called(1);
      verify(mockVectorStore.cosineSimilarity(any, any)).called(greaterThan(0));
      expect(results, isNotEmpty);
    });

    test('should fallback to keyword search when model not loaded', () async {
      when(mockAiService.isModelLoaded).thenReturn(false);
      when(mockRepository.getMemories()).thenAnswer((_) async => testMemories);
      when(mockRepository.searchMemories(any))
          .thenAnswer((_) async => [testMemories[0]]);

      final results = await memoryService.retrieveRelevantMemories('pizza');

      verifyNever(mockAiService.getEmbeddings(any));
      verify(mockRepository.searchMemories('pizza')).called(1);
      expect(results, contains('I like pizza'));
    });

    test('should fallback to keyword search when vector search fails', () async {
      when(mockAiService.isModelLoaded).thenReturn(true);
      when(mockAiService.getEmbeddings(any))
          .thenThrow(Exception('Embedding failed'));
      when(mockRepository.getMemories()).thenAnswer((_) async => testMemories);
      when(mockRepository.searchMemories(any))
          .thenAnswer((_) async => [testMemories[0]]);

      final results = await memoryService.retrieveRelevantMemories('pizza');

      verify(mockRepository.searchMemories('pizza')).called(1);
      expect(results, isNotEmpty);
    });

    test('should return empty list when both searches fail', () async {
      when(mockAiService.isModelLoaded).thenReturn(true);
      when(mockAiService.getEmbeddings(any))
          .thenThrow(Exception('Embedding failed'));
      when(mockRepository.getMemories()).thenAnswer((_) async => testMemories);
      when(mockRepository.searchMemories(any)).thenThrow(Exception('Search failed'));

      final results = await memoryService.retrieveRelevantMemories('pizza');

      expect(results, isEmpty);
    });

    test('should respect limit parameter', () async {
      when(mockAiService.isModelLoaded).thenReturn(false);
      when(mockRepository.getMemories()).thenAnswer((_) async => testMemories);
      when(mockRepository.searchMemories(any))
          .thenAnswer((_) async => testMemories.take(3).toList());

      final results = await memoryService.retrieveRelevantMemories('test', limit: 2);

      expect(results.length, lessThanOrEqualTo(2));
    });
  });

  group('MemoryService - deleteMemory', () {
    test('should delete memory successfully', () async {
      when(mockRepository.deleteMemory(any)).thenAnswer((_) async => {});

      await memoryService.deleteMemory('test-id');

      verify(mockRepository.deleteMemory('test-id')).called(1);
    });

    test('should throw StorageException when deletion fails', () async {
      when(mockRepository.deleteMemory(any))
          .thenThrow(Exception('Delete failed'));

      expect(
        () => memoryService.deleteMemory('test-id'),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('MemoryService - getAllMemories', () {
    test('should return all memories', () async {
      final testMemories = [
        Memory(
          id: '1',
          content: 'Memory 1',
          category: 'general',
          timestamp: DateTime.now(),
        ),
      ];

      when(mockRepository.getMemories()).thenAnswer((_) async => testMemories);

      final results = await memoryService.getAllMemories();

      expect(results, testMemories);
      verify(mockRepository.getMemories()).called(1);
    });

    test('should throw StorageException when fetch fails', () async {
      when(mockRepository.getMemories()).thenThrow(Exception('Fetch failed'));

      expect(
        () => memoryService.getAllMemories(),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('MemoryService - clearAllMemories', () {
    test('should clear all memories', () async {
      final testMemories = [
        Memory(id: '1', content: 'M1', category: 'general', timestamp: DateTime.now()),
        Memory(id: '2', content: 'M2', category: 'general', timestamp: DateTime.now()),
      ];

      when(mockRepository.getMemories()).thenAnswer((_) async => testMemories);
      when(mockRepository.deleteMemory(any)).thenAnswer((_) async => {});

      await memoryService.clearAllMemories();

      verify(mockRepository.deleteMemory('1')).called(1);
      verify(mockRepository.deleteMemory('2')).called(1);
    });
  });
}
