## 0.0.1-alpha02 (2024-03-18)

**New Features:**

* **Flow Transformations:**
  * `onEach<U>(FutureOr<void> Function(U value) action)`: Enables executing actions on each value emitted by the flow, allowing for side effects or value modifications before passing them downstream.
  * `onEmpty(FutureOr<void> Function(FlowCollector<T>) action)`: Provides a mechanism to handle empty flows by executing a specific action if no elements are emitted.
* **Caching Support:**
  * `CacheFlow<T>`: Represents a data source or storage mechanism for caching values of type `T`.
  * **Predefined Cache Strategies:** This release introduces several concrete implementations of the `CacheStrategy<T>` interface, offering various cache invalidation and retrieval behaviors:
    * `FetchOrElseCache<T>`: Fetches data from the primary source and caches the result. If fetching fails, retrieves data from the cache if available.
    * `CacheOrElseFetch<T>`: Attempts to retrieve data from the cache first. If the cache is empty or invalid, fetches fresh data and updates the cache.
    * `CacheThenFetch<T>`: Prioritizes cached data and updates the cache only after fetching new data (if successful).
    * `CacheAndFetch<T>`: Attempts to retrieve data concurrently from both the cache and the primary source. Emits cached data first if valid, but also fetches fresh data to update the cache.
    * `CacheOrStaleCacheOnFetchError<T>`: Prioritizes cached data, even if stale. Fetches from the primary source, but if fetching fails, uses potentially outdated cached data as a fallback.

**API Changes:**

* Updates the implementation of `collect` to ensure it waits for all its callbacks to complete before returning. This addresses the previously mentioned limitation in `onCompletion`.


## v0.0.1-alpha (2024-03-14) **Initial Release**

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