import 'dart:async';

import 'flowimpl.dart';
import 'collectors/flow_collector.dart';
import 'builders.dart';

/// @author Paul Okeke
///
///
/// Extensions on flow
///

extension FlowX<T> on Flow<T> {
  /// Converts this flow into a `Stream<T>`.
  ///
  /// This allows you to use `Stream`-based operators and functionalities
  /// on your flow.
  Stream<T> asStream() => _FlowToStream(this);

  /// Applies a transformation function to each element in the flow.
  ///
  /// This function creates a new flow where each value emitted by the
  /// original flow is transformed using the provided `transform` function.
  /// The transformed value is then emitted in the new flow.
  ///
  /// [transform] : A function that takes a value of type `T` (the input
  /// type of the flow) and returns a value of type `U` (the output type
  /// of the map operation).
  Flow<U> map<U>(U Function(T value) transform) => flow((collector) async {
    await collect((value) => collector.emit(transform(value)));
  });

  /// Applies a transformation function and flattens the resulting streams.
  ///
  /// This function is similar to `map` but allows transforming each element
  /// in the flow into a new flow. The resulting flows are then flattened
  /// into a single stream of values.
  ///
  /// Example:
  /// ```dart
  ///   flowOf([1, 2, 3])
  ///   .flatMap((value) => flowOf([4, 5, 6]))
  ///   .collect(print);
  ///
  /// // Output:
  /// // 4 -> 5 -> 6
  /// ```
  ///
  /// [transform] : A function that takes a value of type `T` (the input type
  /// of the flow) and returns a `Flow<U>` (the output type can be anything
  /// that implements `Flow`).
  Flow<U> flatMap<U>(Flow<U> Function(T value) action) => flow((collector) async {
    final futures = <Future<void>>[];
    await collect((value) async {
      final newFlowFuture = action(value).collect(collector.emit);
      futures.add(Future.value(newFlowFuture));
    });
    await Future.wait(futures);
  });

  /// Handles errors that occur within the flow.
  ///
  /// This function allows you to define an action that will be executed
  /// if an exception is thrown during the flow's processing. The action
  /// receives the exception and the `FlowCollector` as arguments.
  ///
  /// This operator is not triggered when exceptions occurs in the downstream
  /// flow.
  ///
  /// Example:
  /// ```dart
  ///   flow((collector) {
  ///     collector.emit('A');
  ///   })
  ///   .map((event) => throw Exception('computeA'))
  ///   .catchError((error, _) => print('Handled Error from ComputeA'))
  ///   .map((event) => throw Exception('computeB'))
  ///   .collect((event) {}); // Throws an error
  /// ```
  ///
  /// The action block receives a FlowCollector that can be used to emit
  /// values downstream
  ///
  /// Example:
  /// ```dart
  ///   flow<String>((collector) {
  ///     throw Exception();
  ///   }).catchError((error, collector) {
  ///     collector.emit('Ignored the error and emit a message');
  ///   });
  /// ```
  ///
  /// [action] : A function that takes an `Exception` and a `FlowCollector<T>`
  /// as arguments. It can perform error handling or logging within the
  /// context of the flow.
  Flow<T> catchError(
      FutureOr<void> Function(Exception, FlowCollector<T>) action) {
    return flow((collector) async {
      try {
        await collect(collector.emit);
      } catch (e) {
        action.call(e as Exception, collector);
      }
    });
  }

  /// Executes an action before the flow starts collecting data.
  ///
  /// This function allows you to perform setup tasks or initializations
  /// before the actual flow processing begins. The provided `action` function
  /// receives the `FlowCollector` as an argument.
  ///
  /// Example:
  /// ```dart
  ///   flow((collector) => collector.emit('World!'))
  ///   .onStart((collector) => collector.emit('Hello,'));
  ///   .collect(stdout.write)
  ///
  ///   // Outputs:
  ///   // Hello, World!
  /// ```
  ///
  /// [action] : A function that takes a `FlowCollector<T>` as an argument.
  /// It can be used for pre-processing or any actions needed before
  /// collecting data in the flow.
  Flow<T> onStart(FutureOr<void> Function(FlowCollector<T>) action) => flow((collector) async {
    try {
      action(collector);
    } finally  {}
    await collect(collector.emit);
  });

  /// Executes an action upon flow completion (needs improvement).
  ///
  /// This function allows you to perform actions or cleanup tasks after the
  /// flow has finished processing data. The provided `action` function receives
  /// an optional exception (`null` if no exception occurred) and the
  /// `FlowCollector` as arguments.
  ///
  /// **Note:** Currently, the handling of completion errors within the
  /// context of the flow needs improvement.
  ///
  /// [action] : A function that takes an optional `Exception` and a
  /// `FlowCollector<T>` as arguments. It can be used for post-processing,
  /// cleanup, or handling any errors that might occur during completion.
  Flow<T> onCompletion(
      FutureOr<void> Function(Exception?, FlowCollector<T>) action) {
    return flow((collector) async {
      try {
        await collect(collector.emit);
      } catch (e) {
        action(e as Exception, collector);
        rethrow;
      }

      // TODO properly handle completion and ensure that the error within it's context is sent
      try {
        action(null, collector);
      } finally {
        print('<====Completed=====>');
      }
    });
  }

  /// Implements retry logic based on a provided function.
  ///
  /// This function allows you to define a retry strategy for handling
  /// errors within the flow. The provided `action` function takes the
  /// exception and the current attempt number as arguments. It should
  /// return `true` if the flow should be retried and `false` otherwise.
  ///
  /// Example:
  /// ```dart
  ///   flow((collector) {
  ///     collector.emit('A');
  ///     throw Exception('502');
  ///   }).retryWhen((cause, attempts) {
  ///     if (cause.toString().contains('502') && attempts < 2) {
  ///       return true;
  ///     }
  ///     return false;
  ///   }).collect(print);
  /// ```
  ///
  /// [action] : A function that takes an `Exception` and an `int` (the
  /// current attempt number) as arguments. It determines whether to retry
  /// the flow based on the value returned(true|false) by [action]
  Flow<T> retryWhen(FutureOr<bool> Function(Exception, int) action) {
    return flow((collector) async {
      int attempts = 0;
      FutureOr<void> internalRetry() async {
        try {
          await collect(collector.emit);
        } catch (e) {
          if (await action(e as Exception, attempts)) {
            attempts++;
            await internalRetry();
          } else {
            rethrow;
          }
        }
      }
      await internalRetry();
    });
  }
}


extension StreamX<T> on Stream<T> {
  /// TODO document
  Flow<T> asFlow() {
    return flow((collector) async {
      await for (var value in this) {
        collector.emit(value);
      }
    });
  }
}


///
///
/// TODO document
class _FlowToStream<T> extends Stream<T> {
  final Flow<T> _flow;
  StreamSubscription<T>? _subscription;

  late final _testStreamController = StreamController<T>(
    onListen: _onListen,
    onPause: () => _subscription!.pause(),
    onResume: () => _subscription!.resume(),
    onCancel: () => _subscription!.cancel(),
  );

  _FlowToStream(this._flow);

  void _onListen() {
    _flow.catchError((p0, p1) async {
      _testStreamController.addError(p0);
    }).onCompletion((p0, emitter) {
      _testStreamController.close();
    }).collect((value) => _testStreamController.add(value));
  }

  @override
  StreamSubscription<T> listen(void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    _subscription = _testStreamController.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    return _subscription!;
  }
}
