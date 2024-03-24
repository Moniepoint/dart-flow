import 'dart:async';
import 'dart:math';

import 'package:flow/flow.dart';
import 'package:flow/src/retries.dart';
import 'package:flutter_test/flutter_test.dart';

main() {
  group('ExponentialBackOff', () {
    test('test that exponential backoff policy delays for the right amount of time', () {
      int emission = 0;
      final completer = Completer();
      final stopWatch = Stopwatch();

      final fl = flow((collector) {
        emission++;
        collector.emit('A');
        if (emission < 3) throw Exception('hello');
        collector.emit('B');
      }).onStart((_) => stopWatch.start()).retryWith((cause) {
        return RetryPolicy.exponentialBackOff(baseDelay: 1000, maxAttempts: 6);
      }).onCompletion((p0, p1) {
        stopWatch.stop();
        completer.complete(stopWatch.elapsedMilliseconds);
      });

      expect(fl.asStream(), emitsInOrder([
        'A', 'A', 'A', 'B', emitsDone
      ]));

      expectLater(completer.future, completion(anyOf([
        inInclusiveRange(2000, 2100)
      ])));
    });
  });

  group('CircuitBreaker', () {
    test('test that circuit breaker stays opened for the right amount of time', () {
      int emission = 0;
      final completer = Completer();
      final stopWatch = Stopwatch();

      final circuitBreaker = RetryPolicy.circuitBreaker(
          failureThreshold: 4,
          resetTimeout: 500,
          halfOpenThreshold: 2,
          coolDownTime: (start: 200, end: 400)
      );

      const totalNoOfEmission = 7;

      final fl = flow((collector) {
        emission++;
        collector.emit('A');
        if (emission < totalNoOfEmission) throw Exception('hello');
        collector.emit('B');
      }).onStart((_) => stopWatch.start())
          .retryWith((cause) => circuitBreaker)
          .onCompletion((p0, p1) {
            stopWatch.stop();
            completer.complete(stopWatch.elapsedMilliseconds);
          });

      expect(fl.asStream(), emitsInOrder(
          List.generate(totalNoOfEmission, (index) => 'A')
              ..add('B')
              ..add(emitsDone)
      ));

      expectLater(completer.future, completion(anyOf([
        //resetTimeOut + coolDownTime(start or end)
        inInclusiveRange(700, 900)
      ])));
    });

    test('Max attempts limit is respected', () async {
      const maxAttempts = 5;
      final policy = RetryPolicy.circuitBreaker(maxAttempts: maxAttempts);
      bool shouldRetry = true;
      int attempts = 0;

      while (shouldRetry) {
        attempts++;
        shouldRetry = await policy.retry(attempts);
      }

      expect(attempts, equals(maxAttempts));
    });
  });

  group('FixedIntervalRetryPolicy Tests', () {
    test('Retry respects fixed delay', () async {
      const maxAttempts = 5;
      const delay = 3000;
      final policy = RetryPolicy.fixedInterval(delay: delay, maxAttempts: maxAttempts); // Using shorter delays for tests
      final stopwatch = Stopwatch()..start();

      // Perform a retry, which should wait for the specified delay.
      await policy.retry(1);
      stopwatch.stop();

      // Check that the elapsed time is at least the specified delay.
      // In a real test, you might mock the delay or abstract time to avoid waiting.
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(delay));
    });

    test('Max attempts limit is respected', () async {
      const maxAttempts = 3;
      final policy = RetryPolicy.fixedInterval(maxAttempts: maxAttempts);
      int attempts = 0;
      bool shouldRetry = true;

      while (shouldRetry) {
        attempts++;
        shouldRetry = await policy.retry(attempts);
      }

      // Verify the number of attempts does not exceed maxAttempts.
      expect(attempts, equals(maxAttempts));
    });
  });

  group('DecorrelatedJitterRetryPolicy Tests', () {
    test('Initial retry delay is baseDelay', () async {

      const baseDelay = 2000;

      final policy = RetryPolicy.decorrelatedJitter(baseDelay: baseDelay);
      final stopwatch = Stopwatch()..start();

      // Assuming the first retry always happens (attempts = 1).
      await policy.retry(1);
      stopwatch.stop();

      // The first delay should be at least baseDelay.
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(baseDelay));
    });

    test('Max attempts limit is respected', () async {
      const maxAttempts = 3;
      final policy = RetryPolicy.decorrelatedJitter(maxAttempts: maxAttempts);
      bool shouldRetry = true;
      int attempts = 0;

      while (shouldRetry) {
        attempts++;
        shouldRetry = await policy.retry(attempts);
      }

      expect(attempts, equals(maxAttempts));
    });
  });
}
