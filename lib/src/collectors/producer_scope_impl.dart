import 'dart:async';

import 'flow_collector.dart';
import 'producer_scope.dart';

/// Concrete implementation of [ProducerScope].
///
/// Delegates [emit]/[addError]/[close] straight to the wrapped
/// [FlowCollector]. Tracks every [Future] started via [launch] so
/// [awaitAllLaunched] can wait for all of them — including ones launched
/// by another launched action while the first batch was still running —
/// before the owning `channelFlow` is allowed to finish.
final class ProducerScopeImpl<T> implements ProducerScope<T> {
  ProducerScopeImpl(this._collector);

  final FlowCollector<T> _collector;
  final List<Future<void>> _launched = [];

  @override
  void emit(T value) => _collector.emit(value);

  @override
  void addError(Object e, [StackTrace? trace]) => _collector.addError(e, trace);

  @override
  void close() => _collector.close();

  @override
  void launch(FutureOr<void> Function() action) {
    _launched.add(Future(() async {
      try {
        await action();
      } catch (e, st) {
        _collector.addError(e, st);
      }
    }));
  }

  /// Waits for every action passed to [launch] so far to complete,
  /// including any launched while awaiting the current batch.
  Future<void> awaitAllLaunched() async {
    while (_launched.isNotEmpty) {
      final pending = List<Future<void>>.of(_launched);
      _launched.clear();
      await Future.wait(pending);
    }
  }
}
