
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow/flow.dart';


main() {

  setUpAll(() {});


  group('FetchOrElseCache', () {
    test('Test that values from primary flow are emitted when it passes', () {
      //Arrange
      final cacheFlow = TestCacheFlow<int>(
          'test_key', fromJson: (value) => int.parse('$value'), toJson: (v) => v);

      final fl = flow((collector) async {
        final primaryFlow = flowOf([2]);
        cacheFlow.write(3);

        const fetchOrElse = FetchOrElseCache();
        await fetchOrElse.handle(cacheFlow, primaryFlow, collector);
      });

      //Act and Assert
      expect(fl.asStream(), emitsInOrder([
        2, emitsDone
      ]));
    });

    test('Test that when the primary flow fails values from cache are emitted', () {
      final cacheFlow = TestCacheFlow<int>(
          'test_key', fromJson: (value) => int.parse('$value'), toJson: (v) => v);

      //Arrange
      final fl = flow((collector) async {
        final primaryFlow = flowOf([2]).map((value) {
          throw Exception('failed');
        });
        cacheFlow.write(3);

        await Future.delayed(const Duration(milliseconds: 5));
        const fetchOrElse = FetchOrElseCache();
        await fetchOrElse.handle(cacheFlow, primaryFlow, collector);
      });

      //Act and Assert
      expect(fl.asStream(), emitsInOrder([
        3, emitsDone
      ]));
    });

    test('Test that when primary doesnt produce values and cache has expired nothing is emitted', () {
      final cacheFlow = TestCacheFlow<int>(
          'test_key', fromJson: (value) => int.parse('$value'), toJson: (v) => v);

      //Arrange
      final fl = flow((collector) async {
        final primaryFlow = flowOf([]);
        cacheFlow.write(3);

        await Future.delayed(const Duration(milliseconds: 5));
        const fetchOrElse = FetchOrElseCache(maxAge: Duration(milliseconds: 0));
        await fetchOrElse.handle(cacheFlow, primaryFlow, collector);
      });

      //Act and Assert
      expect(fl.asStream(), emitsInOrder([
        emitsDone
      ]));
    });

    test('Test that when primary fails and cache has expired the primary error is thrown', () {
      final cacheFlow = TestCacheFlow<int>(
          'test_key', fromJson: (value) => int.parse('$value'), toJson: (v) => v);

      //Arrange
      final fl = flow((collector) async {
        final primaryFlow = flowOf([1]).map(
                (value) => throw Exception('mapError')
        );
        cacheFlow.write(3);

        await Future.delayed(const Duration(milliseconds: 5));
        const fetchOrElse = FetchOrElseCache(maxAge: Duration(milliseconds: 0));
        await fetchOrElse.handle(cacheFlow, primaryFlow, collector);
      });

      //Act and Assert
      expect(fl.asStream(), emitsInOrder([
        emitsError(isInstanceOf<Exception>().having((p0) => p0.toString(), 'exception message', contains('mapError')))
      ]));
    });
  });


  group('CacheOrElseFetch', () {
    test('Test that values from the cache are emitted when it passes', () {
      final cacheFlow = TestCacheFlow<int>(
          'test_key', fromJson: (value) => int.parse('$value'), toJson: (v) => v);

      final originalFlow = flowOf([1]);

      final fl = flow((collector) async {
        cacheFlow.write(4);

        const cacheOrElseFetch = CacheOrElseFetch();
        await cacheOrElseFetch.handle(cacheFlow, originalFlow, collector);
      });

      expect(fl.asStream(), emitsInOrder([
        4, emitsDone
      ]));
    });

    test('Test that when cache is empty or throws error values from the original flow are emitted', () {
      final cacheFlow = TestCacheFlow<int>(
          'test_key', fromJson: (value) => int.parse('$value'), toJson: (v) => v
      );

      final originalFlow = flowOf([1]);
      //Since we are not writing to the cacheFlow it should fail with NullPointer

      final fl = flow((collector) async {
        const cacheOrElseFetch = CacheOrElseFetch();
        await cacheOrElseFetch.handle(cacheFlow, originalFlow, collector);
      });

      expect(fl.asStream(), emitsInOrder([
        1, emitsDone
      ]));
    });

    test('Test that when cache has expired values from the original flow are emitted', () {
      final cacheFlow = TestCacheFlow<int>(
          'test_key', fromJson: (value) => int.parse('$value'), toJson: (v) => v
      );

      final originalFlow = flowOf([1]);
      cacheFlow.write(4);

      final fl = flow((collector) async {
        const cacheOrElseFetch = CacheOrElseFetch(maxAge: Duration(milliseconds: 0));
        await Future.delayed(const Duration(milliseconds: 3));
        await cacheOrElseFetch.handle(cacheFlow, originalFlow, collector);
      });

      expect(fl.asStream(), emitsInOrder([
        1, emitsDone
      ]));
    });

    test('Test that if cache fails and primary fails both errors are propagated', () {
      final cacheFlow = TestCacheFlow<int>(
          'test_key', fromJson: (value) => int.parse('$value'), toJson: (v) => v
      );

      final originalFlow = flowOf([1])
          .map((value) => throw const FormatException('Primary Failed'));

      final fl = flow((collector) async {
        const cacheOrElseFetch = CacheOrElseFetch(maxAge: Duration(milliseconds: 0));
        await cacheOrElseFetch.handle(cacheFlow, originalFlow, collector);
      });

      expect(fl.asStream(), emitsInOrder([
        emitsError(isInstanceOf<CombinedFlowException>())
      ]));
    });
  });

  group('CacheThenFetch', () {
    test('Test that values emitted are only from the cache flow', () {
      final cacheFlow = TestCacheFlow<int>(
          'test_key', fromJson: (value) => int.parse('$value'), toJson: (v) => v
      );

      final originalFlow = flowOf([1]);
      cacheFlow.write(3);

      final fl = flow((collector) async {
        const cacheOrElseFetch = CacheThenFetch();
        await cacheOrElseFetch.handle(cacheFlow, originalFlow, collector);
      });

      expect(fl.asStream(), emitsInOrder([
        3, emitsDone
      ]));
    });

    test('Test that if cache fails the original flow values are persisted', () {
      final cacheFlow = TestCacheFlow<int>(
          'test_key', fromJson: (value) => int.parse('$value'), toJson: (v) => v
      );

      final originalFlow = flowOf([1]);
      // don't write so that catch flow throws an exception

      final fl = flow((collector) async {
        const cacheOrElseFetch = CacheThenFetch();
        await cacheOrElseFetch.handle(cacheFlow, originalFlow, collector);
      });

      expect(fl.asStream(), emitsInOrder([emitsDone]));
      expectLater(
          Future.delayed(const Duration(milliseconds: 100), () => cacheFlow.read()),
          completion(equals(1))
      );
    });
  });

  group('CacheAndFetch', () {
    test('Test that data from both cache flow and the original flow are received in order', () {
      final cacheFlow = TestCacheFlow<int>(
          'test_key',
          fromJson: (value) => int.parse('$value'),
          toJson: (v) => v
      );

      final originalFlow = flowOf([2]);
      cacheFlow.write(1);

      final fl = flow((collector) async {
        const cacheOrElseFetch = CacheAndFetch();
        await cacheOrElseFetch.handle(cacheFlow, originalFlow, collector);
      });

      expect(fl.asStream(), emitsInOrder([1, 2, emitsDone]));
    });

    test('Test that when cache flow and the original flow throws an error the error is propagated downstream', () {
      final cacheFlow = TestCacheFlow<int>(
          'test_key',
          fromJson: (value) => int.parse('ABC'), // ==> this should throw error
          toJson: (v) => v
      );

      final originalFlow = flowOf([2]).map((value) => throw Exception('mapError'));
      cacheFlow.write(1);

      final fl = flow((collector) async {
        const cacheOrElseFetch = CacheAndFetch();
        await cacheOrElseFetch.handle(cacheFlow, originalFlow, collector);
      });

      expect(fl.asStream(), emitsInOrder([
        emitsError(isInstanceOf<CombinedFlowException>())
      ]));
    });
  });
  
  group('CacheOrStaleCacheOnFetchError', () {
    test('Test that stale cache is a fallback on original flow failure', () {
      final cacheFlow = TestCacheFlow<int>('test_key',
          fromJson: (value) => int.parse('$value'),
          toJson: (v) => v
      );

      final originalFlow = flowOf([2]).map((value) => throw Exception('mapError'));
      cacheFlow.write(1);

      final fl = flow((collector) async {
        const staleCache = CacheOrStaleCacheOnFetchError(
            maxAge: Duration(milliseconds: 0)
        );
        await staleCache.handle(cacheFlow, originalFlow, collector);
      });

      expect(fl.asStream(), emitsInOrder([
        1, emitsDone
      ]));
    });
  });
}

class TestCacheFlow<T> extends CacheFlow<T> {
  final sharedPreference = <dynamic, dynamic>{};

  final T Function(Object) fromJson;
  final dynamic Function(T)? toJson;
  final String dataKey;

  TestCacheFlow(this.dataKey, {required this.fromJson, this.toJson});

  String get _modifiedTimeKey => '${dataKey}_last_modified_time';

  @override
  FutureOr<T?> read() {
    final T value = fromJson(sharedPreference[dataKey]);
    return value;
  }

  @override
  Future<void> write(T data) async {
    final jsonValue = toJson?.call(data) ?? jsonEncode(data);
    sharedPreference[dataKey] = jsonValue;
    sharedPreference[_modifiedTimeKey] = DateTime.timestamp()
        .millisecondsSinceEpoch;
  }

  @override
  FutureOr<Duration> cacheAge() {
    final DateTime now = DateTime.now();
    final lastModifiedTime = DateTime
        .fromMillisecondsSinceEpoch(sharedPreference[_modifiedTimeKey]);
    return now.difference(lastModifiedTime);
  }
}