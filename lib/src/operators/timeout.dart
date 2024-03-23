
import 'dart:async';
import 'package:flow/flow.dart';

@ExperimentalFlowApi()
class Timeout<T> implements Flow<T> {
  Timer? timer;
  final completer = Completer();

  final Flow<T> upstreamFlow;
  final Duration duration;

  Timeout(this.upstreamFlow, this.duration);

  void registerTimer() {
    if (completer.isCompleted) return;
    timer = Timer(duration, () {
      completer.completeError(TimeoutCancellationException(duration));
    });
  }

  @override
  FutureOr<void> collect(FutureOr<void> Function(T value) collector) async {
    registerTimer();

    final collection = Future(() async {
      await upstreamFlow.collect((value) {
        if (!completer.isCompleted) {
          collector.call(value);
          timer?.cancel();
          registerTimer();
        }
      });
    }).then((value) {
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await Future.wait([completer.future, collection], eagerError: true);
    } catch (e) {
      timer?.cancel();
      rethrow;
    } finally {
      timer?.cancel();
      timer = null;
    }
  }
}