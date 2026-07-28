
import 'dart:async';

import 'collectors/flow_collector.dart';
import 'collectors/producer_scope.dart';
import 'flowimpl.dart';

/// FlowBuilders
///
/// Creates a new Flow with the given action.
///
/// This function is a general-purpose way to create a Flow instance. It
/// takes a function ([action]) that will be responsible for emitting values
/// within the Flow.
///
/// Example:
/// ```dart
///  flow<int>((collector) {
///     collector.emit();
///  });
///
///  // Practical usage in application
///
///  class UserService {
///    Flow<User> getUserById(int id) => flow((collector) async {
///       final apiUser = await httpService.getUser(id);
///       collector.emit(apiUser);
///    });
///  }
/// ```
///
/// [action] : A function that takes a `FlowCollector<T>` as an argument and
/// is responsible for emitting values of type `T` into the flow.
Flow<T> flow<T>(FutureOr<void> Function(FlowCollector<T> collector) action) {
  return SafeFlow<T>(action);
}


/// Creates a Flow from an iterable collection of elements.
///
/// This function provides a convenient way to create a Flow that emits a
/// fixed sequence of values from an `Iterable<T>`. It's useful for processing
/// collections of data within the Flow.
///
/// Example:
/// ```dart
///  flowOf<int>([1, 2, 3, 4, 5, 6]).collect(print);
/// ```
///
/// [elements] : An `Iterable<T>` containing the elements to be emitted by the Flow.
Flow<T> flowOf<T>(Iterable<T> elements) => flow((collector) {
  for (var element in elements) {
    collector.emit(element);
  }
});

/// Creates a new Flow whose [action] is given a [ProducerScope], which can
/// launch concurrent work via [ProducerScope.launch] without the Flow
/// closing early.
///
/// A plain `flow<T>((collector) async {...})` closes as soon as its
/// callback's returned future completes — any fire-and-forget work still
/// running is orphaned, not awaited. `channelFlow` doesn't finish until
/// both [action] returns AND every action passed to [ProducerScope.launch]
/// has completed, so it's safe to concurrently launch a one-shot operation
/// alongside a line that awaits something that never completes on its own
/// (e.g. forwarding a live stream).
///
/// Example:
/// ```dart
/// Flow<DashboardData> getDashboardData(String userId) {
///   return channelFlow<DashboardData>((scope) async {
///     // Runs concurrently with the line below — an uncaught error here
///     // routes to scope.addError, it doesn't close the scope.
///     scope.launch(() => fetchAndSyncFreshData(userId));
///
///     // Never returns on its own — keeps the channelFlow open,
///     // forwarding every value the watch stream emits (including ones
///     // caused by the write above) for as long as it's subscribed.
///     await database.watchDashboardData(userId).collect(scope.emit);
///   });
/// }
/// ```
///
/// [action] : A function that takes a [ProducerScope<T>] as an argument.
/// It's responsible for emitting values of type `T` (directly, or via
/// [ProducerScope.launch]) into the flow.
Flow<T> channelFlow<T>(FutureOr<void> Function(ProducerScope<T> scope) action) {
  return ChannelFlow<T>(action);
}