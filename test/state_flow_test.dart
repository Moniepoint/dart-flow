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
      stateFlow.value = 100;
      await Future.delayed(Duration.zero);

      final collectedValues = <int>[];
      final completer = Completer<void>();
      bool firstCollected = false;

      stateFlow.collect((value) {
        if (!firstCollected) {
          collectedValues.add(value);
          firstCollected = true;
          return;
        }
        collectedValues.add(value);
        if (value == 101 && collectedValues.length == 2) {
          if (!completer.isCompleted) completer.complete();
        } else if (collectedValues.length > 2) {
          if (!completer.isCompleted)
            completer.completeError("Collected more values than expected");
        }
      });

      await Future.delayed(Duration.zero);

      stateFlow.value = 100;
      await Future.delayed(Duration.zero);

      stateFlow.value = 101;

      await completer.future
          .timeout(const Duration(milliseconds: 100), onTimeout: () {});
      expect(collectedValues, [100, 101]);
    });

    test('custom areEqual prevents emission for equal values', () async {
      stateFlow = StateFlow<int>(1, areEqual: (a, b) => a.abs() == b.abs());
      final collectedValues = <int>[];

      final c = Completer<void>();
      int emissions = 0;
      stateFlow.collect((value) {
        collectedValues.add(value);
        emissions++;
        if (emissions == 2 && value == 2) c.complete();
      });

      await Future.delayed(Duration.zero);
      expect(stateFlow.value, 1);

      stateFlow.value = -1;
      await Future.delayed(Duration.zero);

      stateFlow.value = 2;
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

        await Future.delayed(Duration.zero);
        stateFlow.value = 1;
        await Future.delayed(Duration.zero);
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

        await Future.delayed(const Duration(milliseconds: 10));
        stateFlow.collect((value) {
          collectedValues2.add(value);
          if (value == 1 && collectedValues2.length == 2) completer2.complete();
        });

        await Future.delayed(Duration.zero);
        stateFlow.value = 1;

        await Future.wait([
          completer1.future.timeout(const Duration(milliseconds: 100)),
          completer2.future.timeout(const Duration(milliseconds: 100)),
        ]);

        expect(collectedValues1, [0, 1]);
        expect(collectedValues2, [0, 1]);
      });

      test('collection stops if lambda throws error', () async {
        final collectedValues = <int>[];
        final error = Exception('Collector error');
        bool errorCaught = false;

        FutureOr<void> collectionProcessFuture = stateFlow.collect((value) {
          collectedValues.add(value);
          if (value == 1) {
            throw error;
          }
        });

        await Future.delayed(Duration.zero);

        stateFlow.value = 1;

        try {
          await collectionProcessFuture;
          fail(
              "stateFlow.collect() should have completed with an error, but it completed normally.");
        } catch (e) {
          if (e == error) {
            errorCaught = true;
          } else {
            rethrow;
          }
        }

        expect(errorCaught, isTrue,
            reason: "The specific error was not caught.");

        stateFlow.value = 2;
        await Future.delayed(Duration.zero);

        expect(collectedValues, [0, 1],
            reason: "Collection should stop after error.");
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

        stateFlow.value = 10;
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

        await Future.delayed(Duration.zero);
        stateFlow.value = 11;
        await Future.delayed(Duration.zero);

        stateFlow.value = 12;
        await Future.delayed(Duration.zero);

        expect(collectedValues, [10, 11, 12]);
        expect(reportedError, customError);
        expect(reportedStackTrace, isNotNull);
        expect(isDone, isFalse);
      });
      test('collectSafely is done when flow is closed', () async {
        bool isDone = false;
        final safeCollector = stateFlow.collectSafely((value) {});
        safeCollector.done(() => isDone = true);

        await Future.delayed(Duration.zero);
        stateFlow.close();
        await Future.delayed(Duration.zero);
        expect(isDone, isTrue);
      });
    });

    group('close()', () {
      test('prevents new value emissions', () async {
        final collectedValues = <int>[];
        stateFlow.collect(collectedValues.add);

        await Future.delayed(Duration.zero);
        stateFlow.value = 1;
        await Future.delayed(Duration.zero);

        stateFlow.close();

        stateFlow.value = 2;
        await Future.delayed(Duration.zero);

        expect(collectedValues, [0, 1]);
      });

      test('new collect() on closed flow completes immediately without values',
          () async {
        stateFlow.close();
        await Future.delayed(Duration.zero);

        final collectedValues = <int>[];
        await stateFlow
            .timeout(const Duration(milliseconds: 50))
            .collect(collectedValues.add);

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

        await Future.delayed(Duration.zero);
        expect(onDoneCalled, isTrue);
      });

      test('setting value on closed flow has no effect', () {
        stateFlow.close();
        stateFlow.value = 100;
        expect(stateFlow.value, 0);
      });
      test('calling close multiple times is safe', () {
        expect(() => stateFlow.close(), returnsNormally);
        expect(() => stateFlow.close(), returnsNormally);
      });
    });
  });
}
