# Flow API

The Flow API provides functionalities for building asynchronous data processing pipelines. It offers a concise and expressive way to chain operations on streams of data.

**Key Features:**

* **Flow Operators:** Extension methods for the `Flow<T>` class, offering functionalities like:

* [map<U>](#map) Applies a transformation function to each element in the flow, resulting in a flow with elements of type `U`.
* [flatMap](#flatmap) Applies a transformation function to each element in the flow, potentially creating new flows. The resulting flows are then flattened into a single stream of values.
* [asStream] (#asStream) Converts this flow into a `Stream<T>`.
* [filter] (#filter)  Handles errors that occur within the flow.
* [catchError] (#catchError)  Handles errors that occur within the flow.
* [onStart](#onstart) Executes an action before the flow starts collecting data.
* [onCompletion](#onCompletion) Executes an action upon flow completion (**needs improvement**).
* [retryWhen] (#retryWhen) Implements retry logic based on a provided function to handle temporary errors.

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

## map<U> {#map}
Applies a transformation function to each element in the flow, resulting in a flow with elements of type `U`.

```dart
final flow = flowOf([1,2,3,4])
  .map((value) => value * 3)
    .collect(print);
 //Output 3,6,9,12
```


## flatMap {#flatmap}
Applies a transformation function and flattens the resulting streams.

This function is similar to `map` but allows transforming each element in the flow into a new flow. The resulting flows are then flattened into a single stream of values.

```dart
flowOf([1, 2, 3])
    .flatMap((value) => flowOf([4, 5, 6]))
    .collect(print);
// Output:
// 4 -> 5 -> 6
```

## asStream {#asStream}
Converts this flow into a `Stream<T>`.

This allows you to use `Stream`-based operators and functionalities on your flow.

 ```dart
     flowOf([1, 2, 3, 4]).asStream()
 ```


## filter {#filter}
Filters elements emitted by the flow based on a provided predicate function.

This function allows you to selectively emit elements from the flow. The provided `action` function takes a single argument, the current  value (`T`) emitted by the flow. 
It should return a `FutureOr<bool>`. If the `action` function returns `true`, the value is emitted by the resulting flow. Otherwise, the value is discarded.
  
 ```dart
     flowOf([1, 2, 3, 4]).filter((value) => value % 2 == 0)
      .collect(print); // This will print only even numbers (2, 4)
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



