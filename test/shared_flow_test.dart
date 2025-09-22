import 'dart:async';
import 'package:flow/flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SharedFlow', () {
    test('emit sends values to active collector (no replay)', () async {
      final sharedFlow = SharedFlow<int>(replay: 0);
      final collectedValues = <int>[];
      final completer = Completer<void>();

      sharedFlow.collect((value) {
        collectedValues.add(value);
        if (value == 2) {
          completer.complete();
        }
      });

      await Future.delayed(Duration.zero); // Allow collect to set up
      sharedFlow.emit(1);
      await Future.delayed(Duration.zero);
      sharedFlow.emit(2);

      await completer.future.timeout(const Duration(milliseconds: 100));
      expect(collectedValues, [1, 2]);
      sharedFlow.close();
    });

    test('new collector receives replayed values and subsequent emissions',
        () async {
      final sharedFlow = SharedFlow<int>(replay: 2);
      sharedFlow.emit(1); // Emitted before collection
      sharedFlow.emit(2); // Emitted before collection

      await Future.delayed(Duration.zero);

      final collectedValues = <int>[];
      final completer = Completer<void>();

      sharedFlow.collect((value) {
        collectedValues.add(value);
        if (value == 3 && collectedValues.length == 3) {
          // Expecting 1, 2, 3
          completer.complete();
        }
      });

      await Future.delayed(
          Duration.zero); // Allow replayed values to be processed
      sharedFlow.emit(3); // Emitted after collection starts

      await completer.future.timeout(const Duration(milliseconds: 100));
      expect(collectedValues, [1, 2, 3]);
      sharedFlow.close();
    });

    test('replay cache respects size limit', () async {
      final sharedFlow = SharedFlow<int>(replay: 2);
      sharedFlow.emit(1);
      sharedFlow.emit(2);
      sharedFlow.emit(3); // This should push 1 out of the replay cache

      await Future.delayed(Duration.zero);

      final collectedValues = <int>[];
      final completer = Completer<void>();

      sharedFlow.collect((value) {
        collectedValues.add(value);
        if (value == 4 && collectedValues.length == 3) {
          // Expecting 2, 3, 4
          completer.complete();
        }
      });
      await Future.delayed(Duration.zero);
      sharedFlow.emit(4);

      await completer.future.timeout(const Duration(milliseconds: 100));
      expect(collectedValues, [2, 3, 4]);
      sharedFlow.close();
    });

    test('multiple collectors receive replayed and new values', () async {
      final sharedFlow = SharedFlow<int>(replay: 1);
      sharedFlow.emit(10); // Will be replayed

      await Future.delayed(Duration.zero);

      final collected1 = <int>[];
      final completer1 = Completer<void>();
      sharedFlow.collect((value) {
        collected1.add(value);
        if (value == 20 && collected1.length == 2) completer1.complete();
      });

      await Future.delayed(const Duration(
          milliseconds: 10)); // Ensure first collector is processing

      final collected2 = <int>[];
      final completer2 = Completer<void>();
      sharedFlow.collect((value) {
        collected2.add(value);
        if (value == 20 && collected2.length == 2) completer2.complete();
      });

      await Future.delayed(Duration.zero);
      sharedFlow.emit(20); // New value

      await Future.wait([
        completer1.future.timeout(const Duration(milliseconds: 100)),
        completer2.future.timeout(const Duration(milliseconds: 100)),
      ]);

      expect(collected1, [10, 20]);
      expect(collected2, [10, 20]);
      sharedFlow.close();
    });

    test('replay = 0 means no values for late collectors before new emit',
        () async {
      final sharedFlow = SharedFlow<int>(replay: 0);
      sharedFlow.emit(1); // Emitted before collection, should not be replayed
      sharedFlow.emit(2); // Emitted before collection, should not be replayed

      await Future.delayed(Duration.zero);

      final collectedValues = <int>[];
      final completer = Completer<void>();

      sharedFlow.collect((value) {
        collectedValues.add(value);
        if (value == 3) {
          completer.complete();
        }
      });

      await Future.delayed(Duration.zero);
      sharedFlow.emit(3); // First value this collector should see

      await completer.future.timeout(const Duration(milliseconds: 100));
      expect(collectedValues, [3]);
      sharedFlow.close();
    });

    group('close()', () {
      test('prevents new value emissions via emit()', () async {
        final sharedFlow = SharedFlow<int>(replay: 1);
        final collectedValues = <int>[];
        final completer = Completer<void>();

        sharedFlow.collect((value) {
          collectedValues.add(value);
          if (value == 1) completer.complete();
        });

        await Future.delayed(Duration.zero);
        sharedFlow.emit(1);
        await completer.future.timeout(const Duration(milliseconds: 100));

        sharedFlow.close();
        await Future.delayed(Duration.zero);

        sharedFlow.emit(2); // Should not be collected
        await Future.delayed(Duration.zero);

        expect(collectedValues, [1]);
      });

      test(
          'new collect() on closed flow (with replay) gets existing replay items then completes',
          () async {
        final sharedFlow = SharedFlow<int>(replay: 2);
        sharedFlow.emit(100);
        sharedFlow.emit(200);

        await Future.delayed(Duration.zero);
        sharedFlow.close();
        await Future.delayed(Duration.zero);

        final collectedValues = <int>[];
        // collectSafely's onDone will be called. For collect(), it means future completes.
        await sharedFlow
            .timeout(const Duration(milliseconds: 50))
            .collect(collectedValues.add);

        expect(collectedValues, [100, 200]);
      });

      test('new collect() on closed flow (no replay) completes immediately',
          () async {
        final sharedFlow = SharedFlow<int>(replay: 0);
        sharedFlow.emit(100); // Not replayed

        await Future.delayed(Duration.zero);
        sharedFlow.close();
        await Future.delayed(Duration.zero);

        final collectedValues = <int>[];
        await sharedFlow
            .timeout(const Duration(milliseconds: 50))
            .collect(collectedValues.add);
        expect(collectedValues, isEmpty);
      });

      test(
          'collectSafely on closed flow (with replay) calls onDone after replay',
          () async {
        final sharedFlow = SharedFlow<int>(replay: 1);
        sharedFlow.emit(50);
        await Future.delayed(Duration.zero);

        sharedFlow.close();
        await Future.delayed(Duration.zero);

        bool onDoneCalled = false;
        final collectedValues = <int>[];
        final safeCollector = sharedFlow.collectSafely((value) {
          collectedValues.add(value);
        });
        safeCollector.done(() => onDoneCalled = true);

        await Future.delayed(const Duration(
            milliseconds: 50)); // Allow microtasks to run for onDone

        expect(collectedValues, [50]);
        expect(onDoneCalled, isTrue);
      });

      test('collectSafely on closed flow (no replay) calls onDone immediately',
          () async {
        final sharedFlow = SharedFlow<int>(replay: 0);

        sharedFlow.close();
        await Future.delayed(Duration.zero);

        bool onDoneCalled = false;
        final safeCollector = sharedFlow.collectSafely((value) {
          fail(
              "Collector should not be called on a closed flow with no replay");
        });
        safeCollector.done(() => onDoneCalled = true);

        await Future.delayed(const Duration(milliseconds: 50));

        expect(onDoneCalled, isTrue);
      });
    });

    test('collect() stops collection if lambda throws error', () async {
      final sharedFlow = SharedFlow<int>(replay: 1);
      sharedFlow.emit(0); // initial value in replay

      final collectedValues = <int>[];
      final error = Exception('Collector error in collect');
      bool errorCaughtByTest = false;

      FutureOr<void> collectionProcessFuture = sharedFlow.collect((value) {
        collectedValues.add(value);
        if (value == 1) {
          throw error;
        }
      });

      await Future.delayed(Duration.zero); // Allow initial replay
      sharedFlow.emit(1); // Triggers error

      try {
        await (collectionProcessFuture as Future<void>)
            .timeout(const Duration(milliseconds: 100));
        fail("sharedFlow.collect() should have completed with an error.");
      } catch (e) {
        if (e == error) {
          errorCaughtByTest = true;
        } else if (e is TimeoutException) {
          fail(
              "sharedFlow.collect() timed out, error not propagated correctly.");
        } else {
          rethrow; // Some other unexpected error
        }
      }

      expect(errorCaughtByTest, isTrue,
          reason: "The specific error was not caught by the test's try-catch.");
      expect(collectedValues, [0, 1],
          reason: "Collection should have values up to the error.");

      sharedFlow.emit(2); // Should not be collected by this errored collector
      await Future.delayed(Duration.zero);
      expect(collectedValues, [0, 1],
          reason: "Collection should stop after error.");
      sharedFlow.close();
    });

    test('collectSafely() reports error and closes the collector',
        () async {
      final sharedFlow = SharedFlow<int>(replay: 1);
      sharedFlow.emit(0); // initial value in replay

      final collectedValues = <int>[];
      final customError = Exception("Collector error in collectSafely");
      Object? reportedError;
      StackTrace? reportedStackTrace;
      bool isDone = false;
      int errorReportCount = 0;

      final safeCollector = sharedFlow.collectSafely((value) {
        collectedValues.add(value);
        if (value == 1) {
          throw customError;
        }
      });

      safeCollector.tryCatch((e, s) {
        reportedError = e;
        reportedStackTrace = s;
        errorReportCount++;
      }).done(() {
        isDone = true;
      });

      await Future.delayed(Duration.zero); // Allow initial replay
      sharedFlow.emit(1); // Triggers error
      await Future.delayed(Duration.zero); // Allow error to be processed

      expect(collectedValues, [0, 1],
          reason: "Should collect up to the erroring value.");
      expect(reportedError, customError,
          reason: "Error reported to tryCatch should be the customError.");
      expect(reportedStackTrace, isNotNull,
          reason: "Stack trace should be reported.");
      expect(errorReportCount, 1, reason: "Error should be reported once.");
      expect(isDone, true,
          reason: "onDone should be called from the error in lambda.");

      sharedFlow.emit(2);
      await Future.delayed(Duration.zero);

      expect(collectedValues, [0, 1], reason: "Shouldn't continue collecting after error was reported.");
    });
    test(
        'replay cache updates correctly with ongoing emissions and new collectors',
        () async {
      final sharedFlow = SharedFlow<int>(replay: 2);
      sharedFlow.emit(1);
      sharedFlow.emit(2);
      sharedFlow.emit(3);
      sharedFlow.emit(4); // Replay cache should now be [3, 4]

      await Future.delayed(Duration.zero);

      final collectedA = <int>[];
      final completerA = Completer<void>();
      sharedFlow.collect((value) {
        collectedA.add(value);
        if (value == 5 && collectedA.length == 3) {
          // Expecting 3, 4, 5
          completerA.complete();
        }
      });

      await Future.delayed(
          Duration.zero); // Allow collector A to process replays
      sharedFlow.emit(5); // Emit after A starts collecting

      await completerA.future.timeout(const Duration(milliseconds: 100));
      expect(collectedA, [3, 4, 5]);

      // At this point, replay cache should be [4, 5]
      final collectedB = <int>[];
      final completerB = Completer<void>();
      sharedFlow.collect((value) {
        collectedB.add(value);
        if (value == 6 && collectedB.length == 3) {
          // Expecting 4, 5, 6
          completerB.complete();
        }
      });

      await Future.delayed(
          Duration.zero); // Allow collector B to process replays
      sharedFlow.emit(6); // Emit after B starts collecting

      await completerB.future.timeout(const Duration(milliseconds: 100));
      expect(collectedB, [4, 5, 6]);

      sharedFlow.close();
    });
  });
}
