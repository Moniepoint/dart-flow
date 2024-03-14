## 0.0.1 (2024-03-14) **Initial Release**

This initial release introduces the foundation for the Flow API, providing functionalities for building asynchronous data processing pipelines. It includes the following core features:

* **Flow Class:** Represents a stream of values of a specific type (`T`).
* **Flow Operators:** Extension methods for the `Flow<T>` class offering functionalities like:
    * `map<U>`: Applies a transformation function to each element in the flow.
    * `flatMap<U>`: Applies a transformation function that returns a new flow
    * `catchError`: Handles errors that occur within the flow.
    * `onStart`: Executes an action before the flow starts collecting data.
    * `onCompletion`: Executes an action upon flow completion (**needs improvement**).
    * `retryWhen`: Implements retry logic based on a provided function to handle temporary errors.
* **Flow Collectors:**
    * `FlowCollector` (abstract): Defines an interface for emitting data within a Flow.
* **Flow Creation Functions:**
    * `flow`: Creates a new Flow with a provided action for data emission.
    * `flowOf`: Creates a Flow from an iterable collection of elements.

**Additional Notes:**

* The `onCompletion` functionality currently requires improvement for proper error handling within the flow context.
* This is an initial release, and further features and functionalities are planned for future versions.
