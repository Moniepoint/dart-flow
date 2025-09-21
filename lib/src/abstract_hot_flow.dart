import 'dart:async';
import 'package:flow/src/collectors/safe_collector.dart';
import 'package:flow/src/flowimpl.dart';
import 'package:flow/src/task_pool_executor.dart'; // Added import
import 'package:meta/meta.dart';

abstract class AbstractHotFlow<T> implements Flow<T> {
  @protected
  final StreamController<T> controller;
  bool _isClosed = false;

  AbstractHotFlow() : controller = StreamController<T>.broadcast(sync: true);

  bool get isClosed => _isClosed;

  @protected
  void dispatchValue(T value) {
    if (_isClosed) {
      return;
    }
    controller.add(value);
  }

  @protected
  FutureOr<void> emitInitialValues(FutureOr<void> Function(T value) collector);

  @override
  FutureOr<void> collect(FutureOr<void> Function(T value) collector) {
    if (_isClosed) {
      return Future.value();
    }

    final context = currentTaskPool() ?? TaskPoolExecutor();
    final completer = Completer<void>();

    return runZoned(() {
      context.registerTask(Task(ExecutionType.signalCollection));

      final SafeCollector safeCollector = collectSafely(collector);

      safeCollector.tryCatch((Object e, [StackTrace? s]) {
        if (!completer.isCompleted) {
          completer.completeError(e, s);
        }
      }).done(() {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      return completer.future.whenComplete(() {
        context.registerTask(Task(
          ExecutionType.signalClosure,
          invocationId: Zone.current.hashCode,
        ));
      });
    }, zoneSpecification: context.config, zoneValues: {#flow.context: context});
  }

  @override
  SafeCollector collectSafely(FutureOr<void> Function(T value) collector) {
    final safeCollector = SafeCollector();
    StreamSubscription<T>? subscription;
    bool isCollectionProcessActive = true;

    void cancelSubscriptionAndMarkDone() {
      if (isCollectionProcessActive) {
        isCollectionProcessActive = false;
        subscription?.cancel();
        safeCollector.onDone();
      }
    }

    if (_isClosed) {
      Future.microtask(() => safeCollector.onDone());
      return safeCollector;
    }

    Future.microtask(() async {
      if (!isCollectionProcessActive || _isClosed) {
        if (isCollectionProcessActive) safeCollector.onDone();
        isCollectionProcessActive = false;
        return;
      }

      try {
        await emitInitialValues((T initialValue) async {
          if (!isCollectionProcessActive) return;
          try {
            await collector(initialValue);
          } catch (e, s) {
            if (isCollectionProcessActive) safeCollector.sendError(e, s);
          }
        });
      } catch (e, s) {
        if (isCollectionProcessActive) {
          safeCollector.sendError(e, s);
          cancelSubscriptionAndMarkDone();
        }
        return;
      }

      if (!isCollectionProcessActive || _isClosed) {
        if (isCollectionProcessActive) safeCollector.onDone();
        isCollectionProcessActive = false;
        return;
      }

      subscription = controller.stream.listen((newValue) async {
        if (!isCollectionProcessActive) return;
        try {
          await collector(newValue);
        } catch (e, s) {
          if (isCollectionProcessActive) safeCollector.sendError(e, s);
        }
      }, onError: (e, s) {
        if (isCollectionProcessActive) {
          safeCollector.sendError(e, s);
          cancelSubscriptionAndMarkDone();
        }
      }, onDone: () {
        if (isCollectionProcessActive) {
          cancelSubscriptionAndMarkDone();
        }
      });
    });

    return safeCollector;
  }

  void close() {
    if (!_isClosed) {
      _isClosed = true;
      controller.close();
    }
  }
}
