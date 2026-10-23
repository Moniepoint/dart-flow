import 'dart:async';

import 'package:flowx/flowx.dart';
import 'package:test/test.dart';

void main() {
  group('channelFlow', () {
    test('does not complete until a launched action finishes', () async {
      final fl = channelFlow<String>((scope) {
        scope.launch(() async {
          await Future.delayed(const Duration(milliseconds: 50));
          scope.emit('from launch');
        });
      });

      expect(fl.asStream(), emitsInOrder([
        'from launch',
        emitsDone,
      ]));
    });

    test('routes an uncaught error from launch to addError without ending the scope', () async {
      final fl = channelFlow<String>((scope) {
        scope.launch(() async {
          throw Exception('boom');
        });
        scope.launch(() async {
          await Future.delayed(const Duration(milliseconds: 20));
          scope.emit('still alive');
        });
      });

      expect(fl.asStream(), emitsInOrder([
        emitsError(isA<Exception>()),
        'still alive',
        emitsDone,
      ]));
    });

    test('waits for actions launched by another launched action', () async {
      final fl = channelFlow<String>((scope) {
        scope.launch(() async {
          scope.emit('parent');
          scope.launch(() async {
            await Future.delayed(const Duration(milliseconds: 30));
            scope.emit('child');
          });
        });
      });

      expect(fl.asStream(), emitsInOrder([
        'parent',
        'child',
        emitsDone,
      ]));
    });

    test('a launched action runs concurrently with an indefinitely-awaited forwarded source', () async {
      final controller = StreamController<String>();

      final fl = channelFlow<String>((scope) async {
        scope.launch(() async {
          await Future.delayed(const Duration(milliseconds: 20));
          scope.emit('fetched');
        });

        // Never completes on its own until the controller is closed —
        // mirrors forwarding a live database watch stream that stays
        // open for the lifetime of the subscription.
        await controller.stream.forEach(scope.emit);
      });

      final events = <String>[];
      final subscription = fl.asStream().listen(events.add);

      await Future.delayed(const Duration(milliseconds: 10));
      controller.add('local-1');
      await Future.delayed(const Duration(milliseconds: 30));
      controller.add('local-2');
      await Future.delayed(const Duration(milliseconds: 10));
      await controller.close();
      await subscription.cancel();

      expect(events, containsAllInOrder(['local-1', 'fetched', 'local-2']));
    });
  });
}
