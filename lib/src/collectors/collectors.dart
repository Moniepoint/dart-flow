
import 'dart:async';

import 'flow_collector.dart';

/// Concrete implementation of the FlowCollector interface.
///
/// This class provides a concrete implementation of the `FlowCollector<T>`
/// interface. It utilizes an `EventSink<T>` object to emit values into the flow.
final class FlowCollectorImpl<T> implements FlowCollector<T> {
  /// Internal EventSink used for emitting data.
  final EventSink<T> _sink;

  /// Constructor for FlowCollectorImpl.
  ///
  /// Takes an `EventSink<T>` object as an argument. This `_sink` is likely
  /// used internally to send data downstream in the flow.
  FlowCollectorImpl(this._sink);

  @override
  void addError(Object e, [StackTrace? trace]) => _sink.addError(e, trace);

  /// Emits a value of type `T` into the flow (overrides emit from FlowCollector).
  ///
  /// This method delegates the emission of the `value` to the internal
  /// `_sink` object. The `_sink` object is responsible for the actual data
  /// transmission mechanism within the Flow.
  @override
  void emit(T value) => _sink.add(value);

  @override
  void close() => _sink.close();
}