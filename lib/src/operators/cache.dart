import 'dart:async';
import 'dart:math';

import 'package:flow/flow.dart';
import 'package:flow/src/collectors/safe_collector.dart';
import 'package:flow/src/exceptions/flow_exception.dart';
import 'package:flow/src/task_pool_executor.dart';
import '../collectors/flow_collector.dart';


/// An abstract interface representing a Flow that supports caching.
abstract class CacheFlow<T> implements Flow<T> {

  final int _invocationId = Random().nextInt(10000000);

  /// Asynchronously collects values from the cache.
  @override
  FutureOr<void> collect(FutureOr<void> Function(T value) collector) async {
    final completer = Completer();
    currentTaskPool()?.registerTask(Task(ExecutionType.signalCollection));
    collectSafely(collector)
        .tryCatch((a) => completer.completeError(a))
        .done(() {
          if (!completer.isCompleted) completer.complete();
        });
    return completer.future;
  }

  /// Writes data to the cache.
  Future<void> write(T data);

  /// Asynchronously reads data from the cache.
  FutureOr<T?> read();

  /// Retrieves the estimated age of the cached data,
  /// indicating how long it has been since the cache was last updated.
  ///
  /// This method calculates the duration since the last modification time
  /// stored in the cache. If no cached data exists, or the last modification
  /// time cannot be retrieved, it returns `Duration.max`.
  ///
  /// Returns:
  ///  A `Duration` object representing the estimated age of the cached data,
  ///  or `Duration(days: 30)` if no cached data exists.
  FutureOr<Duration> cacheAge() => const Duration(days: 30);

  @override
  SafeCollector collectSafely(FutureOr<void> Function(T value) collector, [String? name]) {
    final safeCollector = SafeCollector();
    int id = _invocationId + hashCode;

    void collectAsync() async {
      try {
        currentTaskPool()?.registerTask(
            Task(ExecutionType.signalInvocation, invocationId: id));
        final value = await read();
        if (value != null) {
          collector(value);
        }
      } catch (e) {
        safeCollector.onError(e);
      } finally {
        currentTaskPool()?.registerTask(
            Task(ExecutionType.signalClosure, invocationId: id));
        safeCollector.onDone();
      }
    }

    collectAsync();
    return safeCollector;
  }
}


abstract interface class CacheStrategy<T> {
  /// Defines how to handle cache reads and writes.
  ///
  /// This method takes the following arguments:
  /// [cacheFlow] : A `CacheFlow<T>` instance representing the cache.
  /// [originalFlow] : A `Flow<T>` instance representing the original data source.
  /// [collector] : A `FlowCollector<T>` to emit data to the downstream flow.
  FutureOr<void> handle(CacheFlow<T> cacheFlow, Flow<T> originalFlow, FlowCollector<T> collector);
}

/// A cache strategy that prioritizes fetching fresh data from the primary
/// source (represented by a `Flow`). If fetching encounters errors or the
/// primary source is empty, it attempts to retrieve data from the
/// cache (`CacheFlow`) and emit it downstream.
///
/// This strategy offers two key functionalities:
///
/// 1. **Fallback to Cache:** When fetching fails or the primary source is empty,
/// the cache is consulted to provide data if it's still valid.
///
/// 2. **Cache Update:** If fetching from the primary source is successful,
/// the retrieved data is written back to the cache for future use.
///
/// This approach ensures data freshness by prioritizing the primary source,
/// but also provides resilience by leveraging the cache in case of errors or
/// emptiness.
///
/// However, there are specific error handling behaviors to consider:
///
/// - If the cache is empty or invalid (`cacheAge` exceeds `maxAge`) and the
/// primary source initially fails, the error is propagated downstream.
/// - If the cache is expired (`cacheAge` exceeds `maxAge`) but the primary
/// source is empty, nothing is emitted downstream.
///
/// This strategy is useful for scenarios where up-to-date data is important
/// but fallback to cached data is essential to maintain application responsiveness
/// in case of network issues or primary source unavailability.
class FetchOrElseCache<T> implements CacheStrategy<T> {
  const FetchOrElseCache({this.maxAge = const Duration(days: 30)});

  /// The maximum age allowed for cached data before it is considered expired.
  final Duration maxAge;

  /// Handles the retrieval of data using the cache strategy.
  ///
  /// Parameters:
  /// - [cacheFlow] : The cache flow from which data is read and written.
  /// - [originalFlow] : The original flow representing the source of data.
  /// - [collector] : The collector responsible for emitting data received from
  /// either the cache or the original source.
  ///
  /// Throws:
  /// - [CombinedFlowException] : If both the cache and original flows encounter
  /// errors while retrieving data.
  @override
  FutureOr<void> handle(CacheFlow<T> cacheFlow, Flow<T> originalFlow,
      FlowCollector<T> collector) async {
    final combinedFlowException = CombinedFlowException([]);

    readFromCache([Object? e]) async {
      final cacheAge = await cacheFlow.cacheAge();
      final cacheHasExpired = cacheAge.inMilliseconds > maxAge.inMilliseconds;

      if (cacheHasExpired && null != e) {
        throw combinedFlowException;
      } else if (cacheHasExpired) {
        return;
      }

      await cacheFlow.catchError((cause, _) {
        combinedFlowException.add(cause);
        throw combinedFlowException;
      }).onEmpty((_) {
        if (null != e) throw e;
      }).collect(collector.emit);
    }

    try {
      await originalFlow.onEmpty((_) => readFromCache()).collect((value) async {
        collector.emit(value);
        cacheFlow.write(value);
      });
    } catch (e) {
      combinedFlowException.add(e.toException());
      await readFromCache(e);
    }
  }
}

/// A cache strategy that fetches data from a cache if available, otherwise
/// retrieves it from an original source.
///
/// This cache strategy attempts to read data from a cache first.
/// If the cache does not contain the required data or if the cached data
/// has expired, it falls back to fetching the data from the original source.
/// The fetched data is then stored in the cache for future use.
///
/// The [maxAge] parameter specifies the maximum age allowed for cached data
/// before it is considered expired. By default, data older than 30 days is
/// considered expired.
///
/// Example usage:
///
/// ```dart
/// final cacheStrategy = CacheOrElseFetch<MyData>();
/// await cacheStrategy.handle(cacheFlow, originalFlow, collector);
/// ```
///
/// In the example above, `cacheFlow` represents the cache from which data is
/// read and written, `originalFlow` represents the original source of data, and
/// `collector` is responsible for emitting data received from either the cache
/// or the original source.
class CacheOrElseFetch<T> implements CacheStrategy<T> {
  /// Constructs a [CacheOrElseFetch] with the specified maximum age for cached
  /// data.
  ///
  /// The [maxAge] parameter specifies the maximum age allowed for cached data
  /// before it is considered expired. By default, data older than 30 days is
  /// considered expired.
  const CacheOrElseFetch({this.maxAge = const Duration(days: 30)});

  /// The maximum age allowed for cached data before it is considered expired.
  final Duration maxAge;

  /// Handles the retrieval of data using the cache strategy.
  ///
  /// Parameters:
  /// - [cacheFlow] : The cache flow from which data is read and written.
  /// - [originalFlow] : The original flow representing the source of data.
  /// - [collector] : The collector responsible for emitting data received from
  /// either the cache or the original source.
  ///
  /// Throws:
  /// - [CombinedFlowException] : If both the cache and original flows encounter
  /// errors while retrieving data.
  @override
  FutureOr<void> handle(CacheFlow<T> cacheFlow, Flow<T> originalFlow,
      FlowCollector<T> collector) async {
    final combinedFlowException = CombinedFlowException([]);

    readFromOriginal([Object? e]) async {
      await originalFlow.catchError((cause, _) {
        combinedFlowException.add(cause);
        throw combinedFlowException;
      }).onEmpty((_) {
        if (null != e) throw e;
      }).collect((value) {
        collector.emit(value);
        cacheFlow.write(value);
      });
    }

    if (await cacheFlow.hasExpired(maxAge)) {
      await readFromOriginal();
      return;
    }

    try {
      await cacheFlow
          .onEmpty((_) async => await readFromOriginal())
          .collect(collector.emit);
    } catch (e) {
      combinedFlowException.add(e.toException());
      await readFromOriginal(e);
    }
  }
}


/// A cache strategy that prioritizes retrieving data from the cache (`CacheFlow`).
/// It also then fetches fresh data from the original flow (`Flow`) and persist
/// into the cache for future use.
///
/// This strategy offers the following functionalities:
///
/// 1. **Cache Priority:** It attempts to retrieve data from the cache first,
/// emitting it downstream if available and valid.
///
/// 2. **Fallback to Fetch:** Regardless of if the cache is empty or expired,
/// it fetches data from the original flow and writes the fetched data back
/// to the cache for future use.
///
/// 3. **Combined Error Handling:** It utilizes a `CombinedFlowException` to
/// capture and propagate errors from both the cache flow and the original flow.
/// This exception allows for centralized handling of potential errors
/// encountered during caching or fetching operations.
///
/// This strategy is useful for scenarios where prioritizing cached data for
/// faster response times is important, but fallback to fetching fresh data
/// ensures data consistency and avoids serving stale information.
class CacheThenFetch<T> implements CacheStrategy<T> {
  /// Constructs a [CacheThenFetch] with the specified maximum age for cached data.
  ///
  /// The [maxAge] parameter specifies the maximum age allowed for cached data
  /// before it is considered expired. By default, data older than 30 days is
  /// considered expired.
  const CacheThenFetch({this.maxAge = const Duration(days: 30)});

  /// The maximum age allowed for cached data before it is considered expired.
  final Duration maxAge;

  /// Handles the retrieval of data using the cache strategy.
  ///
  ///
  /// Parameters:
  /// - [cacheFlow] : The cache flow from which data is read and written.
  /// - [originalFlow] : The original flow representing the source of data.
  /// - [collector] : The collector responsible for emitting data received from
  /// either the cache or the original source.
  ///
  /// Throws:
  /// - [CombinedFlowException] : If both the cache and original flows encounter
  /// errors while retrieving data.
  @override
  FutureOr<void> handle(CacheFlow<T> cacheFlow, Flow<T> originalFlow,
      FlowCollector<T> collector) async {
    final combinedFlowException = CombinedFlowException([]);

    try {
      if (!await cacheFlow.hasExpired(maxAge)) {
        await cacheFlow
            .catchError((cause, _) => combinedFlowException.add(cause))
            .collect(collector.emit);
      }
      await originalFlow.collect(cacheFlow.write);
    } catch (e) {
      combinedFlowException.add(e.toException());
      rethrow;
    }
  }
}

/// A cache strategy that attempts to retrieve data concurrently from both the
/// cache (`CacheFlow`) and the original flow (`Flow`).
///
/// This strategy offers the following functionalities:
///
/// 1. **Concurrent Access:** It initiates data retrieval from both the cache and
/// the original flow simultaneously.
/// 2. **Cache Priority:** If the cache holds valid data (not expired based on
/// `maxAge`), it emits the cached data downstream first.
/// 3. **Fallback and Caching:** If the cache is empty or expired, it fetches data
/// from the original flow and writes the fetched data back to the cache
/// for future use.
/// 4. **Combined Error Handling:** It utilizes a `CombinedFlowException` to
/// capture and propagate errors from both the cache flow and the original flow.
/// This exception allows for centralized handling of potential errors
/// encountered during caching or fetching operations.
///
/// This strategy is useful for scenarios where prioritizing cached data for
/// faster response times is important, but concurrent fetching ensures
/// data consistency and avoids waiting for the original flow to complete
/// if cached data is unavailable. However, be aware that this approach
/// might result in duplicate data being emitted downstream if both the cache
/// and the original flow provide data successfully.
class CacheAndFetch<T> implements CacheStrategy<T> {
  /// Constructs a [CacheAndFetch] with the specified maximum age for cached data.
  ///
  /// The [maxAge] parameter specifies the maximum age allowed for cached data
  /// before it is considered expired. By default, data older than 30 days is
  /// considered expired.
  const CacheAndFetch({this.maxAge = const Duration(days: 30)});

  /// The maximum age allowed for cached data before it is considered expired.
  final Duration maxAge;

  /// Handles the retrieval of data using the cache strategy.
  ///
  /// This method simultaneously attempts to retrieve data from both the cache
  /// and the original source. If the cache contains the required data and it
  /// has not expired, the cached data is emitted through the provided
  /// [collector]. Regardless of the cache status, the method also fetches the
  /// data from the original source emits it downstream and stores it in the
  /// cache for future use.
  ///
  /// Parameters:
  /// - [cacheFlow] : The cache flow from which data is read and written.
  /// - [originalFlow] : The original flow representing the source of data.
  /// - [collector] : The collector responsible for emitting data received from
  /// either the cache or the original source.
  ///
  /// Throws:
  /// - Any error encountered during the retrieval of data from either the cache
  /// or the original source.
  @override
  FutureOr<void> handle(CacheFlow<T> cacheFlow, Flow<T> originalFlow,
      FlowCollector<T> collector) async {
    final combinedFlowException = CombinedFlowException([]);

    try {
      if (!await cacheFlow.hasExpired(maxAge)) {
        await cacheFlow
            .catchError((cause, _) => combinedFlowException.add(cause))
            .collect(collector.emit);
      }

      await originalFlow.collect((value) async {
        collector.emit(value);
        await cacheFlow.write(value);
      });
    } catch (e) {
      combinedFlowException.add(e.toException());
      throw combinedFlowException;
    }
  }
}


/// A cache strategy that prioritizes fetching data from the cache (`CacheFlow`).
/// If the cache is empty or the data is expired (`maxAge` exceeded), it attempts
/// to fetch fresh data from the original flow (`Flow`). However, unlike
/// [CacheThenFetch], if fetching from the original flow encounters an error,
/// this strategy will still emit the potentially stale data from the cache
/// as a fallback.
///
/// This strategy offers the following functionalities:
///
/// 1. **Cache Priority:** It attempts to retrieve data from the cache first.
/// 2. **Fallback to Fetch (with Error Handling):** If the cache is empty or
/// expired, it fetches data from the original flow. However, if fetching fails,
/// it attempts to recover by emitting the cached data (even if stale) instead of
/// propagating the error.
/// 3. **Combined Error Handling (Conditional):** It utilizes a
/// `CombinedFlowException` to capture and propagate errors. However, it
/// conditionally handles errors from fetching: if fetching is the only failing
/// source (indicated by a single error in the exception), it emits the cached
/// data and swallows the error. Otherwise, it rethrows the exception for
/// further handling.
///
/// This strategy can be useful for scenarios where prioritizing cached data
/// for faster response times and maintaining some level of functionality is
/// important, even if the data might be outdated. However, be aware that this
/// approach can lead to serving stale data if the fetch operation fails.
/// Consider using a monitoring mechanism to track the frequency of such
/// occurrences and potentially trigger cache updates as needed.
class CacheOrStaleCacheOnFetchError<T> implements CacheStrategy<T> {
  /// Constructs a [CacheOrStaleCacheOnFetchError] with the specified maximum
  /// age for cached data.
  ///
  /// The [maxAge] parameter specifies the maximum age allowed for cached data
  /// before it is considered expired. By default, data older than 30 days is
  /// considered expired.
  const CacheOrStaleCacheOnFetchError({this.maxAge = const Duration(days: 30)});

  /// The maximum age allowed for cached data before it is considered expired.
  final Duration maxAge;

  @override
  FutureOr<void> handle(CacheFlow<T> cacheFlow, Flow<T> originalFlow,
      FlowCollector<T> collector) async {
    try {
      // Use CacheOrElseFetch to handle the cache retrieval and fallback to
      // fetching from the original source if necessary
      final cacheOrElseFetch = CacheOrElseFetch(maxAge: maxAge);
      await cacheOrElseFetch.handle(cacheFlow, originalFlow, collector);
    } catch (e) {
      // If an error occurred during fetch, check if it's the only error
      // in the CombinedFlowException. If so, use the stale cache data
      if (e is CombinedFlowException && e.errors.length == 1) {
        // Collect from the cache regardless of its staleness
        await cacheFlow.collect(collector.emit);
        return;
      }
      // Re-throw the error if it's related to cache retrieval
      rethrow;
    }
  }
}



extension _CacheFlowX<T> on CacheFlow<T> {
  Future<bool> hasExpired(Duration maxAge) async {
    try {
      final cacheAge = await this.cacheAge();
      final cacheHasExpired = cacheAge.inMilliseconds > maxAge.inMilliseconds;
      return cacheHasExpired;
    } catch (e) {
      return true;
    }
  }
}
