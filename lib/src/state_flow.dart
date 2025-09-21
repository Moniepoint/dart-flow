import 'dart:async';

import 'package:flow/src/flowimpl.dart';
import 'package:flow/src/collectors/safe_collector.dart';
import 'package:flow/src/task_pool_executor.dart';

/// A Flow that holds a single value and emits it to new collectors,
/// followed by subsequent updates to the value.
///
/// StateFlow is a hot flow: it's active as soon as created and stores the latest value.
/// New collectors immediately receive the current value.
/// It only emits new values if they are different from the current one (using `areEqual`).
class StateFlow<T> implements Flow<T> {
  T _value;
  final bool Function(T oldValue, T newValue) _areEqual;
  final StreamController<T> _controller;
  bool _isClosed = false;

  StateFlow(T initialValue, {bool Function(T oldValue, T newValue)? areEqual})
      : _value = initialValue,
        _areEqual = areEqual ?? ((a, b) => a == b),
        _controller = StreamController<T>.broadcast();

  /// The current value.
  T get value => _value;

  /// Sets a new value. If different from the current value,
  /// it's updated and emitted to collectors.
  set value(T newValue) {
    if (_isClosed) return; // Modification: Check if closed
    if (!_areEqual(_value, newValue)) {
      _value = newValue;
      _controller.add(newValue);
    }
  }

  /// Alias for the value setter.
  void update(T newValue) {
    this.value = newValue;
  }

  @override
  FutureOr<void> collect(FutureOr<void> Function(T value) collector) {
    if (_isClosed) return Future.value();

    final context = currentTaskPool() ?? TaskPoolExecutor();
    final completer = Completer<void>();
    StreamSubscription<T>? subscriptionForThisCollector;

    Future<void> safeEmit(T val) async {
      try {
        await collector(val);
      } catch (e, s) {
        if (!completer.isCompleted) {
          completer.completeError(e, s);
        }
        subscriptionForThisCollector?.cancel();
      }
    }

    return runZoned(() {
      context.registerTask(Task(ExecutionType.signalCollection));

      Future.microtask(() async {
        if (_isClosed || completer.isCompleted) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        await safeEmit(_value);

        if (_isClosed || completer.isCompleted) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        
        subscriptionForThisCollector = _controller.stream.listen(
          (newValue) async {
            if (completer.isCompleted) {
              subscriptionForThisCollector?.cancel();
              return;
            }
            await safeEmit(newValue);
          },
          onError: (e, s) {
            if (!completer.isCompleted) {
              completer.completeError(e, s);
            }
            subscriptionForThisCollector?.cancel();
          },
          onDone: () {
            if (!completer.isCompleted) {
              completer.complete();
            }
          }
        );
      });

      return completer.future.whenComplete(() {
        subscriptionForThisCollector?.cancel();
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
    if (_isClosed) {
      Future.microtask(() => safeCollector.onDone());
      return safeCollector;
    }

    StreamSubscription<T>? selfManagedSubscription;
    bool collectionActive = true; 

    Future<void> performCollection() async {
      if (!collectionActive || _isClosed) return;

      try {
        await collector(_value);
        if (!collectionActive) return;

        selfManagedSubscription = _controller.stream.listen((newValue) async {
          if (!collectionActive) {
            selfManagedSubscription?.cancel();
            return;
          }
          try {
            await collector(newValue);
          } catch (e, s) {
            if (collectionActive) {
              safeCollector.sendError(e, s);
              // Optionally, consider stopping this specific collection on collector error
              // collectionActive = false;
              // selfManagedSubscription?.cancel();
              // safeCollector.onDone();
            }
          }
        }, onError: (e, s) {
          if (collectionActive) {
            safeCollector.sendError(e, s);
            collectionActive = false;
            selfManagedSubscription?.cancel();
            safeCollector.onDone(); 
          }
        }, onDone: () {
          if (collectionActive) {
            collectionActive = false;
            selfManagedSubscription?.cancel(); 
            safeCollector.onDone(); 
          }
        });
      } catch (e, s) {
        if (collectionActive) {
          safeCollector.sendError(e, s);
          collectionActive = false; 
          safeCollector.onDone(); 
        }
      }
    }

    Future.microtask(performCollection);
    return safeCollector;
  }

  void close() {
    if (_isClosed) return;
    _controller.close();
    _isClosed = true;
  }
}
