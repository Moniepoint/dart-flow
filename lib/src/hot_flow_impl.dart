import 'dart:async';
import 'package:flow/src/collectors/safe_collector.dart';
import 'package:flow/src/flowimpl.dart';
import 'package:flow/src/task_pool_executor.dart'; 
import 'package:meta/meta.dart';

/// An abstract base class for "hot" flows.
///
/// Hot flows are flows that can have multiple collectors and typically maintain a
/// current value or state. They start emitting values as soon as they are created
/// or when their underlying source starts producing data, independently of whether
/// there are active collectors.
///
/// This class manages a broadcast [StreamController] to allow multiple listeners
/// and handles common logic for value dispatching, collection, and closing.
@ExperimentalFlowApi()
abstract class AbstractHotFlow<T> implements Flow<T> {
  /// The underlying broadcast stream controller that manages value emissions.
  @protected
  final StreamController<T> controller;

  /// Indicates whether the flow has been closed.
  bool _isClosed = false;

  /// Initializes the hot flow with a synchronous broadcast [StreamController].
  AbstractHotFlow() : controller = StreamController<T>.broadcast(sync: true);

  /// Returns `true` if this flow has been closed via the [close] method.
  /// Once closed, a flow cannot emit new values and new collectors will typically
  /// complete immediately or receive a last known state if applicable.
  bool get isClosed => _isClosed;

  /// Dispatches a new [value] to all active collectors of this flow.
  ///
  /// If the flow [isClosed], this method does nothing.
  /// This method is intended for internal use by subclasses.
  @protected
  void dispatchValue(T value) {
    if (_isClosed) {
      return;
    }
    controller.add(value);
  }

  /// Abstract method for subclasses to implement logic for emitting initial
  /// or current values to a new [collector].
  ///
  /// This is called when [collectSafely] is invoked, allowing the hot flow
  /// to provide its current state or any relevant initial values to the collector
  /// before it starts receiving ongoing updates.
  /// This method is intended for internal use by subclasses.
  @protected
  FutureOr<void> emitInitialValues(FutureOr<void> Function(T value) collector);

  /// Terminal operator that starts the collection of values from this flow.
  ///
  /// This method uses a [Zone] to manage the execution context and relies on
  /// [collectSafely] for the actual collection logic. It returns a [Future]
  /// that completes when the collection is done or an error occurs.
  ///
  /// See [Flow.collect] for more general information on collection.
  ///
  /// [collector]: A callback function that will be invoked for each value emitted
  /// by the flow.
  @override
  FutureOr<void> collect(FutureOr<void> Function(T value) collector) {
    if (_isClosed) {
      return Future.value();
    }

    final context = currentTaskPool() ?? TaskPoolExecutor();
    final completer = Completer<void>();

    // Note: The original runZonedGuarded is replaced by a simpler runZoned call based on previous discussions.
    // The error handling is now primarily managed by the SafeCollector and the completer's future.
    return runZoned(() {
      context.registerTask(Task(ExecutionType.signalCollection));

      final SafeCollector safeCollector = collectSafely(collector);

      safeCollector.tryCatch((e, s) {
        if (!completer.isCompleted) {
          completer.completeError(e, s is StackTrace ? s : null);
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

  /// Provides a safe mechanism to collect values from this flow, handling
  /// initial emissions and subsequent updates.
  ///
  /// When invoked, this method first schedules a microtask to:
  /// 1. Call [emitInitialValues] to provide the current state or initial values
  ///    to the [collector].
  /// 2. Subscribe to the internal [controller]'s stream to receive ongoing updates.
  ///
  /// It uses a [SafeCollector] to manage error handling and completion signals.
  /// If the [collector] lambda throws an error, or if the underlying stream
  /// encounters an error, the collection is stopped, and the error is propagated
  /// via the [SafeCollector].
  ///
  /// [collector]: A callback function that processes each emitted value.
  /// Returns a [SafeCollector] instance that can be used to further configure
  /// error handling or completion logic.
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
            if (isCollectionProcessActive) {
              safeCollector.sendError(e, s);
              cancelSubscriptionAndMarkDone();
            }
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
          if (isCollectionProcessActive) {
            safeCollector.sendError(e, s);
            cancelSubscriptionAndMarkDone();
          }
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

  /// Closes this hot flow.
  ///
  /// After calling [close]:
  /// - The flow is marked as closed ([isClosed] will be `true`).
  /// - No new values will be dispatched via [dispatchValue].
  /// - The underlying [StreamController] is closed.
  /// - Existing collectors will typically be completed via their `onDone` callbacks.
  /// - New attempts to collect will result in immediate completion.
  /// Calling [close] multiple times has no additional effect.
  void close() {
    if (!_isClosed) {
      _isClosed = true;
      controller.close();
    }
  }
}

/// A specialized hot flow that holds a single piece of state ([value]).
///
/// A `StateFlow` is a shareable, replayable hot [Flow]. It emits the current
/// state to new collectors and then continues to emit subsequent state updates.
/// If the value being set is the same as the current value (according to the
/// [_areEqual] comparator), no new emission occurs.
///
/// This is conceptually similar to `BehaviorSubject` in RxDart or `StateFlow`
/// in Kotlin Coroutines.
///
/// Example:
/// ```dart
/// final stateFlow = StateFlow<int>(0); // Initial state is 0
/// print(stateFlow.value); // Output: 0
///
/// stateFlow.collect(print); // Collector 1: prints 0 immediately, then updates
///
/// stateFlow.value = 1; // Collector 1: prints 1
/// stateFlow.value = 1; // No emission, value is the same
///
/// stateFlow.collect(print); // Collector 2: prints 1 immediately (current state)
///
/// stateFlow.value = 2; // Collector 1 & 2: print 2
/// stateFlow.close();
/// ```
class StateFlow<T> extends AbstractHotFlow<T> {
  /// The current state value of this flow.
  T _currentValue;

  /// A function used to compare the old and new state values.
  /// Emissions are skipped if this function returns `true`.
  final bool Function(T oldValue, T newValue) _areEqual;

  /// Creates a [StateFlow] with an [initialValue].
  ///
  /// An optional [areEqual] function can be provided to customize how
  /// state equality is determined. If not provided, it defaults to standard
  /// equality (`==`).
  StateFlow(T initialValue, {bool Function(T oldValue, T newValue)? areEqual})
      : _currentValue = initialValue,
        _areEqual = areEqual ?? ((a, b) => a == b),
        super();

  /// Gets the current state value synchronously.
  T get value => _currentValue;

  /// Sets a new state [newValue] for this flow.
  ///
  /// If the flow [isClosed], the new value is ignored.
  /// If the [newValue] is considered equal to the current [value] by the
  /// [_areEqual] function, the new value is not emitted, though the internal
  /// state might still be updated if `_areEqual` only checks emission criteria.
  /// (Note: current implementation updates `_currentValue` only if `!_areEqual`).
  /// Otherwise, `_currentValue` is updated, and the new value is dispatched
  /// to all collectors.
  set value(T newValue) {
    if (isClosed) return;
    if (!_areEqual(_currentValue, newValue)) {
      _currentValue = newValue;
      dispatchValue(_currentValue);
    }
  }

  /// Updates the state of this flow to [newValue].
  /// This is a convenience method equivalent to setting the [value] property.
  void update(T newValue) {
    this.value = newValue;
  }

  /// Emits the current [_currentValue] to the [collector].
  ///
  /// This is called by [collectSafely] to provide the initial state to
  /// a new collector.
  @override
  @protected
  FutureOr<void> emitInitialValues(FutureOr<void> Function(T value) collector) async {
    // Ensure that the collector lambda itself is awaited if it's async
    await collector(_currentValue);
  }
}
