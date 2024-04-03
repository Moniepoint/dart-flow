
import 'dart:async';
import 'package:flow/flow.dart';
import 'package:flow/src/collectors/flow_collector.dart';

/// A flow wrapper that imposes a timeout on the collection process of an
/// upstream flow.
///
/// The [Timeout] class is used to ensure that the collection process of an
/// upstream flow completes within a specified duration. If the collection
/// process exceeds the duration, the [Timeout] class completes with a timeout
/// error.
///
/// Usage:
/// ```dart
/// final upstreamFlow = flow<int>((collector) async {
///   // Simulate a delay in emitting values
///   await Future.delayed(Duration(seconds: 2));
///   collector.emit(1);
///   collector.emit(2);
/// });
///
/// final timeoutFlow = Timeout(upstreamFlow, Duration(seconds: 1));
///
/// timeoutFlow.collect(print); // Will throw TimeoutCancellationException
/// ```
@ExperimentalFlowApi()
class Timeout<T> extends AbstractFlow<T> {
  /// The timer used to enforce the timeout duration.
  Timer? timer;

  /// A completer used to signal completion or timeout.
  final completer = Completer();

  /// The upstream flow to which the timeout is applied.
  final Flow<T> upstreamFlow;

  /// The duration after which the timeout occurs.
  final Duration duration;


  final Zone _context = Zone.current.parent ?? Zone.root;

  /// Constructs a [Timeout] instance with the specified upstream flow and
  /// duration.
  ///
  /// The [upstreamFlow] parameter represents the flow whose collection process
  /// is subject to the timeout.
  ///
  /// The [duration] parameter specifies the maximum duration for the collection
  /// process.
  Timeout(this.upstreamFlow, this.duration);

  void registerTimer() {
    if (completer.isCompleted) return;
    _context.run(() {
      timer?.cancel();
      timer = Timer(duration, () {
        completer.completeError(TimeoutCancellationException(duration));
      });
    });
  }

  void _closeTimer() {
    _context.run(() {
      timer?.cancel();
      timer = null;
    });
  }

  @override
  Future<void> invokeSafely(FlowCollector<T> collector) async {
    registerTimer();

    upstreamFlow.collectSafely((value) {
      if (!completer.isCompleted) {
        collector.emit(value);
        timer?.cancel();
        registerTimer();
      }
    }).collectWith(collector).done(() {
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await Future.wait([completer.future], eagerError: true);
    } catch (e) {
      collector.addError(e);
    } finally {
      _closeTimer();
    }
  }
}