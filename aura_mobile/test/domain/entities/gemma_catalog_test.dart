import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';

/// Unit tests for the required Gemma LiteRT catalog entries.
///
/// Validates: Requirements 4.4, 4.5, 4.6, 4.7
void main() {
  ModelInfo entryFor(String id) =>
      modelCatalog.firstWhere((m) => m.id == id);

  bool hasEntry(String id) => modelCatalog.any((m) => m.id == id);

  group('Required Gemma catalog entries', () {
    test('Gemma 3 1B exists as a litert model without tool calling (Req 4.4)',
        () {
      expect(hasEntry('gemma3-1b'), isTrue,
          reason: 'gemma3-1b entry must be present in the catalog');
      final model = entryFor('gemma3-1b');
      expect(model.engine, AIEngine.litert);
      expect(model.supportsToolCalling, isFalse);
    });

    test('Gemma 3n E2B exists as a litert model without tool calling (Req 4.5)',
        () {
      expect(hasEntry('gemma3n-e2b'), isTrue,
          reason: 'gemma3n-e2b entry must be present in the catalog');
      final model = entryFor('gemma3n-e2b');
      expect(model.engine, AIEngine.litert);
      expect(model.supportsToolCalling, isFalse);
    });

    test('Gemma 4 E2B exists as a litert model with tool calling (Req 4.6)',
        () {
      expect(hasEntry('gemma4-e2b'), isTrue,
          reason: 'gemma4-e2b entry must be present in the catalog');
      final model = entryFor('gemma4-e2b');
      expect(model.engine, AIEngine.litert);
      expect(model.supportsToolCalling, isTrue);
    });

    test('Gemma 4 E4B exists as a litert model with tool calling (Req 4.7)',
        () {
      expect(hasEntry('gemma4-e4b'), isTrue,
          reason: 'gemma4-e4b entry must be present in the catalog');
      final model = entryFor('gemma4-e4b');
      expect(model.engine, AIEngine.litert);
      expect(model.supportsToolCalling, isTrue);
    });

    test('all four required Gemma entries are present', () {
      const requiredIds = [
        'gemma3-1b',
        'gemma3n-e2b',
        'gemma4-e2b',
        'gemma4-e4b',
      ];
      for (final id in requiredIds) {
        expect(hasEntry(id), isTrue, reason: 'missing required entry: $id');
      }
    });
  });
}
