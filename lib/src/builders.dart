
import 'dart:async';

import 'collectors/flow_collector.dart';
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