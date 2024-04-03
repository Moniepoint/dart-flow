import 'dart:async';

import 'package:flow/flow.dart';
import 'package:flow/src/collectors/collectors.dart';
import 'collectors/flow_collector.dart';
import 'collectors/safe_collector.dart';
import 'task_pool_executor.dart';

/// @author Paul Okeke
///
/// Flow Api
///
/// Experimental Flow API for asynchronous data processing.

class ExperimentalFlowApi {
  const ExperimentalFlowApi();
}

/// This abstract interface represents a flow of values of type `T` within the
/// Flow API. It provides a foundation for building asynchronous data pipelines
/// in a structured pattern.
@ExperimentalFlowApi()
abstract interface class Flow<T> {
  
  /// Creates an empty Flow instance.
  ///
  /// This constructor is the starting point for subclasses to implement
  /// the flow. This constructor cannot be instantiated as this class as marked
  /// `abstract interface`. To create a flow use one of the flow builders.
  Flow();

  /// Creates a factory for an empty Flow.
  ///
  /// This factory method provides a convenient way to create an empty Flow
  /// without the need for explicit instantiation.
  factory Flow.empty() => flow((_) => null);

  /// Terminal operator for collecting values from the Flow.
  ///
  /// This method consumes the values emitted by the Flow and passes each value
  /// to the provided collector function. It's a terminal operator, meaning it
  /// marks the completion of the flow's processing.
  ///
  /// [collector] : A function that takes a value of type `T` and returns a
  /// `FutureOr<void>`. It's responsible for handling each value emitted by the Flow.
  FutureOr<void> collect(FutureOr<void> Function(T value) collector) => ();

  /// Terminal operator for collecting values from the Flow in a safe manner.
  ///
  /// This method provides a safer alternative to the direct `collect` method
  /// by offering customization options for error handling and completion behavior.
  /// It returns a `SafeCollector` object for configuration before actual collection.
  ///
  /// [collector] : A function that takes a value of type `T` and returns a
  /// `FutureOr<void>`. It's responsible for handling each value emitted by the Flow.
  SafeCollector collectSafely(FutureOr<void> Function(T value) collector) => SafeCollector();
}


abstract class AbstractFlow<T> extends Flow<T> {
  AbstractFlow({StreamController<T>? controller}) {
    _controller = controller ?? StreamController.broadcast(sync: false);
    _flowCollector = FlowCollectorImpl(_controller!.sink);
    _controller?.onListen = onListen;
  }

  FlowCollector<T>? _flowCollector;
  StreamController<T>? _controller;
  StreamSubscription<T>? _subscription;

  void onListen() async {
    final taskPool = currentTaskPool();
    try {
      taskPool?.registerTask(Task(
          ExecutionType.signalInvocation,
          close: _dispose,
          invocationId: _controller.hashCode
      ));
      await invokeSafely(_flowCollector!);
    } catch (e) {
      _controller?.addError(e);
    } finally {
      taskPool?.registerTask(Task(
          ExecutionType.signalClosure,
          invocationId: _controller.hashCode
      ));
    }
  }

  @override
  FutureOr<void> collect(FutureOr<void> Function(T value) collector) async {
    final context = currentTaskPool() ?? TaskPoolExecutor();

    return runZoned(() {
      final completer = Completer();
      context.registerTask(Task(ExecutionType.signalCollection));

      collectSafely(collector)
          .collectWith(_flowCollector!)
          .tryCatch((e) => completer.completeError(e))
          .done(() {
            _flowCollector!.close();
            if (!completer.isCompleted) completer.complete();
          });

      return completer.future;
    }, zoneSpecification: context.config, zoneValues: {#flow.context: context});
  }

  @override
  SafeCollector collectSafely(FutureOr<void> Function(T value) collector) {
    _closeSubscription();
    _ensureActive();

    int pendingCollection = 0;
    bool hasSignaledDoneEvent = false;

    final safeCollector = SafeCollector();

    void scheduleTask(FutureOr<void> action) async {
      try {
        pendingCollection++;
        await action;
      } catch (e, s) {
        safeCollector.sendError(e, s);
      } finally {
        pendingCollection--;
        if (hasSignaledDoneEvent && pendingCollection == 0) {
          safeCollector.onDone();
          _closeSubscription();
        }
      }
    }

    _subscription = _controller?.stream
        .listen((value) => scheduleTask(collector(value)),
        cancelOnError: false,
        onError: (e, s) => scheduleTask(safeCollector.sendError(e, s)),
        onDone: () {
          hasSignaledDoneEvent = true;
          if (pendingCollection == 0) {
            safeCollector.onDone();
            _closeSubscription();
          }
        });

    return safeCollector;
  }

  void _ensureActive() {
    if (null == _controller || true == _controller?.isClosed) {
      _controller = StreamController.broadcast(sync: false);
      _flowCollector = FlowCollectorImpl(_controller!.sink);
      _controller!.onListen = onListen;
    }
  }

  void _dispose() {
    _controller?.close();
    _controller = null;
  }

  void _closeSubscription() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> invokeSafely(FlowCollector<T> collector);
}

final class SafeFlow<T> extends AbstractFlow<T> {
  final FutureOr<void> Function(FlowCollector<T>) block;

  SafeFlow(this.block): super();

  @override
  Future<void> invokeSafely(FlowCollector<T> collector) async {
    return block.call(collector);
  }
}
