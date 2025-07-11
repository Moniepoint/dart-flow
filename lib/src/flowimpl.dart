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

  /// Merges multiple flows into a single flow that emits items in the order they are received.
  /// Example:
  /// ```dart
  /// final flow1 = flowOf([1, 2, 3]);
  /// final flow2 = flowOf([4, 5, 6]);
  /// final merged = Flow.merge([flow1, flow2]); 
  /// merged.collect(print); // prints numbers as they arrive from either flow
  /// ```
  ///
  /// [flows] : A list of flows to merge into a single flow
  ///
  /// Returns a new flow that merges all the provided flows
  static Flow<T> merge<T>(List<Flow<T>> flows) => MergeFlow<T>(flows);

  /// Combines the latest values from multiple flows into a single flow.
  /// Example:
  /// ```dart
  /// final flow1 = flowOf([1, 2, 3]);
  /// final flow2 = flowOf(['a', 'b', 'c']);
  /// final combined = Flow.combineLatest([flow1, flow2], 
  ///   (values) => '${values[0]}-${values[1]}');
  /// combined.collect(print); // prints combined values like '1-a', '2-a', '2-b'
  /// ```
  ///
  /// [flows] : A list of flows to combine
  /// [combiner] : A function that transforms the latest values from all flows into a single value
  ///
  /// Returns a new flow that combines the latest values from all provided flows using the combiner function
  static Flow<T> combineLatest<T>(List<Flow<dynamic>> flows, Combiner<T> combiner) => CombineLatestFlow<T>(flows, combiner);

  /// Creates a race between multiple flows, emitting value only from the first flow to emit.
  /// Example:
  /// ```dart
  ///  final flow1 = flow<String>((collector) async {
  ///  await Future.delayed(const Duration(milliseconds: 200));
  ///  collector.emit("A");
  ///  });
  /// final flow2 = flow<String>((collector) async {
  ///    collector.emit("B");
  ///  });
  /// final race = RaceFlow([flow1, flow2]);
  /// race.collect(print); // prints "B"
  /// ```
  ///
  /// [flows] : A list of flows to race against each other
  ///
  /// Returns a new flow that emits values only from the first flow to emit
  static Flow<T> race<T>(List<Flow<T>> flows) => RaceFlow<T>(flows);
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


/// A Flow that merges multiple source Flows into a single Flow, collecting values from each Flow sequentially.
///
/// This Flow collects values from each source Flow one at a time in the order they were provided.
/// If any source Flow emits an error, collection stops and the error is propagated.
///
/// Example:
/// ```dart
/// final flow1 = flowOf([1, 2]);
/// final flow2 = flowOf([3, 4]); 
/// final merged = MergeFlow([flow1, flow2]);
/// merged.collect(print); // prints 1, 2, 3, 4
/// ```
class MergeFlow<T> extends AbstractFlow<T> {
  /// The source Flows to merge values from
  final List<Flow<T>> flows;

  /// Creates a MergeFlow that merges values from the given [flows]
  MergeFlow(this.flows);

  @override
  Future<void> invokeSafely(FlowCollector<T> collector) async {
    if (flows.isEmpty) return;

    bool hasError = false;

    final futures = flows.map((flow) async {
      try {
        await flow.collect((value) {
          if(hasError) return;
          collector.emit(value);
        });
      } catch (e, st) {
        if (!hasError) {
          hasError = true;
          collector.addError(e, st);
        }
      }
    });

    await Future.wait(futures);
  }
}

typedef Combiner<T> = T Function(List<dynamic> values);

/// A Flow that combines the latest values from multiple source Flows into a single value.
///
/// This Flow waits for all source Flows to emit at least one value before emitting any combined values.
/// When any source Flow emits a new value, it combines the latest values from all Flows using the provided
/// combiner function and emits the result.
/// If any source Flow emits an error, collection stops and the error is propagated.
///
/// Example:
/// ```dart
/// final flow1 = flowOf([1, 2, 3]);
/// final flow2 = flowOf(['a', 'b', 'c']);
/// final combined = CombineLatestFlow([flow1, flow2], 
///   (values) => '${values[0]}-${values[1]}');
/// combined.collect(print); // prints "1-a", "2-a", "2-b", "3-b", "3-c"
/// ```
///
/// [R] The type of values emitted by this Flow after combining
class CombineLatestFlow<T> extends AbstractFlow<T> {
  /// The source Flows to combine values from
  final List<Flow<dynamic>> flows;

  /// Function that combines the latest values from all Flows into a single value
  final Combiner<T> combiner;

  /// Creates a CombineLatestFlow that combines values from the given [flows] using the [combiner] function
  CombineLatestFlow(this.flows, this.combiner);

  @override
  Future<void> invokeSafely(FlowCollector<T> collector) async {
    if (flows.isEmpty) return;
    
    final collectedValues = List<dynamic>.filled(flows.length, null);
    final isValueCollected = List<bool>.filled(flows.length, false);
    bool hasError = false;

    final futures = flows.asMap().entries.map((entry) async {
      if (hasError) return;
      
      final index = entry.key;
      final flow = entry.value;
      
      try {
        await flow.collect((value) {
        
        if (hasError) return;
        
        collectedValues[index] = value;
        isValueCollected[index] = true;
        
        if (isValueCollected.every((collected) => collected)) {
          try {
            final values = List<dynamic>.from(collectedValues);
            final combinedValue = combiner(values);
            collector.emit(combinedValue);
          } catch (e, st) {
            hasError = true;
            collector.addError(e, st);
          }
        }

      });
    
    } catch (e, st) {
      if(!hasError) {
          hasError = true;
          collector.addError(e, st);
      }
    }
    });

   await Future.wait(futures);
  }
}

/// Given two or more source Flows, emits all values from only the first Flow
/// that emits a value. After the first Flow emits, all other Flows are ignored.
///
/// If the provided list of Flows is empty, the resulting Flow completes immediately
/// without emitting any values.
/// If any source Flow emits an error, collection stops and the error is propagated.
///
/// Example:
/// ```dart
///  final flow1 = flow<String>((collector) async {
///  await Future.delayed(const Duration(milliseconds: 200));
///  collector.emit("A");
///  });
/// final flow2 = flow<String>((collector) async {
///    collector.emit("B");
///  });
/// final race = RaceFlow([flow1, flow2]);
/// race.collect(print); // prints "B"
/// ```
class RaceFlow<T> extends AbstractFlow<T> {
  /// The source Flows to race
  final List<Flow<T>> flows;

  /// Creates a RaceFlow that emits values from the first Flow in [flows] that emits
  RaceFlow(this.flows);

  @override
  Future<void> invokeSafely(FlowCollector<T> collector) async {
    if (flows.isEmpty) return;

    bool hasWinner = false;
    bool hasError = false;
    int? winnerIndex;

      final futures = flows.asMap().entries.map((entry) async {
      final index = entry.key;
      
      if (hasError || (hasWinner && index != winnerIndex)) return;

      try {
        await entry.value.collect((value) {
          if (!hasError && !hasWinner) {
            hasWinner = true;
            winnerIndex = index;
            collector.emit(value);
          } else if (index == winnerIndex && !hasError) {
            collector.emit(value);
          }
        });
      } catch (e, st) {
          if (!hasWinner) {
            hasError = true;
            collector.addError(e, st);
          }
      }
    });

    await Future.wait(futures);
  }
}