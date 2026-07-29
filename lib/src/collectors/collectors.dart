
import 'dart:async';

import 'flow_collector.dart';

/// Concrete implementation of the FlowCollector interface.
///
/// Backed by the [StreamController] itself, not just its sink — so [emit]
/// and [addError] can check [StreamController.isClosed] first. Cancellation
/// in this library is cooperative (closing a downstream controller doesn't
/// preempt an in-flight upstream emit already on its way), so a late call
/// arriving after close is an expected race, not a bug — it's dropped
/// silently instead of throwing, matching how `Stream.multi` already
/// ignores adds from a cancelled listener.
final class FlowCollectorImpl<T> implements FlowCollector<T> {
  final StreamController<T> _controller;

  FlowCollectorImpl(this._controller);

  @override
  void addError(Object e, [StackTrace? trace]) {
    if (_controller.isClosed) return;
    _controller.addError(e, trace);
  }

  @override
  void emit(T value) {
    if (_controller.isClosed) return;
    _controller.add(value);
  }

  @override
  void close() => _controller.close();
}