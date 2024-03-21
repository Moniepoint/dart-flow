import 'dart:async';

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
        inInclusiveRange(2000, 2030)
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
  });
}
