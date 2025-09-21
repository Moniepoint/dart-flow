import 'dart:async';
import 'package:flow/flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StateFlow', () {
    late StateFlow<int> stateFlow;

    setUp(() {
      stateFlow = StateFlow<int>(0);
    });

    tearDown(() async {
      // Ensure the flow is closed after each test if it wasn't explicitly closed by the test
      // This might involve a short delay if collections are active,
      // or if StateFlow had a way to check if its controller is closed.
      // For simplicity, we'll just call close.
      stateFlow.close();
    });

    test('initial value is correct', () {
      expect(stateFlow.value, 0);
    });

    test('setting value updates the current value', () {
      stateFlow.value = 10;
      expect(stateFlow.value, 10);
    });

    test('update() method updates the current value', () {
      stateFlow.update(15);
      expect(stateFlow.value, 15);
    });

    test('setting the same value does not re-emit (default areEqual)',
        () async {
      final collectedValues = <int>[];
      final completer = Completer<void>();
      int collectCount = 0;

      stateFlow.collect((value) {
        collectedValues.add(value);
        collectCount++;
        if (collectCount == 2) {
          // Expecting initial + one new value
          completer.complete();
        }
      });

      // Wait for initial value to be collected
      await Future.delayed(Duration.zero);

      stateFlow.value = 5; // First change
      await Future.delayed(Duration.zero);

      stateFlow.value = 5; // Second change (same value)
      await Future.delayed(Duration.zero); // Give time for potential emit

      stateFlow.value = 6; // Third change (different value)

      await completer.future
          .timeout(const Duration(milliseconds: 100), onTimeout: () {});

      // Expected: initial (0), first distinct (5), second distinct (6)
      // The first value '0' is collected, then '5'. Setting '5' again shouldn't trigger collect. Then '6'.
      // So, if we only care about distinct emissions AFTER the initial one:
      // A better way to test "no re-emit" is to count emissions after a specific setup.

      final valuesAfterSetup = <int>[];
      final setupCompleter = Completer<void>();
      stateFlow.value = 100; // Setup value

      // Collect values, skip the first one (which is 100)
      bool firstSkipped = false;
      stateFlow.collect((value) {
        if (!firstSkipped) {
          firstSkipped = true;
          return;
        }
        valuesAfterSetup.add(value);
        if (valuesAfterSetup.length == 1 && valuesAfterSetup.first == 101) {
          if (!setupCompleter.isCompleted) setupCompleter.complete();
        }
      });
      await Future.delayed(Duration.zero); // initial 100 collected

      stateFlow.value = 100; // Set same value
      await Future.delayed(Duration.zero);
      stateFlow.value = 101; // Set different value

      await setupCompleter.future
          .timeout(const Duration(milliseconds: 100), onTimeout: () {});
      expect(valuesAfterSetup, [101]);
    });

    test('custom areEqual prevents emission for equal values', () async {
      // Custom equality: consider numbers equal if their absolute value is the same
      stateFlow = StateFlow<int>(1, areEqual: (a, b) => a.abs() == b.abs());
      final collectedValues = <int>[];

      final c = Completer<void>();
      int emissions = 0;
      stateFlow.collect((value) {
        collectedValues.add(value);
        emissions++;
        if (emissions == 2 && value == 2) c.complete(); // Initial (1), then (2)
      });

      await Future.delayed(Duration.zero); // initial
      expect(stateFlow.value, 1);

      stateFlow.value = -1; // Should not emit based on custom areEqual
      await Future.delayed(Duration.zero);

      stateFlow.value = 2; // Should emit
      await c.future
          .timeout(const Duration(milliseconds: 100), onTimeout: () {});

      expect(collectedValues, [1, 2]);
    });

    group('collect()', () {
      test('receives current value immediately and subsequent updates',
          () async {
        final collectedValues = <int>[];
        final completer = Completer<void>();

        stateFlow.collect((value) {
          collectedValues.add(value);
          if (value == 2) {
            completer.complete();
          }
        });

        // Value 0 should be collected immediately (microtask)
        // Then update values
        await Future.delayed(Duration.zero); // Allow microtask for initial emit
        stateFlow.value = 1;
        await Future.delayed(Duration.zero); // Allow microtask for next emit
        stateFlow.value = 2;

        await completer.future.timeout(const Duration(milliseconds: 100));
        expect(collectedValues, [0, 1, 2]);
      });

      test('multiple collectors receive updates', () async {
        final collectedValues1 = <int>[];
        final collectedValues2 = <int>[];
        final completer1 = Completer<void>();
        final completer2 = Completer<void>();

        stateFlow.collect((value) {
          collectedValues1.add(value);
          if (value == 1 && collectedValues1.length == 2) completer1.complete();
        });

        // Second collector after a delay, should get current value (0) then update
        await Future.delayed(const Duration(milliseconds: 10));
        stateFlow.collect((value) {
          collectedValues2.add(value);
          if (value == 1 && collectedValues2.length == 2) completer2.complete();
        });

        await Future.delayed(Duration.zero); // Allow initial emits for both
        stateFlow.value = 1;

        await Future.wait([
          completer1.future.timeout(const Duration(milliseconds: 100)),
          completer2.future.timeout(const Duration(milliseconds: 100)),
        ]);

        expect(collectedValues1, [0, 1]);
        expect(collectedValues2, [0, 1]); // Gets initial value then update
      });

      test('collection stops if lambda throws error', () async {
        final collectedValues = <int>[];
        final error = Exception('Collector error');
        bool errorCaught = false;

        // collect() itself will complete with an error if the lambda throws.
        // We catch this error to verify it's the one we expect.
        try {
          await stateFlow.collect((value) {
            collectedValues.add(value);
            if (value == 1) {
              throw error;
            }
          });
        } catch (e) {
          if (e == error) {
            // Make sure it's the exact error we threw
            errorCaught = true;
          } else {
            rethrow; // Re-throw unexpected errors
          }
        }

        // Ensure state changes have propagated
        await Future.delayed(Duration.zero);
        stateFlow.value = 2; // This should not be collected by the failed collector
        await Future.delayed(Duration.zero);

        expect(collectedValues, [0, 1]);
        expect(errorCaught, isTrue, reason: "The specific error was not caught");
      });
    });

    group('collectSafely()', () {
      test(
          'receives current value and updates; error in lambda calls sendError',
          () async {
        final collectedValues = <int>[];
        Object? reportedError;
        StackTrace? reportedStackTrace;
        bool isDone = false;
        final customError = Exception("safe collect error");

        stateFlow.value = 10; // Start with a known value
        await Future.delayed(Duration.zero);

        final safeCollector = stateFlow.collectSafely((value) {
          collectedValues.add(value);
          if (value == 11) {
            throw customError;
          }
        });

        safeCollector.tryCatch((e, s) {
          reportedError = e;
          reportedStackTrace = s;
        }).done(() {
          isDone = true;
        });

        await Future.delayed(Duration.zero); // Initial value 10
        stateFlow.value = 11; // Triggers error
        await Future.delayed(Duration.zero);

        // As per current state_flow.dart, collection continues after error
        stateFlow.value = 12;
        await Future.delayed(Duration.zero);

        expect(collectedValues,
            [10, 11, 12]); // Error thrown for 11, but collection continues
        expect(reportedError, customError);
        expect(reportedStackTrace, isNotNull);
        expect(isDone,
            isFalse); // Collection not "done" by stream controller itself

        // If the behavior was to stop collection on error (by uncommenting lines):
        // expect(collectedValues, [10, 11]);
        // expect(isDone, isTrue);
      });
      test('collectSafely is done when flow is closed', () async {
        bool isDone = false;
        final safeCollector = stateFlow.collectSafely((value) {
          // Do nothing
        });
        safeCollector.done(() => isDone = true);

        await Future.delayed(Duration.zero);
        stateFlow.close();
        await Future.delayed(Duration.zero); // Allow onDone to propagate

        // This test depends on how 'close' interacts with ongoing 'collectSafely'
        // If 'close' makes the controller 'done', then SafeCollector will be done.
        expect(isDone, isTrue);
      });
    });

    group('close()', () {
      test('prevents new value emissions', () async {
        final collectedValues = <int>[];
        stateFlow.collect(collectedValues.add);

        await Future.delayed(Duration.zero); // initial
        stateFlow.value = 1;
        await Future.delayed(Duration.zero);

        stateFlow.close();

        stateFlow.value = 2; // Should not be collected
        await Future.delayed(Duration.zero);

        expect(collectedValues, [0, 1]);
      });

      test('new collect() on closed flow completes immediately without values',
          () async {
        stateFlow.close();
        await Future.delayed(Duration.zero); // ensure close propagates

        final collectedValues = <int>[];
        await stateFlow
            .timeout(const Duration(milliseconds: 10))
            .collect(collectedValues.add); // Ensure it doesn't hang

        expect(collectedValues, isEmpty);
      });

      test('new collectSafely() on closed flow calls onDone immediately',
          () async {
        stateFlow.close();
        await Future.delayed(Duration.zero);

        bool onDoneCalled = false;
        final safeCollector = stateFlow.collectSafely((value) {
          fail("Collector should not be called on a closed flow");
        });
        safeCollector.done(() => onDoneCalled = true);

        await Future.delayed(Duration.zero); // allow microtask for onDone
        expect(onDoneCalled, isTrue);
      });

      test('setting value on closed flow has no effect', () {
        stateFlow.close();
        stateFlow.value = 100; // Original value was 0
        expect(stateFlow.value, 0); // Value should not have changed
      });
      test('calling close multiple times is safe', () {
        expect(() => stateFlow.close(), returnsNormally);
        expect(() => stateFlow.close(), returnsNormally); // Call again
      });
    });
  });
}
