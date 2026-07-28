/// A minimal lifecycle contract that lets a [Flow] know when to stop
/// collecting on its own, without exposing a raw `StreamSubscription` to
/// the caller — see `FlowX.launchIn`.
///
/// Implement this on anything that has a well-defined "end" (a
/// ViewModel's dispose, a widget's `State.dispose`, a request scope,
/// etc.). The two members are named to match the shape most ViewModel
/// base classes already have (an `isDisposed` getter and an
/// `addCleanup`-style registration method), so satisfying this interface
/// is typically a zero-new-code addition on the implementing side.
abstract class FlowLifecycle {
  /// Whether this lifecycle has already ended.
  bool get isDisposed;

  /// Registers [action] to run when this lifecycle ends. If it has
  /// already ended, implementations should run [action] immediately.
  void addCleanup(void Function() action);
}
