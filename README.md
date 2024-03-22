**## Flow API**

The Flow API provides functionalities for building asynchronous data processing pipelines. It offers a concise and expressive way to chain operations on streams of data.

**Key Features:**

* **Flow Operators:** Extension methods for the `Flow<T>` class, offering functionalities like:
    * `map<U>`: Applies a transformation function to each element in the flow, resulting in a flow with elements of type `U`.
    * `flatMap`: Applies a transformation function to each element in the flow, potentially creating new flows. The resulting flows are then flattened into a single stream of values.
    * `catchError`: Handles errors that occur within the flow.
    * `onStart`: Executes an action before the flow starts collecting data.
    * `onCompletion`: Executes an action upon flow completion (**needs improvement**).
    * `retryWhen`: Implements retry logic based on a provided function to handle temporary errors.

* **Flow Creation Functions:**
    * `flow`: Creates a new Flow with a provided action for data emission.
    * `flowOf`: Creates a Flow from an iterable collection of elements.

**Benefits:**

* **Asynchronous Processing:** Efficiently handles streams of data with asynchronous operations.
* **Concise Syntax:** Provides a readable and easy-to-use API for building data pipelines.
* **Composable Operators:** Allows chaining various operations together for complex data processing workflows.

**Getting Started:**

1. Install the Flow package:
   ```bash
   pub add flow
   ```

2. Import the Flow library in your Dart code:
   ```dart
   import 'package:flow/flow.dart';
   ```

3. Use the provided functions and operators to build your data processing pipelines.

**Example Usage:**

```dart
flowOf([1, 2, 3, 4])
  .map<String>((number) => (number * 2).toString())
  .catchError((error, collector) => print("Error: $error"))
  .collec(print); // Prints: 2, 4, 6, 8
```

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



