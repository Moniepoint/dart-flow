# Flow API

The Flow API provides functionalities for building asynchronous data processing pipelines. It offers a concise and expressive way to chain operations on streams of data.

**Key Features:**

**Flow Operators:** Extension methods for the `Flow<T>` class, offering functionalities like:

* [map<U>](#map) Applies a transformation function to each element in the flow, resulting in a flow with elements of type `U`.
* [flatMap](#flatmap) Applies a transformation function to each element in the flow, potentially creating new flows. The resulting flows are then flattened into a single stream of values.
* [asStream](#asStream) Converts this flow into a `Stream<T>`.
* [filter](#filter)  Filters elements emitted by the flow based on a provided predicate function.
* [cache](#cache) Creates a new Flow that applies a caching strategy using the provided ```CacheFlow``` and ```CacheStrategy``` objects.
* [catchError](#catchError)  Handles errors that occur within the flow.
* [onStart](#onstart) Executes an action before the flow starts collecting data.
* [onCompletion](#onCompletion) Executes an action upon flow completion (**needs improvement**).
* [retryWhen](#retryWhen) Implements retry logic based on a provided function to handle temporary errors.
* [retryWith](#retryWith) Implements retry logic based on a provided [RetryPolicy].
* [onEach](#onEach) Returns a flow that invokes the given [action] before each value of theupstream flow is emitted downstream.
* [onEmpty](#onEmpty) Creates a new flow that executes the provided action ([action]) only if the original flow emits no events (i.e., is empty).
* [distinctUntilChanged](#distinctUntilChanged)A Function that returns a flow where all subsequent repetitions of the same value are filtered out



**Getting Started:**

1. Install the Flow package:
   ```bash
   pub add flow
   ```

2. Import the Flow library in your Dart code:
   ```dart
   import 'package:flow/flow.dart';
   ```

## Creating a flow

To create flows, use the flow builder APIs. The flow builder function creates a new flow where you can manually emit new values into the stream of data using the flow collector emit function.

```dart
flow<String>((collector) async {
  collector.emit('Flow API');
})

```
Create a Flow from an iterable collection of elements.
```dart
flowOf([1, 2, 3, 4])
  .map<String>((number) => (number * 2).toString())
  .catchError((error, collector) => print("Error: $error"))
  .collect(print); // Prints: 2, 4, 6, 8
```

## Flow Operators

## map<U>
Applies a transformation function to each element in the flow, resulting in a flow with elements of type `U`.

```dart
final flow = flowOf([1,2,3,4])
  .map((value) => value * 3)
    .collect(print);
 //Output 3,6,9,12
```


## flatMap
Applies a transformation function and flattens the resulting streams.

This function is similar to `map` but allows transforming each element in the flow into a new flow. The resulting flows are then flattened into a single stream of values.

```dart
flowOf([1, 2, 3])
    .flatMap((value) => flowOf([4, 5, 6]))
    .collect(print);
// Output:
// 4 -> 5 -> 6
```

## asStream
Converts this flow into a `Stream<T>`.

This allows you to use `Stream`-based operators and functionalities on your flow.

 ```dart
     flowOf([1, 2, 3, 4]).asStream()
 ```


## filter
Filters elements emitted by the flow based on a provided predicate function.

This function allows you to selectively emit elements from the flow. The provided `action` function takes a single argument, the current  value (`T`) emitted by the flow. 
It should return a `FutureOr<bool>`. If the `action` function returns `true`, the value is emitted by the resulting flow. Otherwise, the value is discarded.
  
 ```dart
     flowOf([1, 2, 3, 4]).filter((value) => value % 2 == 0)
      .collect(print); // This will print only even numbers (2, 4)
  ```

## cache
Creates a new Flow that applies a caching strategy using the provided `CacheFlow` and `CacheStrategy`  objects.

This function allows you to integrate caching logic into your data flows. It takes a `CacheFlow` object that defines the caching behavior (e.g., reading, writing from cache), a `CacheStrategy` object that determines the specific caching strategy to employ (e.g., `FetchOrElseCache`, `CacheThenFetch`), and a `FlowCollector` to emit data downstream.

The provided `CacheStrategy` handles the interaction between the source Flow (`this` in the context of the function) and the `CacheFlow` toimplement the desired caching behavior.


 ```dart
  // Example CacheFlow implementation (simplified)
   class InMemoryCache<T> implements CacheFlow<T> {
    // ... cache implementation details
  }
 
  // Example CacheStrategy implementation (simplified)
  class FetchOrElseCache<T> implements CacheStrategy<T> {
    @override
    FutureOr<void> handle(CacheFlow<T> cacheFlow, Flow<T> sourceFlow,
              FlowCollector collector) async {
      // ... implementation to fetch or read from cache
    }
  }

  // Usage
  flowOf([1, 2, 3])
    .cache(InMemoryCache<int>(), FetchOrElseCache<int>())
    .collect(print);
  ```

[cacheFlow] : An object implementing the `CacheFlow` interface that provides caching functionalities (read, write, etc.)

[strategy] : An object implementing the `CacheStrategy` interface that defines the specific caching strategy to be used with the `CacheFlow`.
  
Returns: A new Flow that incorporates the caching logic defined by the provided `CacheStrategy` and `CacheFlow` objects.

## retryWhen
Implements retry logic based on a provided function.

This function allows you to define a retry strategy for handling errors within the flow. The provided `action` function takes the exception and the current attempt number as arguments. It should return `true` if the flow should be retried and `false` otherwise.

 ```dart
   flow((collector) {
     collector.emit('A');
     throw Exception('502');
   }).retryWhen((cause, attempts) {
     if (cause.toString().contains('502') && attempts < 2) {
       return true;
     }
     return false;
   }).collect(print);
 ```

 [action] : A function that takes an `Exception` and an `int` (the current attempt number) as arguments. It determines whether to retry the flow based on the value returned(true|false) by [action]

## retryWith
Implements retry logic based on a provided [RetryPolicy].
  
This approach offers more flexibility by allowing you to define a custom retry policy class that encapsulates various retry strategies. The provided `action` function takes the encountered exception as an argument and should return a concrete implementation of the `RetryPolicy` interface. This policy object then dictates the retry behavior based on factors like the number of attempts, elapsed time, or specific error types.
  

   ```dart
     flow((collector) {
       collector.emit('A');
       throw Exception('Something went wrong');
     }).retryWith((cause) =>  RetryPolicy.exponentialBackOff())
       .collect(print);
   ```
  
  [action] : A function that takes an `Exception` as an argument. It should return a concrete implementation of the `RetryPolicy` interface, defining the retry strategy for the flow in case of errors.

  ### At the moment, dart-flow supports 7 different retryPolcies, which are

  1. ExponentialBackOffRetryPolicy
  2. CircuitBreakerRetryPolicy
  3. FixedIntervalRetryPolicy
  4. DecorrelatedJitterRetryPolicy
  5. LinearBackoffRetryPolicy
  6. RandomisedBackoffRetryPolicy
  7. NoRetryPolicy

  ### ExponentialBackOffRetryPolicy

  The ExponentialBackOff retry policy mitigates transient failures by strategically increasing the delay between retry attempts. This approach helps in managing system load and improving the chances of subsequent attempts succeeding.
  [Read More](https://www.baeldung.com/resilience4j-backoff-jitter)

  ```dart
     flow((collector) {
       collector.emit('A');
       throw Exception('Something went wrong');
     }).retryWith((cause) =>  RetryPolicy.exponentialBackOff())
       .collect(print);
   ```

 ### CircuitBreakerRetryPolicy

 The CircuitBreakerRetryPolicy prevents flow from performing operations that are likely to fail. If failures reach a certain threshold, the circuit breaker trips, and further attempts are blocked for a configured time period. After the timeout expires, the circuit breaker allows a limited number of test requests to pass through. If these are successful, normal operation is resumed.
 [Read More](https://dantt.medium.com/circuit-breaker-and-retry-64830e71d0f6)

  ```dart
     flow((collector) {
       collector.emit('A');
       throw Exception('Something went wrong');
     }).retryWith((cause) =>  RetryPolicy.circuitBreaker())
       .collect(print);
   ```

 ### FixedIntervalRetryPolicy

 This policy retries tasks at fixed intervals, regardless of the number of attempts made. It is simple and predictable, making it suitable for situations where the expected time for the issue to be resolved is known.

  ```dart
     flow((collector) {
       collector.emit('A');
       throw Exception('Something went wrong');
     }).retryWith((cause) =>  RetryPolicy.fixedInterval())
       .collect(print);
   ```

 ### DecorrelatedJitterRetryPolicy

 The DecorrelatedJitterRetryPolicy adds a randomized delay between retries to prevent thundering herd problems, which can occur when many clients retry a failed request simultaneously. This approach combines both random and fixed delay strategies to provide a balance between retrying quickly and avoiding overwhelming the server or resource.
 [Read More](https://www.baeldung.com/resilience4j-backoff-jitter)


  ```dart
     flow((collector) {
       collector.emit('A');
       throw Exception('Something went wrong');
     }).retryWith((cause) =>  RetryPolicy.decorrelatedJitter())
       .collect(print);
   ```

 ### LinearBackoffRetryPolicy

 The LinearBackOff retry policy increases the delay between retry attempts by a fixed increment. Unlike exponential backoff, which doubles the delay with each attempt, linear backoff provides a constant increase in the retry interval. This approach is straightforward and predictable, making it suitable for scenarios where a steady progression in retry attempts is preferred.

  ```dart
     flow((collector) {
       collector.emit('A');
       throw Exception('Something went wrong');
     }).retryWith((cause) =>  RetryPolicy.linearBackoff())
       .collect(print);
   ```
  
  ### LinearBackoffRetryPolicy

 The LinearBackOff retry policy increases the delay between retry attempts by a fixed increment. Unlike exponential backoff, which doubles the delay with each attempt, linear backoff provides a constant increase in the retry interval. This approach is straightforward and predictable, making it suitable for scenarios where a steady progression in retry attempts is preferred.

  ```dart
     flow((collector) {
       collector.emit('A');
       throw Exception('Something went wrong');
     }).retryWith((cause) =>  RetryPolicy.linearBackoff())
       .collect(print);
   ```
  
 ### NoRetryPolicy

 As the name suggests, the NoRetryPolicy implements the retry interface but does not attempt retries. It is useful as a default policy or in situations where retries are not desired.

  ```dart
     flow((collector) {
       collector.emit('A');
       throw Exception('Something went wrong');
     }).retryWith((cause) =>  RetryPolicy.noRetry())
       .collect(print);
   ```

### Implementing Custom Retry Policies

To create your custom retry policy, implement the RetryPolicy interface and override the retry method. Your implementation should define the logic to determine if a retry should occur based on the number of [attempts] already made and the nature of the failure.

```dart
class MyCustomRetryPolicy implements RetryPolicy {
  @override
  FutureOr<bool> retry(int attempt) {
    // Implement your custom retry logic here
    // Return true to retry, false to not retry
    if (attempt < 3) {
      return true; // Retry on specific error up to 3 times
    }
    return false; // Do not retry for other errors or after 3 attempts
  }
}

```




## onCompletion
Executes an action upon flow completion (needs improvement).

This function allows you to perform actions or cleanup tasks after the flow has finished processing data. The provided `action` function receives an optional exception (`null` if no exception occurred) and the `FlowCollector` as arguments. **Note:** Currently, the handling of completion errors within the context of the flow needs improvement.

  ```dart
  flowOf([1, 2, 3]).onCompletion((exception, collector){
        //Perform  action
    });
  ```

[action] : A function that takes an optional `Exception` and a  `FlowCollector<T>` as arguments. It can be used for post-processing, cleanup, or handling any errors that might occur during completion.

## onStart
Executes an action before the flow starts collecting data.

This function allows you to perform setup tasks or initializations before the actual flow processing begins. The provided `action` function receives the `FlowCollector` as an argument.

 ```dart
   flow((collector) => collector.emit('World!'))
     .onStart((collector) => collector.emit('Hello,'));
     .collect(stdout.write)

   // Outputs:
   // Hello, World!
 ```

[action] : A function that takes a `FlowCollector<T>` as an argument. It can be used for pre-processing or any actions needed before collecting data in the flow.

## onEach
Returns a flow that invokes the given [action] before each value of the upstream flow is emitted downstream.
  
This function allows you to perform actions on each individual value that flows through the pipeline, potentially performing side effects before the value is sent further downstream.
  
   ```dart
    flowOf([1, 2, 3])
    .onEach((value) => print('Emitting value: $value'))
      .collect(print);
      
    // Output:
    // Emitting value: 1
    // 1
    // Emitting value: 2
    // 2
    // Emitting value: 3
    // 3
   ```

[action] : A function that takes a value of type `T` and potentially performs asynchronous operations. This function is called for each value emitted by the source Flow.

## onEmpty
Creates a new flow that executes the provided action ([action]) only if the original flow emits no events (i.e., is empty).

This function is useful for scenarios where you want to perform specific logic when a flow is empty. For example, you might want to emit a default value, fetch data from another source, or trigger some side effect when no data is available in the original flow.


```dart
 Flow<int> numbers = Flow.from([1, 2, 3]);

 // This action will NOT be executed because the original flow is not empty
 Flow<int> withEmptyHandling = numbers
   .onEmpty((collector) => collector.emit(0));

 withEmptyHandling.collect(print); // Output: 1, 2, 3

 Flow<String> emptyStringFlow = Flow.empty();

 // This action WILL be executed because the original flow is empty
 Flow<String> withEmptyAction = emptyStringFlow
   .onEmpty((collector) => collector.emit("No data available"));

 withEmptyAction.collect(print); // Output: No data available
 ```
[action] : A function that accepts a `FlowCollector<T>` as its parameter. The provided action will be executed only if the original flow doesn't emit any values. Otherwise, the original flow's events are simply forwarded downstream without any modification.


## distinctUntilChanged
A Function that returns a flow where all subsequent repetitions of the same value are filtered out.
   
   ```dart
   flow<DummyClass>((collector) {
     collector.emit(DummyClass(foo: 1));
     collector.emit(DummyClass(foo: 2));
     collector.emit(DummyClass(foo: 3));
     collector.emit(DummyClass(foo: 2));
     collector.emit(DummyClass(foo: 4));
   })
   .distinctUntilChanged(
     keySelector: (value) => value.foo,
     areEquivalent: (previousKey, nextKey) => (previousKey ?? 0) > nextKey!,
   )
   .collect((value) => print(value.foo));
  // Output: 1,2,3,4
   ```

## distinctUntilChanged
A Function  that returns a flow where all subsequent repetitions of the same value are filtered out.


```dart
 flow<DummyClass>((collector) {
   collector.emit(DummyClass(foo: 21));
   collector.emit(DummyClass(foo: 25));
   collector.emit(DummyClass(foo: 22));
   collector.emit(DummyClass(foo: 22));
 })
 .distinctUntilChangedBy(
  (value) => value.foo,
 )
 .collect((value) => print(value.foo));
 ///Output: 21,25,22

```


**Benefits:**

* **Asynchronous Processing:** Efficiently handles streams of data with asynchronous operations.
* **Concise Syntax:** Provides a readable and easy-to-use API for building data pipelines.
* **Composable Operators:** Allows chaining various operations together for complex data processing workflows.



**Further Documentation:**

##### TODO

**Contributing:**

We welcome contributions to the Flow API. Please refer to the CONTRIBUTING.md file for guidelines.

License
=======

Copyright 2024 Moniepoint, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.



