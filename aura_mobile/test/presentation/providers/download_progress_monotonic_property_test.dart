import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';

// Feature: multi-engine-ai-models, Property 20: Download progress is bounded
// and monotonic.
//
// "For any sequence of bytes-received readings during a download, the reported
//  progress is always a value in the closed interval [0, 1] and never decreases
//  as additional bytes are received."
//
// Validates: Requirements 7.2
//
// The download pipeline reports progress on a 0-100 percentage scale that can
// be noisy: it may exceed 100, dip backwards on a retry, or arrive out of
// order. `ModelSelectorNotifier.foldDownloadProgress` folds each raw reading
// into the reported value, clamping to [0, 1] and never decreasing. This test
// exercises that pure folding logic over generated reading sequences.
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:flutter_test.
// Each property runs >= 100 generated cases.

const int _iterations = 300;

/// Generates one raw progress reading on a 0-100 percentage scale, but
/// deliberately includes out-of-range and noisy values (negative readings,
/// readings above 100, jitter) so the clamping/monotonic logic is stressed.
double _randomReading(Random rng) {
  switch (rng.nextInt(6)) {
    case 0:
      return -rng.nextDouble() * 50; // negative (below 0)
    case 1:
      return 100 + rng.nextDouble() * 100; // above 100
    case 2:
      return 0;
    case 3:
      return 100;
    default:
      return rng.nextDouble() * 100; // typical in-range reading
  }
}

/// Builds a random sequence of raw readings of random length.
List<double> _randomSequence(Random rng) {
  final len = rng.nextInt(40); // 0..39 readings
  return List<double>.generate(len, (_) => _randomReading(rng));
}

void main() {
  group('Property 20: download progress is bounded and monotonic '
      '(multi-engine-ai-models)', () {
    test('each folded reading stays within the closed interval [0, 1]', () {
      final rng = Random(0x7202A);
      for (var i = 0; i < _iterations; i++) {
        final readings = _randomSequence(rng);
        var progress = 0.0; // downloads start at 0
        for (final raw in readings) {
          progress = ModelSelectorNotifier.foldDownloadProgress(progress, raw);
          expect(progress, greaterThanOrEqualTo(0.0),
              reason: 'progress $progress below 0 for reading $raw');
          expect(progress, lessThanOrEqualTo(1.0),
              reason: 'progress $progress above 1 for reading $raw');
        }
      }
    });

    test('reported progress never decreases as more readings arrive', () {
      final rng = Random(0x4D0);
      for (var i = 0; i < _iterations; i++) {
        final readings = _randomSequence(rng);
        var progress = 0.0;
        for (final raw in readings) {
          final next =
              ModelSelectorNotifier.foldDownloadProgress(progress, raw);
          expect(next, greaterThanOrEqualTo(progress),
              reason: 'progress decreased from $progress to $next '
                  'for reading $raw');
          progress = next;
        }
      }
    });

    test('monotonicity holds even when a reading drops backwards (retry)', () {
      final rng = Random(0xBADF00D);
      for (var i = 0; i < _iterations; i++) {
        // Climb to some progress, then feed a lower reading (simulating a
        // retry that restarts byte counting) and confirm it does not regress.
        final high = rng.nextDouble() * 100;
        final low = rng.nextDouble() * high; // strictly <= high
        final afterHigh =
            ModelSelectorNotifier.foldDownloadProgress(0.0, high);
        final afterLow =
            ModelSelectorNotifier.foldDownloadProgress(afterHigh, low);
        expect(afterLow, greaterThanOrEqualTo(afterHigh),
            reason: 'retry reading $low regressed progress from '
                '$afterHigh to $afterLow');
        expect(afterLow, lessThanOrEqualTo(1.0));
      }
    });

    test('a 100% reading maps to exactly 1.0 and stays there', () {
      final rng = Random(0xC0FFEE);
      for (var i = 0; i < _iterations; i++) {
        final complete =
            ModelSelectorNotifier.foldDownloadProgress(rng.nextDouble(), 100);
        expect(complete, 1.0);
        // Any subsequent reading keeps it at 1.0.
        final after =
            ModelSelectorNotifier.foldDownloadProgress(complete, _randomReading(rng));
        expect(after, 1.0);
      }
    });
  });
}
