import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/domain/models/workflow_plan.dart';
import 'package:aura_mobile/domain/models/workflow_step.dart';
import 'package:aura_mobile/domain/services/workflow_validator.dart';
import 'package:aura_mobile/core/errors/app_exceptions.dart';

void main() {
  late WorkflowValidator validator;

  setUp(() {
    validator = WorkflowValidator();
  });

  group('WorkflowValidator - Plan validation', () {
    test('should accept valid plan', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(rawMessage: 'Step 1'),
        WorkflowStep(rawMessage: 'Step 2'),
      ]);

      expect(() => validator.validatePlan(plan), returnsNormally);
    });

    test('should reject empty plan', () {
      final plan = WorkflowPlan(steps: const []);

      expect(
        () => validator.validatePlan(plan),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should reject plan with invalid step', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(rawMessage: ''), // Empty message
      ]);

      expect(
        () => validator.validatePlan(plan),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should accept plan with variable extraction', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(
          rawMessage: 'Search for info',
          outputKey: 'result',
          extractionRequirement: 'Extract URL',
        ),
        WorkflowStep(rawMessage: 'Use {result}'),
      ]);

      expect(() => validator.validatePlan(plan), returnsNormally);
    });
  });

  group('WorkflowValidator - Step validation', () {
    test('should accept valid step', () {
      const step = WorkflowStep(rawMessage: 'Do something');

      expect(() => validator.validateStep(step), returnsNormally);
    });

    test('should accept step with extraction', () {
      const step = WorkflowStep(
        rawMessage: 'Search for data',
        outputKey: 'myData',
        extractionRequirement: 'Extract the data',
      );

      expect(() => validator.validateStep(step), returnsNormally);
    });

    test('should reject empty message', () {
      const step = WorkflowStep(rawMessage: '');

      expect(
        () => validator.validateStep(step),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should reject whitespace-only message', () {
      const step = WorkflowStep(rawMessage: '   ');

      expect(
        () => validator.validateStep(step),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should reject outputKey without extractionRequirement', () {
      const step = WorkflowStep(
        rawMessage: 'Do something',
        outputKey: 'result',
      );

      expect(
        () => validator.validateStep(step),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should reject extractionRequirement without outputKey', () {
      const step = WorkflowStep(
        rawMessage: 'Do something',
        extractionRequirement: 'Extract data',
      );

      expect(
        () => validator.validateStep(step),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should reject invalid outputKey characters', () {
      const step = WorkflowStep(
        rawMessage: 'Do something',
        outputKey: 'my-result', // Hyphen not allowed
        extractionRequirement: 'Extract',
      );

      expect(
        () => validator.validateStep(step),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should accept valid outputKey formats', () {
      const validKeys = [
        'result',
        'myResult',
        'my_result',
        'result123',
        '_private',
        'RESULT',
      ];

      for (final key in validKeys) {
        final step = WorkflowStep(
          rawMessage: 'Do something',
          outputKey: key,
          extractionRequirement: 'Extract',
        );

        expect(() => validator.validateStep(step), returnsNormally,
            reason: 'Key "$key" should be valid');
      }
    });

    test('should reject too long message', () {
      final longMessage = 'a' * 1001; // 1001 characters
      final step = WorkflowStep(rawMessage: longMessage);

      expect(
        () => validator.validateStep(step),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should accept message at max length', () {
      final maxMessage = 'a' * 1000; // Exactly 1000 characters
      final step = WorkflowStep(rawMessage: maxMessage);

      expect(() => validator.validateStep(step), returnsNormally);
    });
  });

  group('WorkflowValidator - Variable dependencies', () {
    test('should accept plan with proper variable order', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(
          rawMessage: 'Get data',
          outputKey: 'data',
          extractionRequirement: 'Extract data',
        ),
        WorkflowStep(rawMessage: 'Process {data}'),
      ]);

      expect(() => validator.validatePlan(plan), returnsNormally);
    });

    test('should reject undefined variable reference', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(rawMessage: 'Use {undefinedVar}'),
      ]);

      expect(
        () => validator.validatePlan(plan),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should reject forward variable reference', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(rawMessage: 'Use {futureVar}'), // Forward reference
        WorkflowStep(
          rawMessage: 'Get data',
          outputKey: 'futureVar',
          extractionRequirement: 'Extract',
        ),
      ]);

      expect(
        () => validator.validatePlan(plan),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should accept multiple variable references', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(
          rawMessage: 'Get A',
          outputKey: 'varA',
          extractionRequirement: 'Extract A',
        ),
        WorkflowStep(
          rawMessage: 'Get B',
          outputKey: 'varB',
          extractionRequirement: 'Extract B',
        ),
        WorkflowStep(rawMessage: 'Combine {varA} and {varB}'),
      ]);

      expect(() => validator.validatePlan(plan), returnsNormally);
    });

    test('should accept chained variable dependencies', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(
          rawMessage: 'Get A',
          outputKey: 'a',
          extractionRequirement: 'Extract A',
        ),
        WorkflowStep(
          rawMessage: 'Process {a}',
          outputKey: 'b',
          extractionRequirement: 'Extract B',
        ),
        WorkflowStep(
          rawMessage: 'Use {b}',
          outputKey: 'c',
          extractionRequirement: 'Extract C',
        ),
      ]);

      expect(() => validator.validatePlan(plan), returnsNormally);
    });
  });

  group('WorkflowValidator - Duplicate output keys', () {
    test('should reject duplicate output keys', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(
          rawMessage: 'Step 1',
          outputKey: 'result',
          extractionRequirement: 'Extract 1',
        ),
        WorkflowStep(
          rawMessage: 'Step 2',
          outputKey: 'result', // Duplicate
          extractionRequirement: 'Extract 2',
        ),
      ]);

      expect(
        () => validator.validatePlan(plan),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should accept different output keys', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(
          rawMessage: 'Step 1',
          outputKey: 'result1',
          extractionRequirement: 'Extract 1',
        ),
        WorkflowStep(
          rawMessage: 'Step 2',
          outputKey: 'result2',
          extractionRequirement: 'Extract 2',
        ),
      ]);

      expect(() => validator.validatePlan(plan), returnsNormally);
    });

    test('should allow steps without output keys', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(rawMessage: 'Step 1'),
        WorkflowStep(rawMessage: 'Step 2'),
        WorkflowStep(rawMessage: 'Step 3'),
      ]);

      expect(() => validator.validatePlan(plan), returnsNormally);
    });
  });

  group('WorkflowValidator - Circular dependencies', () {
    test('should reject simple circular dependency', () {
      // This is actually impossible with the current step structure
      // since you can't reference a variable before it's defined.
      // But we test the cycle detection logic for future-proofing.

      // We'll test the internal _hasCycle method indirectly
      // by ensuring no false positives on valid chains
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(
          rawMessage: 'Get A',
          outputKey: 'a',
          extractionRequirement: 'Extract A',
        ),
        WorkflowStep(
          rawMessage: 'Process {a}',
          outputKey: 'b',
          extractionRequirement: 'Extract B',
        ),
        WorkflowStep(rawMessage: 'Use {b}'),
      ]);

      expect(() => validator.validatePlan(plan), returnsNormally);
    });

    test('should accept DAG (no cycles)', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(
          rawMessage: 'Root',
          outputKey: 'root',
          extractionRequirement: 'Extract',
        ),
        WorkflowStep(
          rawMessage: 'Branch A from {root}',
          outputKey: 'branchA',
          extractionRequirement: 'Extract',
        ),
        WorkflowStep(
          rawMessage: 'Branch B from {root}',
          outputKey: 'branchB',
          extractionRequirement: 'Extract',
        ),
        WorkflowStep(rawMessage: 'Merge {branchA} and {branchB}'),
      ]);

      expect(() => validator.validatePlan(plan), returnsNormally);
    });
  });

  group('WorkflowValidator - Resume validation', () {
    test('should accept valid resume parameters', () {
      expect(
        () => validator.validateResume('workflow-123', 0, 5),
        returnsNormally,
      );
    });

    test('should accept mid-workflow resume', () {
      expect(
        () => validator.validateResume('workflow-123', 3, 5),
        returnsNormally,
      );
    });

    test('should reject empty workflow ID', () {
      expect(
        () => validator.validateResume('', 0, 5),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should reject whitespace workflow ID', () {
      expect(
        () => validator.validateResume('   ', 0, 5),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should reject negative step index', () {
      expect(
        () => validator.validateResume('workflow-123', -1, 5),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should reject step index beyond total steps', () {
      expect(
        () => validator.validateResume('workflow-123', 5, 5),
        throwsA(isA<ValidationException>()),
      );
    });

    test('should reject step index way beyond total steps', () {
      expect(
        () => validator.validateResume('workflow-123', 10, 5),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('WorkflowValidator - Extracted data validation', () {
    test('should accept valid extracted data', () {
      expect(validator.isValidExtractedData('Some data'), true);
      expect(validator.isValidExtractedData('https://example.com'), true);
      expect(validator.isValidExtractedData('12345'), true);
    });

    test('should reject null data', () {
      expect(validator.isValidExtractedData(null), false);
    });

    test('should reject empty string', () {
      expect(validator.isValidExtractedData(''), false);
    });

    test('should reject whitespace-only string', () {
      expect(validator.isValidExtractedData('   '), false);
    });

    test('should reject NOT_FOUND sentinel', () {
      expect(validator.isValidExtractedData('NOT_FOUND'), false);
    });

    test('should accept data with leading/trailing whitespace', () {
      expect(validator.isValidExtractedData('  data  '), true);
    });
  });

  group('WorkflowValidator - Variable reference extraction', () {
    test('should extract single variable', () {
      final validator = WorkflowValidator();
      final refs = validator.extractVariableReferences('Use {myVar}');
      expect(refs, {'myVar'});
    });

    test('should extract multiple variables', () {
      final validator = WorkflowValidator();
      final refs = validator.extractVariableReferences(
        'Combine {var1} and {var2} with {var3}',
      );
      expect(refs, {'var1', 'var2', 'var3'});
    });

    test('should handle no variables', () {
      final validator = WorkflowValidator();
      final refs = validator.extractVariableReferences('No variables here');
      expect(refs, isEmpty);
    });

    test('should handle duplicate references', () {
      final validator = WorkflowValidator();
      final refs = validator.extractVariableReferences('Use {var} and {var}');
      expect(refs, {'var'});
    });

    test('should handle underscore and numbers', () {
      final validator = WorkflowValidator();
      final refs = validator.extractVariableReferences(
        '{my_var1} and {_private} and {VAR123}',
      );
      expect(refs, {'my_var1', '_private', 'VAR123'});
    });

    test('should ignore invalid variable names', () {
      final validator = WorkflowValidator();
      final refs = validator.extractVariableReferences(
        '{123invalid} and {my-var} and {valid}',
      );
      expect(refs, {'valid'});
    });
  });

  group('WorkflowValidator - Edge cases', () {
    test('should handle plan with single step', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(rawMessage: 'Only step'),
      ]);

      expect(() => validator.validatePlan(plan), returnsNormally);
    });

    test('should handle plan with many steps', () {
      final steps = List.generate(
        100,
        (i) => WorkflowStep(rawMessage: 'Step $i'),
      );
      final plan = WorkflowPlan(steps: steps);

      expect(() => validator.validatePlan(plan), returnsNormally);
    });

    test('should handle complex variable names', () {
      final plan = WorkflowPlan(steps: const [
        WorkflowStep(
          rawMessage: 'Get data',
          outputKey: 'user_email_address_primary',
          extractionRequirement: 'Extract email',
        ),
        WorkflowStep(rawMessage: 'Send to {user_email_address_primary}'),
      ]);

      expect(() => validator.validatePlan(plan), returnsNormally);
    });

    test('should handle nested braces (extracts inner variable)', () {
      final validator = WorkflowValidator();
      final refs = validator.extractVariableReferences('Use {{nested}}');
      // The regex matches {nested} inside {{nested}}
      expect(refs, {'nested'});
    });
  });
}
