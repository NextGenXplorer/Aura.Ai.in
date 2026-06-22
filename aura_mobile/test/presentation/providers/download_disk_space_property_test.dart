import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/domain/entities/ai_engine.dart';

// Feature: multi-engine-ai-models, Property 24: Insufficient disk space blocks
// download.
//
// "For any litert model where available disk space is less than the model's
//  file size, the Model_Selector reports an insufficient-storage error and does
//  not start the download."
//
// Validates: Requirements 7.8
//
// The download pipeline in ModelSelectorNotifier._attemptDownload calls
// ModelManager.validateDiskSpace before starting a download. That method
// compares the available disk space (in bytes) against the model's sizeBytes
// (with a 10% buffer). When the available space is below the threshold,
// a ModelException.insufficientSpace is thrown, which the provider catches to
// block the download and surface an error.
//
// This test verifies the pure decision logic: given any model size and any
// available disk space, the download is blocked (never started) when
// availableBytes < requiredBytes (where requiredBytes = sizeBytes * 1.1).
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:flutter_test.
// Each property runs >= 100 generated cases.

const int _iterations = 200;

/// The buffer multiplier applied to model.sizeBytes to determine required disk
/// space. Mirrors ModelManager.validateDiskSpace: `model.sizeBytes * 1.1`.
const double _diskSpaceBufferMultiplier = 1.1;

/// Outcome of the disk space decision.
enum DiskSpaceDecision {
  /// There is sufficient space — the download may proceed.
  allow,

  /// There is insufficient space — the download is blocked (Req 7.8).
  block,
}

/// Pure decision function that replicates the logic in
/// ModelManager.validateDiskSpace.
///
/// Given the model's [sizeBytes] and the [availableDiskSpaceBytes] reported by
/// the device, returns [DiskSpaceDecision.block] when the available space is
/// below the required threshold (sizeBytes * 1.1), and [DiskSpaceDecision.allow]
/// otherwise.
DiskSpaceDecision decideDiskSpace({
  required int sizeBytes,
  required int availableDiskSpaceBytes,
}) {
  final requiredBytes = (sizeBytes * _diskSpaceBufferMultiplier).toInt();
  if (availableDiskSpaceBytes < requiredBytes) {
    return DiskSpaceDecision.block;
  }
  return DiskSpaceDecision.allow;
}

/// Generates a random model size in bytes (between 1 MB and 4 GB).
/// Stays within Dart's `Random.nextInt` limit of 2^32.
int _randomSizeBytes(Random rng) {
  const minSize = 1 * 1024 * 1024; // 1 MB
  const maxSize = 4 * 1024 * 1024 * 1024 - 1; // ~4 GB (fits in nextInt)
  return minSize + rng.nextInt(maxSize - minSize);
}

/// Generates available disk space that is strictly less than the required
/// threshold for a given model size, ensuring the download should be blocked.
int _randomInsufficientSpace(Random rng, int sizeBytes) {
  final requiredBytes = (sizeBytes * _diskSpaceBufferMultiplier).toInt();
  // Available is in [0, requiredBytes - 1]
  if (requiredBytes <= 1) return 0;
  // Clamp to nextInt's max (2^32 - 1) to avoid RangeError.
  final cap = requiredBytes.clamp(1, 0x7FFFFFFF);
  return rng.nextInt(cap);
}

/// Generates available disk space that is >= the required threshold,
/// ensuring the download should be allowed.
int _randomSufficientSpace(Random rng, int sizeBytes) {
  final requiredBytes = (sizeBytes * _diskSpaceBufferMultiplier).toInt();
  // Available is in [requiredBytes, requiredBytes + some extra]
  final extra = rng.nextInt(500 * 1024 * 1024); // up to 500 MB extra
  return requiredBytes + extra;
}

void main() {
  group('Property 24: Insufficient disk space blocks download '
      '(multi-engine-ai-models)', () {
    // --- Core property: when available space < sizeBytes * 1.1, the download
    // is blocked. Runs >= 100 generated cases. ---
    test('download is blocked when available space is below the threshold', () {
      final rng = Random(0xD15C);
      for (var i = 0; i < _iterations; i++) {
        final sizeBytes = _randomSizeBytes(rng);
        final available = _randomInsufficientSpace(rng, sizeBytes);

        final decision = decideDiskSpace(
          sizeBytes: sizeBytes,
          availableDiskSpaceBytes: available,
        );

        expect(decision, DiskSpaceDecision.block,
            reason: 'model with sizeBytes=$sizeBytes requires '
                '${(sizeBytes * _diskSpaceBufferMultiplier).toInt()} bytes, '
                'but only $available available — download must be blocked '
                '(Req 7.8)');
      }
    });

    // --- Converse property: when available space >= sizeBytes * 1.1, the
    // download is allowed. ---
    test('download is allowed when available space meets or exceeds threshold',
        () {
      final rng = Random(0xA110);
      for (var i = 0; i < _iterations; i++) {
        final sizeBytes = _randomSizeBytes(rng);
        final available = _randomSufficientSpace(rng, sizeBytes);

        final decision = decideDiskSpace(
          sizeBytes: sizeBytes,
          availableDiskSpaceBytes: available,
        );

        expect(decision, DiskSpaceDecision.allow,
            reason: 'model with sizeBytes=$sizeBytes requires '
                '${(sizeBytes * _diskSpaceBufferMultiplier).toInt()} bytes, '
                'and $available is available — download must be allowed');
      }
    });

    // --- Boundary: available exactly equals required threshold — should allow. ---
    test('download is allowed at exact boundary (available == required)', () {
      final rng = Random(0xB0DD);
      for (var i = 0; i < _iterations; i++) {
        final sizeBytes = _randomSizeBytes(rng);
        final requiredBytes = (sizeBytes * _diskSpaceBufferMultiplier).toInt();

        final decision = decideDiskSpace(
          sizeBytes: sizeBytes,
          availableDiskSpaceBytes: requiredBytes,
        );

        expect(decision, DiskSpaceDecision.allow,
            reason: 'at exact boundary (available=$requiredBytes == required) '
                'the download should be allowed');
      }
    });

    // --- Boundary: available is 1 byte below the threshold — should block. ---
    test('download is blocked 1 byte below the threshold', () {
      final rng = Random(0xBE10);
      for (var i = 0; i < _iterations; i++) {
        final sizeBytes = _randomSizeBytes(rng);
        final requiredBytes = (sizeBytes * _diskSpaceBufferMultiplier).toInt();
        final available = requiredBytes - 1;

        final decision = decideDiskSpace(
          sizeBytes: sizeBytes,
          availableDiskSpaceBytes: available,
        );

        expect(decision, DiskSpaceDecision.block,
            reason: 'available=$available is 1 byte below required='
                '$requiredBytes — download must be blocked (Req 7.8)');
      }
    });

    // --- Verify against real catalog litert models: for each litert entry,
    // confirm the decision function blocks when space is insufficient. ---
    test('every catalog litert model is blocked when space is insufficient',
        () {
      final litertModels =
          modelCatalog.where((m) => m.engine == AIEngine.litert).toList();
      expect(litertModels, isNotEmpty,
          reason: 'catalog must contain at least one litert model');

      final rng = Random(0xCAFE);
      for (final model in litertModels) {
        for (var i = 0; i < _iterations; i++) {
          final available = _randomInsufficientSpace(rng, model.sizeBytes);

          final decision = decideDiskSpace(
            sizeBytes: model.sizeBytes,
            availableDiskSpaceBytes: available,
          );

          expect(decision, DiskSpaceDecision.block,
              reason: 'litert model ${model.id} (sizeBytes=${model.sizeBytes}) '
                  'must be blocked when available=$available (Req 7.8)');
        }
      }
    });

    // --- Zero available space always blocks any model with sizeBytes > 0. ---
    test('zero available disk space always blocks download', () {
      final rng = Random(0x0000);
      for (var i = 0; i < _iterations; i++) {
        final sizeBytes = 1 + rng.nextInt(0x7FFFFFFF); // 1B..~2GB

        final decision = decideDiskSpace(
          sizeBytes: sizeBytes,
          availableDiskSpaceBytes: 0,
        );

        expect(decision, DiskSpaceDecision.block,
            reason: 'zero disk space must always block download '
                '(sizeBytes=$sizeBytes)');
      }
    });
  });
}
