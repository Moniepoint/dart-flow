import 'dart:async';

import 'package:flow/flow.dart';
import 'package:test/test.dart';

void main() {
  group('mapLatest', () {
    test('transforms each value when calls do not overlap', () async {
      final controller = StreamController<int>();
      final fl = controller.stream.asFlow().mapLatest((value) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return value * 10;
      });

      final events = <int>[];
      final subscription = fl.asStream().listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Spaced well past each transform call's 5ms delay, so each value is
      // fully processed before the next arrives — no overlap to coalesce.
      controller.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.add(2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.add(3);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await controller.close();
      await subscription.cancel();

      expect(events, [10, 20, 30]);
    });

    test('coalesces values that arrive while a transform call is still running — '
        'runs once more with only the latest, not once per arrival', () async {
      final controller = StreamController<int>();
      final calls = <int>[];

      final fl = controller.stream.asFlow().mapLatest((value) async {
        calls.add(value);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return value;
      });

      final events = <int>[];
      final subscription = fl.asStream().listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      controller.add(1); // starts running immediately
      await Future<void>.delayed(const Duration(milliseconds: 5));
      controller.add(2); // arrives mid-run — coalesced
      controller.add(3); // arrives mid-run — replaces 2, coalesced
      await Future<void>.delayed(const Duration(milliseconds: 60));

      await controller.close();
      await subscription.cancel();

      // 2 was superseded by 3 before the in-flight call for 1 finished —
      // only 1 (already running) and 3 (the latest once free) ran.
      expect(calls, [1, 3]);
      expect(events, [1, 3]);
    });

    test('never runs transform concurrently — at most one call in flight at a time',
        () async {
      final controller = StreamController<int>();
      var concurrent = 0;
      var maxConcurrent = 0;

      final fl = controller.stream.asFlow().mapLatest((value) async {
        concurrent++;
        maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        concurrent--;
        return value;
      });

      final subscription = fl.asStream().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 5));

      controller.add(1);
      controller.add(2);
      controller.add(3);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await controller.close();
      await subscription.cancel();

      expect(maxConcurrent, 1);
    });

    test('routes a transform error to the flow without ending it', () async {
      final controller = StreamController<int>();
      final fl = controller.stream.asFlow().mapLatest((value) async {
        if (value == 1) throw Exception('boom');
        return value;
      });

      final events = [];
      final subscription = fl.asStream().listen(
        events.add,
        onError: (Object e) => events.add(e),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));

      controller.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.add(2);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await controller.close();
      await subscription.cancel();

      expect(events, [isA<Exception>(), 2]);
    });
  });
}
