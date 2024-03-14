import 'dart:async';

import 'builders.dart';
import 'collectors/flow_collector.dart';
import 'collectors/collectors.dart';

/// @author Paul Okeke
///
/// Flow Api
///
/// Experimental Flow API for asynchronous data processing.
///
/// This abstract interface represents a flow of values of type `T` within the
/// Flow API. It provides a foundation for building asynchronous data pipelines.
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
}

abstract class AbstractFlow<T> extends Flow<T> {
  @override
  FutureOr<void> collect(FutureOr<void> Function(T value) collector) async {
    StreamController<T> controller = StreamController(sync: false);
    final flowCollector = FlowCollectorImpl<T>(controller.sink);
    final Completer completer = Completer();
    controller.onListen = () async {
      try {
        await collectSafely(flowCollector);
        completer.complete();
      } catch (e) {
        controller.addError(e);
      }
    };

    scheduleMicrotask(() {
      controller.stream.listen((event) {
        collector.call(event);
      }, onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      });
    });

    await completer.future;
    await controller.close();
  }

  FutureOr<void> collectSafely(FlowCollector<T> collector);
}

final class SafeFlow<T> extends AbstractFlow<T> {
  final FutureOr<void> Function(FlowCollector<T>) block;

  SafeFlow(this.block);

  @override
  FutureOr<void> collectSafely(FlowCollector<T> collector) async {
    await block.call(collector);
  }
}

///=============================================================================
class ExperimentalFlowApi {
  const ExperimentalFlowApi();
}
