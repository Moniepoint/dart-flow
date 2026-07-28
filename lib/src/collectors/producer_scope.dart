import 'dart:async';

import 'flow_collector.dart';

/// A [FlowCollector] that can also launch concurrent work.
///
/// Passed to the callback given to `channelFlow`. Unlike a plain
/// `flow<T>((collector) async {...})` block — which closes as soon as the
/// callback's returned future completes, regardless of any fire-and-forget
/// work still running — a `channelFlow`'s scope doesn't finish until every
/// action passed to [launch] has completed too. This makes it safe to
/// `await` something that never completes on its own (e.g. forwarding a
/// live database watch stream) while concurrently running a one-shot
/// operation (e.g. a network fetch) alongside it.
///
/// Example:
/// ```dart
/// channelFlow<DashboardData>((scope) async {
///   // Runs concurrently — doesn't block the line below. Any uncaught
///   // error is routed to scope.addError automatically.
///   scope.launch(() => fetchAndSyncFreshData());
///
///   // Never returns on its own — keeps the channelFlow open for as long
///   // as it's subscribed, forwarding every value the watch stream emits,
///   // including ones caused by the write above.
///   await database.watchDashboardData().collect(scope.emit);
/// });
/// ```
abstract class ProducerScope<T> implements FlowCollector<T> {
  /// Runs [action] concurrently with the rest of the `channelFlow` block
  /// and with any other launched action.
  ///
  /// An uncaught error thrown by [action] is routed to [addError] — it
  /// does not terminate the scope or any other launched action.
  ///
  /// The scope this [ProducerScope] belongs to will not be considered
  /// finished until every launched action (including ones launched by
  /// another launched action) has completed.
  void launch(FutureOr<void> Function() action);
}
