import 'dart:async';

import 'package:flow/flow.dart';
import 'package:test/test.dart';

class _FakeLifecycle implements FlowLifecycle {
  bool _disposed = false;
  final List<void Function()> _cleanups = [];

  @override
  bool get isDisposed => _disposed;

  @override
  void addCleanup(void Function() action) {
    if (_disposed) {
      action();
    } else {
      _cleanups.add(action);
    }
  }

  void dispose() {
    _disposed = true;
    for (final cleanup in List<void Function()>.of(_cleanups)) {
      cleanup();
    }
    _cleanups.clear();
  }
}

void main() {
  group('launchIn', () {
    test('runs the pipeline attached via onEach', () async {
      final lifecycle = _FakeLifecycle();
      final values = <String>[];

      flowOf(['A', 'B', 'C']).onEach(values.add).launchIn(lifecycle);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(values, ['A', 'B', 'C']);
    });

    test('does nothing if the lifecycle is already disposed', () async {
      final lifecycle = _FakeLifecycle()..dispose();
      final values = <String>[];

      flowOf(['A', 'B']).onEach(values.add).launchIn(lifecycle);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(values, isEmpty);
    });

    test('stops delivering further values once the lifecycle disposes', () async {
      final controller = StreamController<int>();
      final lifecycle = _FakeLifecycle();
      final values = <int>[];

      controller.stream.asFlow().onEach(values.add).launchIn(lifecycle);

      controller.add(1);
      await Future.delayed(const Duration(milliseconds: 20));
      lifecycle.dispose();
      controller.add(2);
      await Future.delayed(const Duration(milliseconds: 20));

      expect(values, [1]);
    });

    test('cancels the raw source stream once the lifecycle disposes', () async {
      final controller = StreamController<int>();
      final lifecycle = _FakeLifecycle();

      controller.stream.asFlow().onEach((_) {}).launchIn(lifecycle);

      await Future.delayed(const Duration(milliseconds: 20));
      expect(controller.hasListener, isTrue);

      lifecycle.dispose();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(controller.hasListener, isFalse);
      await controller.close();
    });

    test('cascades cancellation through a nested Flow-to-Flow chain', () async {
      final controller = StreamController<int>();
      final lifecycle = _FakeLifecycle();

      controller.stream.asFlow()
          .filter((value) => value > 0)
          .onEach((_) {})
          .launchIn(lifecycle);

      await Future.delayed(const Duration(milliseconds: 20));
      expect(controller.hasListener, isTrue);

      lifecycle.dispose();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(controller.hasListener, isFalse);
      await controller.close();
    });
  });
}
