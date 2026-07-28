import 'dart:async';

/// A cancel-once, notify-listeners primitive threaded through the current
/// [Zone] (see [currentCancellationSignal]) so nested Flow operations can
/// cascade their own teardown without the code that created them having to
/// check anything explicitly.
final class CancellationSignal {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  /// Whether [cancel] has already been called.
  bool get isCancelled => _cancelled;

  /// Cancels this signal, synchronously notifying every listener
  /// registered via [onCancel]. Idempotent — calling this more than once
  /// has no further effect.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  /// Registers [listener] to run when [cancel] is called. If this signal
  /// is already cancelled, [listener] runs immediately.
  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }
}

const Symbol _cancellationZoneKey = #flow.cancellation;

/// The [CancellationSignal] established by the nearest enclosing
/// `launchIn` call, if any. Flow internals use this to cascade teardown
/// through nested Flow operations automatically — see [FlowX.launchIn].
CancellationSignal? currentCancellationSignal() {
  final value = Zone.current[_cancellationZoneKey];
  return value is CancellationSignal ? value : null;
}

/// Runs [body] with [signal] established as the current
/// [currentCancellationSignal] for the duration of the call.
R runWithCancellationSignal<R>(CancellationSignal signal, R Function() body) {
  return runZoned(body, zoneValues: {_cancellationZoneKey: signal});
}
