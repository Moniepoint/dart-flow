import 'dart:async';

import 'package:flow/src/collectors/safe_collector.dart';
import 'package:flow/src/operators/cache.dart';
import 'package:flow/src/exceptions/flow_exception.dart';
import 'package:flow/src/operators/timeout.dart';
import 'package:flow/src/retries.dart';
import 'package:flow/src/operators/distinct.dart';

import 'flowimpl.dart';
import 'collectors/flow_collector.dart';
import 'builders.dart';

/// @author Paul Okeke
///
///
/// Extensions on flow
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
  Flow<U> map<U>(FutureOr<U> Function(T value) transform) {
    return flow((collector) async {
      collectSafely((value) async => collector.emit(await transform(value)))
          .collectWith(collector);
    });
  }

  /// Applies a transformation function and flattens the resulting streams.
  ///
  /// This function is similar to `map` but allows transforming each element
  /// in the flow into a new flow. The resulting flows are then flattened
  /// into a single stream of values.
  ///
  /// Example:
  /// ```dart
  ///   flowOf([1, 2, 3])
  ///     .flatMap((value) => flowOf([4, 5, 6]))
  ///     .collect(print);
  ///
  /// // Output:
  /// // 4 -> 5 -> 6
  /// ```
  ///
  /// [transform] : A function that takes a value of type `T` (the input type
  /// of the flow) and returns a `Flow<U>` (the output type can be anything
  /// that implements `Flow`).
  Flow<U> flatMap<U>(Flow<U> Function(T value) action) => flow((collector) async {
    collectSafely((value) async {
      action(value).collectSafely(collector.emit).collectWith(collector);
    }).collectWith(collector).done(() {});
  });

  /// Filters elements emitted by the flow based on a provided predicate function.
  ///
  /// This function allows you to selectively emit elements from the flow.
  /// The provided `action` function takes a single argument, the current
  /// value (`T`) emitted by the flow. It should return a `FutureOr<bool>`. If
  /// the `action` function returns `true`, the value is emitted by the resulting
  /// flow. Otherwise, the value is discarded.
  ///
  /// Example:
  /// ```dart
  ///   flow([1, 2, 3, 4]).filter((value) => value % 2 == 0)
  ///     .collect(print); // This will print only even numbers (2, 4)
  /// ```
  ///
  /// [action]: A function that takes a value of type `T` emitted by the flow
  /// as an argument. It should return a `FutureOr<bool>`. If the function
  /// returns `true`, the value is emitted by the resulting flow. Otherwise,
  /// the value is discarded.
  Flow<T> filter(FutureOr<bool> Function(T value) action) => flow((collector) async {
    collectSafely((value) async {
      if (await action(value)) collector.emit(value);
    }).collectWith(collector);
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
    return flow<T>((collector) async {
      collectSafely(collector.emit).collectWith(collector).tryCatch((e) async {
        try {
          await action(e, collector);
        } catch (e) {
          collector.addError(e);
        }
      });
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
  ///     .onStart((collector) => collector.emit('Hello,'));
  ///     .collect(stdout.write)
  ///
  ///   // Outputs:
  ///   // Hello, World!
  /// ```
  ///
  /// [action] : A function that takes a `FlowCollector<T>` as an argument.
  /// It can be used for pre-processing or any actions needed before
  /// collecting data in the flow.
  Flow<T> onStart(FutureOr<void> Function(FlowCollector<T>) action) => flow((collector) async {
    try { await action(collector); } catch(e) { collector.addError(e); }
    collectSafely(collector.emit).collectWith(collector);
  });

  /// Returns a flow that invokes the given [action] before each value of the
  /// upstream flow is emitted downstream.
  ///
  /// This function allows you to perform actions on each individual value that
  /// flows through the pipeline, potentially performing side effects before
  /// the value is sent further downstream.
  ///
  /// Example:
  /// ```dart
  ///  flow((collector) => collector.emit(1, 2, 3))
  ///    .onEach((value) => print('Emitting value: $value'))
  ///    .collect(print);
  ///
  ///  // Output:
  ///  // Emitting value: 1
  ///  // 1
  ///  // Emitting value: 2
  ///  // 2
  ///  // Emitting value: 3
  ///  // 3
  /// ```
  ///
  /// [action] : A function that takes a value of type `T` and potentially
  /// performs asynchronous operations. This function is called for each value
  /// emitted by the source Flow.
  Flow<T> onEach(FutureOr<void> Function(T value) action) => flow((collector) {
    collectSafely((value) async {
      try {
        await action(value);
        collector.emit(value);
      } catch (e) {
        collector.addError(e);
      }
    }).collectWith(collector);
  });


  /// A Function that returns a flow where all subsequent repetitions of the
  /// same value are filtered out.
  /// ```dart
  /// flow<DummyClass>((collector) {
  ///   collector.emit(DummyClass(foo: 1));
  ///   collector.emit(DummyClass(foo: 2));
  ///   collector.emit(DummyClass(foo: 3));
  ///   collector.emit(DummyClass(foo: 2));
  ///   collector.emit(DummyClass(foo: 4));
  /// })
  /// .distinctUntilChanged(
  ///   keySelector: (value) => value.foo,
  ///   areEquivalent: (previousKey, nextKey) => (previousKey ?? 0) > nextKey!,
  /// )
  /// .collect((value) => print(value.foo));
  /// ```
  /// Output: 1,2,3,4
  Flow<T> distinctUntilChanged({bool Function(T? previousKey, T? nextKey)? areEquivalent}) =>
      Distinct(upstreamFlow: this, equivalenceMethod: areEquivalent).call();

  /// A Function  that returns a flow where all subsequent repetitions of the
  /// same value are filtered out.
  /// ```dart
  ///  flow<DummyClass>((collector) {
  ///    collector.emit(DummyClass(foo: 21));
  ///    collector.emit(DummyClass(foo: 25));
  ///    collector.emit(DummyClass(foo: 22));
  ///    collector.emit(DummyClass(foo: 22));
  ///  })
  ///  .distinctUntilChangedBy(
  ///   (value) => value.foo,
  ///  )
  ///  .collect((value) => print(value.foo));
  /// ```
  /// Output: 21,25,22
  Flow<T> distinctUntilChangedBy<K>(K Function(T value) keySelector) =>
      Distinct(upstreamFlow: this, keySelector: keySelector).call();

  /// Creates a new flow that executes the provided action ([action]) only
  /// if the original flow emits no events (i.e., is empty).
  ///
  /// This function is useful for scenarios where you want to perform
  /// specific logic when a flow is empty. For example, you might want to
  /// emit a default value, fetch data from another source, or trigger
  /// some side effect when no data is available in the original flow.
  ///
  /// Example:
  /// ```dart
  /// Flow<int> numbers = Flow.from([1, 2, 3]);
  ///
  /// // This action will NOT be executed because the original flow is not empty
  /// Flow<int> withEmptyHandling = numbers
  ///   .onEmpty((collector) => collector.emit(0));
  ///
  /// withEmptyHandling.collect(print); // Output: 1, 2, 3
  ///
  /// Flow<String> emptyStringFlow = Flow.empty();
  ///
  /// // This action WILL be executed because the original flow is empty
  /// Flow<String> withEmptyAction = emptyStringFlow
  ///   .onEmpty((collector) => collector.emit("No data available"));
  ///
  /// withEmptyAction.collect(print); // Output: No data available
  /// ```
  ///
  /// [action] : A function that accepts a `FlowCollector<T>` as its parameter.
  /// The provided action will be executed only if the original flow doesn't
  /// emit any values. Otherwise, the original flow's events are simply forwarded
  /// downstream without any modification.
  Flow<T> onEmpty(FutureOr<void> Function(FlowCollector<T>) action) {
    return flow((collector) async {
      bool isEmpty = true;
      collectSafely((value) {
        isEmpty = false;
        collector.emit(value);
      }).collectWith(collector).tryCatch((e) {
        isEmpty = false;
        collector.addError(e);
      }).done(() async {
        if (isEmpty) {
          await action.call(collector);
        }
        collector.close();
      });
    });
  }


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
      collectSafely(collector.emit).collectWith(collector).done(() {
        try {
          action(null, collector);
          collector.close();
        } finally {
        }
      });
    });
  }

  /// Extends a flow with a timeout mechanism.
  ///
  /// This function creates a new `Timeout` flow that wraps the provided
  /// `upstreamFlow`.
  /// If the upstream flow execution doesn't complete within the specified
  /// `duration`, a `TimeoutCancellationException` will be thrown.
  ///
  /// Example:
  /// ```dart
  /// flow((collector) async {
  ///   await Future.delayed(const Duration(seconds: 5));
  ///   collector.emit('A');
  /// })
  /// .timeout(const Duration(seconds: 3))
  /// .collect(print);
  ///
  /// // Output:
  /// //  throws a TimeoutCancellationException
  ///
  /// flow((collector) async {
  ///   collector.emit('A');
  ///   await Future.delayed(const Duration(milliseconds: 100));
  ///   collector.emit('B');
  ///   await Future.delayed(const Duration(milliseconds: 100));
  ///   collector.emit('C');
  ///   await Future.delayed(const Duration(milliseconds: 1000));
  ///   collector.emit('D');
  /// })
  /// .timeout(const Duration(milliseconds: 99))
  /// .catchError((cause, collector) {
  ///   if (cause is TimeoutCancellationException) {
  ///     collector.emit('Z');
  ///   } else {
  ///     throw cause;
  ///   }
  /// })
  /// .onEach(() {
  ///   await Future.delayed(const Duration(milliseconds: 300)); // this doesn't matter
  /// });
  ///
  /// //Output:
  /// // A, B, C, Z
  /// ```
  ///
  /// [duration] : The maximum allowed execution time for the upstream flow.
  ///
  /// Returns:
  ///   * A new `Flow<T>` object that incorporates the timeout functionality.
  Flow<T> timeout(Duration duration) => Timeout(this, duration);

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
          if (await action(e.toException(), attempts)) {
            attempts++;
            await internalRetry();
          } else {
            collector.addError(e);
          }
        }
        collector.close();
      }
      await internalRetry();
    });
  }

  /// Implements retry logic based on a provided [RetryPolicy].
  ///
  /// This approach offers more flexibility by allowing you to define a custom
  /// retry policy class that encapsulates various retry strategies. The
  /// provided `action` function takes the encountered exception as an argument
  /// and should return a concrete implementation of the `RetryPolicy` interface.
  /// This policy object then dictates the retry behavior based on factors like
  /// the number of attempts, elapsed time, or specific error types.
  ///
  /// Example:
  /// ```dart
  ///   class ExponentialRetryPolicy implements RetryPolicy {
  ///     // ... implementation details
  ///   }
  ///
  ///   flow((collector) {
  ///     collector.emit('A');
  ///     throw Exception('Something went wrong');
  ///   }).retryWith((cause) => ExponentialRetryPolicy())
  ///     .collect(print);
  /// ```
  ///
  /// [action] : A function that takes an `Exception` as an argument. It
  /// should return a concrete implementation of the `RetryPolicy` interface,
  /// defining the retry strategy for the flow in case of errors.
  Flow<T> retryWith(RetryPolicy Function(Exception cause) action) {
    RetryPolicy? retryPolicy;
    Exception? previousException;
    return this.retryWhen((cause, attempts) async {
      if (null != retryPolicy && previousException.isIdenticalWith(cause)) {
        return await retryPolicy?.retry(attempts) ?? false;
      } else {
        retryPolicy = action(cause);
        previousException = cause;
        return await retryPolicy?.retry(attempts) ?? false;
      }
    });
  }

  /// Creates a new Flow that applies a caching strategy using the provided
  /// `CacheFlow` and `CacheStrategy` objects.
  ///
  /// This function allows you to integrate caching logic into your data flows.
  /// It takes a `CacheFlow` object that defines the caching behavior
  /// (e.g., reading, writing from cache), a `CacheStrategy` object that
  /// determines the specific caching strategy to employ
  /// (e.g., `FetchOrElseCache`, `CacheThenFetch`), and a `FlowCollector` to
  /// emit data downstream.
  ///
  /// The provided `CacheStrategy` handles the interaction between the source
  /// Flow (`this` in the context of the function) and the `CacheFlow` to
  /// implement the desired caching behavior.
  ///
  /// Example:
  ///
  /// ```dart
  /// // Example CacheFlow implementation (simplified)
  /// class InMemoryCache<T> implements CacheFlow<T> {
  ///   // ... cache implementation details
  /// }
  ///
  /// // Example CacheStrategy implementation (simplified)
  /// class FetchOrElseCache<T> implements CacheStrategy<T> {
  ///   @override
  ///   FutureOr<void> handle(CacheFlow<T> cacheFlow, Flow<T> sourceFlow,
  ///             FlowCollector collector) async {
  ///     // ... implementation to fetch or read from cache
  ///   }
  /// }
  ///
  /// // Usage
  /// flowOf([1, 2, 3])
  ///   .cache(InMemoryCache<int>(), FetchOrElseCache<int>())
  ///   .collect(print);
  /// ```
  ///
  /// [cacheFlow] : An object implementing the `CacheFlow` interface that
  /// provides caching functionalities (read, write, etc.).
  /// [strategy] : An object implementing the `CacheStrategy` interface that
  /// defines the specific caching strategy to be used with the `CacheFlow`.
  ///
  /// Returns:
  ///  A new Flow that incorporates the caching logic defined by the provided
  ///  `CacheStrategy` and `CacheFlow` objects.
  Flow<T> cache(CacheFlow<T> cacheFlow, CacheStrategy<T> strategy) {
    return flow((collector) async {
      await strategy.handle(cacheFlow, this, collector);
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

  void _onListen() async {
    await _flow.catchError((p0, p1) async {
      _testStreamController.addError(p0);
    }).onCompletion((p0, emitter) {
      _testStreamController.close();
    }).collect((value) {
      _testStreamController.add(value);
    });
  }

  @override
  StreamSubscription<T> listen(void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    _subscription = _testStreamController.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    return _subscription!;
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