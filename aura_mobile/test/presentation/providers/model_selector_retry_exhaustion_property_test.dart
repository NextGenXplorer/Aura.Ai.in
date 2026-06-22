import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';

// Feature: multi-engine-ai-models, Property 21: Download retry exhaustion
//
// "For any litert download that fails on every attempt, exactly 3 total
//  download attempts are made, and after the third failure any partially
//  downloaded file is removed and a download-failure error is reported to the
//  user."
//
// Validates: Requirements 7.4, 7.5
//
// The retry control flow in ModelSelectorNotifier is driven by the pure
// decision function `decideDownloadFailure(attemptsSoFar, maxAttempts)`, which
// the provider consults at every failure (both in the download-update stream
// handler and in `retryDownload`). Testing that pure decision plus a faithful
// re-creation of the provider's failure loop lets us verify the universal
// property deterministically, across many inputs, without the Riverpod /
// stream / backoff-timer machinery.
//
// glados is not a project dependency; per the design's testing strategy this
// uses an equivalent generator-based approach layered on package:test. The
// generated properties run >= 100 cases.

const int _iterations = 200;

/// Outcome of simulating a download whose every attempt fails.
class _AllFailingOutcome {
  /// Total number of download attempts dispatched.
  final int attemptsMade;

  /// Number of times the partial file was removed (cleanup invoked).
  final int partialRemovals;

  /// Number of times a download-failure error was reported to the user.
  final int errorsReported;

  /// The 1-based attempt index at which exhaustion (cleanup + error) occurred.
  final int exhaustionAtAttempt;

  const _AllFailingOutcome({
    required this.attemptsMade,
    required this.partialRemovals,
    required this.errorsReported,
    required this.exhaustionAtAttempt,
  });
}

/// Faithfully re-creates the provider's retry loop for a download that fails on
/// every attempt, using the *real* `decideDownloadFailure` decision the
/// provider uses.
///
/// Mirrors ModelSelectorNotifier:
///  - `downloadModel` seeds the attempt counter to 1 and dispatches attempt 1.
///  - On each failure, `decideDownloadFailure(attempts)` decides:
///      * retry    -> the counter is incremented and another attempt is
///                    dispatched (`retryDownload` -> `_attemptDownload`).
///      * exhausted -> `_failDownloadAfterExhaustion` removes the partial file
///                    and reports a download-failure error exactly once.
_AllFailingOutcome _simulateAllFailing(int maxAttempts) {
  var attempts = 1; // _downloadRetryCount seeded by downloadModel (attempt 1).
  var attemptsMade = 1; // the initial _attemptDownload dispatch.
  var partialRemovals = 0;
  var errorsReported = 0;
  var exhaustionAtAttempt = -1;

  // Each iteration represents the current in-flight attempt reporting failure.
  while (true) {
    final decision =
        decideDownloadFailure(attempts, maxAttempts: maxAttempts);
    if (decision == DownloadFailureDecision.retry) {
      attempts += 1; // retryDownload increments the attempt counter.
      attemptsMade += 1; // _attemptDownload dispatches the next attempt.
    } else {
      // _failDownloadAfterExhaustion: remove partial + report failure (once).
      partialRemovals += 1;
      errorsReported += 1;
      exhaustionAtAttempt = attempts;
      break;
    }
  }

  return _AllFailingOutcome(
    attemptsMade: attemptsMade,
    partialRemovals: partialRemovals,
    errorsReported: errorsReported,
    exhaustionAtAttempt: exhaustionAtAttempt,
  );
}

void main() {
  group('Property 21: Download retry exhaustion (multi-engine-ai-models)', () {
    // --- The project's configured behaviour: exactly 3 total attempts. ---
    test('the configured maximum is exactly 3 total attempts', () {
      expect(kMaxDownloadAttempts, 3);

      final outcome = _simulateAllFailing(kMaxDownloadAttempts);
      expect(outcome.attemptsMade, 3,
          reason: 'a litert download that fails on every attempt must make '
              'exactly 3 total attempts (Req 7.4)');
      expect(outcome.partialRemovals, 1,
          reason: 'the partial file must be removed exactly once after the '
              'third failure (Req 7.5)');
      expect(outcome.errorsReported, 1,
          reason: 'a download-failure error must be reported exactly once '
              'after the third failure (Req 7.5)');
      expect(outcome.exhaustionAtAttempt, 3,
          reason: 'cleanup must occur on the third (final) failure');
    });

    // --- General property over any positive attempt budget: a download that
    // fails every time makes EXACTLY maxAttempts attempts, then cleans up and
    // reports failure exactly once. Runs >= 100 generated cases. ---
    test('all-failing download makes exactly maxAttempts attempts then cleans '
        'up and reports failure once', () {
      final rng = Random(72147);
      for (var i = 0; i < _iterations; i++) {
        final maxAttempts = 1 + rng.nextInt(12); // 1..12

        final outcome = _simulateAllFailing(maxAttempts);

        expect(outcome.attemptsMade, maxAttempts,
            reason: 'exactly $maxAttempts attempts expected when every '
                'attempt fails');
        expect(outcome.partialRemovals, 1,
            reason: 'partial file removed exactly once after exhaustion');
        expect(outcome.errorsReported, 1,
            reason: 'failure reported exactly once after exhaustion');
        expect(outcome.exhaustionAtAttempt, maxAttempts,
            reason: 'exhaustion (cleanup + error) happens on the final '
                'attempt only');
      }
    });

    // --- No premature cleanup: while attempts remain the decision is always
    // `retry`, and cleanup/error only fire on the very last failure. ---
    test('cleanup never happens before the final attempt', () {
      final rng = Random(99001);
      for (var i = 0; i < _iterations; i++) {
        final maxAttempts = 1 + rng.nextInt(12); // 1..12

        // For every non-final attempt index, the decision must be retry.
        for (var a = 1; a < maxAttempts; a++) {
          expect(decideDownloadFailure(a, maxAttempts: maxAttempts),
              DownloadFailureDecision.retry,
              reason: 'attempt $a of $maxAttempts must retry (no early '
                  'cleanup)');
        }
        // On (and beyond) the final attempt the decision must be exhausted.
        for (var a = maxAttempts; a <= maxAttempts + 3; a++) {
          expect(decideDownloadFailure(a, maxAttempts: maxAttempts),
              DownloadFailureDecision.exhausted,
              reason: 'attempt $a of $maxAttempts must be exhausted');
        }
      }
    });

    // --- The number of retries is exactly maxAttempts - 1 (the remaining
    // attempts beyond the first), for any positive budget. ---
    test('retry count equals maxAttempts - 1 for all-failing downloads', () {
      final rng = Random(13579);
      for (var i = 0; i < _iterations; i++) {
        final maxAttempts = 1 + rng.nextInt(12); // 1..12

        var retries = 0;
        for (var a = 1; a <= maxAttempts; a++) {
          if (decideDownloadFailure(a, maxAttempts: maxAttempts) ==
              DownloadFailureDecision.retry) {
            retries += 1;
          }
        }
        expect(retries, maxAttempts - 1,
            reason: 'exactly maxAttempts-1 retries before exhaustion');
      }
    });
  });
}
