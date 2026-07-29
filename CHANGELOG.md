## 0.2.1 (2026-07-29)

**Fixes:**

* `emit`/`addError` no longer throw `Bad state: Cannot add new events after calling close` when they race a downstream close. Cancellation in this library is cooperative — closing a controller doesn't preempt an in-flight upstream emit already on its way — so a late call arriving after close is an expected race, not a bug. It's now dropped silently instead, matching how `Stream.multi` already ignores adds from a cancelled listener.

## 0.2.0 (2026-07-28)

**API Changes:**

* `Flow<T>.launchIn(FlowLifecycle lifecycle)` now returns the `CancellationSignal` backing the collection, instead of `void` — mirrors Kotlin's `launchIn` returning a `Job`. Call `.cancel()` on it to stop that specific collection early without disposing `lifecycle` — useful when an instance needs to restart collection for a different argument (e.g. re-subscribing account-scoped data on an account switch) rather than tearing down the whole lifecycle. Non-breaking: the return value is safe to ignore, exactly as before.

## 0.1.1 (2026-07-28)

**Fixes:**

* `Flow.conflateMap` no longer coalesces values it shouldn't: it started its worker via `ProducerScope.launch`, which always defers to a new event-loop turn (`Timer.run`) — so if several sources notified by the same underlying write (e.g. several independently-watched DB tables) all emitted in the same synchronous burst, *every one of them, including the first*, coalesced together before the worker ever got a turn to run. Two temporally-distinct bursts arriving close enough together (e.g. an initial subscribe-time read immediately followed by a fast write-triggered re-read) could collapse into a single processed value instead of two. Fixed by starting the first value's processing synchronously, immediately, rather than through `launch` — only values that arrive *while that's already in flight* are coalesced now, which was the intent all along.

## 0.1.0 (2026-07-28)

**New Features:**

* **Reactive coalescing:**
  * Added `Flow<T>.conflateMap<U>(transform)`: like `map`, but keeps at most one `transform` call in flight, coalescing values that arrive while a previous call is still running down to the latest. Equivalent to Kotlin's `flow.conflate().map { ... }` — deliberately not `mapLatest`/`switchMap`, since it never cancels an in-flight `transform` call (Dart has no cheap way to cancel an arbitrary in-flight `Future`).
* **Concurrent producer flows:**
  * Added `channelFlow<T>((scope) async {...})`: a Flow builder whose block receives a `ProducerScope<T>` instead of a plain `FlowCollector<T>`. `ProducerScope.launch(action)` runs `action` concurrently, routes uncaught errors to `addError` automatically, and the flow doesn't finish until both the block returns and every launched action (including ones launched by another launched action) has completed — unlike a plain `flow()`, which closes as soon as its callback's returned future completes, orphaning any unawaited work still running underneath it.
* **Lifecycle-aware collection:**
  * Added `FlowLifecycle`: a minimal interface (`isDisposed`, `addCleanup`) that lets a Flow know when to stop collecting on its own. Deliberately named to match the shape most ViewModel base classes already have, so implementing it is typically zero new code.
  * Added `Flow<T>.launchIn(FlowLifecycle lifecycle)`, mirroring Kotlin's `Flow.launchIn(scope)`: build the pipeline with `.onEach`/`.catchError` first, then call `.launchIn(lifecycle)` last. No `StreamSubscription` is ever exposed to the caller — collection starts and is cancelled automatically once the lifecycle disposes.
  * Added `CancellationSignal`, threaded through the current `Zone` (mirroring the existing `TaskPoolExecutor` Zone pattern). `AbstractFlow.collectSafely` registers against the ambient signal, so any nested Flow-to-Flow collect happening inside a `launchIn` call cascades its own teardown automatically — no manual cancellation checks needed in application code.

**API Changes:**

* `StreamX.asFlow()` no longer uses a plain `await for` (which can't respond to cancellation at all) — it now subscribes manually and checks the ambient `CancellationSignal`, so a raw source stream (e.g. a database watch stream) gets its own subscription cancelled too, not just the outermost Flow.


## 0.0.1-alpha02 (2024-03-22)

**New Features:**

* **Flow Transformations:**
  * Added `onEach<U>(FutureOr<void> Function(U value) action)`: Enables executing actions on each value emitted by the flow, allowing for side effects or value modifications before passing them downstream.
  * Added `onEmpty(FutureOr<void> Function(FlowCollector<T>) action)`: Provides a mechanism to handle empty flows by executing a specific action if no elements are emitted.
  * Added `filter(FutureOr<bool> Function(T value) action)` method to Flow to selectively emit elements based on a predicate function.
  * Added `distinctUntilChanged(KeySelector<K, T>, EquivalenceMethod<K>)`: which provides a mechanism to filter out subsequent repetitions of the same values within a flow. see also `distinctUntilChangedBy`.
  * Added `cache(CacheFlow<T>, CacheStrategy<T>)`: to create a new Flow that could provide values from the cache or reads directly from the original flow depending on the caching strategy. See Caching Support.
  * Added `retryWith(RetryPolicy Function(Exception cause) action)` method to Flow for flexible retry strategies based on custom retry policies.
  * Added `timeout(Duration)` Extends a flow with a timeout mechanism
* **Caching Support:**
  * `CacheFlow<T>`: Represents a data source or storage mechanism for caching values of type `T`.
  * **Predefined Cache Strategies:** This release introduces several concrete implementations of the `CacheStrategy<T>` interface, offering various cache invalidation and retrieval behaviors:
    * `FetchOrElseCache<T>`: Fetches data from the primary source and caches the result. If fetching fails, retrieves data from the cache if available.
    * `CacheOrElseFetch<T>`: Attempts to retrieve data from the cache first. If the cache is empty or invalid, fetches fresh data and updates the cache.
    * `CacheThenFetch<T>`: Prioritizes cached data and updates the cache only after fetching new data (if successful).
    * `CacheAndFetch<T>`: Attempts to retrieve data concurrently from both the cache and the primary source. Emits cached data first if valid, but also fetches fresh data to update the cache.
    * `CacheOrStaleCacheOnFetchError<T>`: Prioritizes cached data, even if stale. Fetches from the primary source, but if fetching fails, uses potentially outdated cached data as a fallback.
* **Retries Support:**
  * Created `ExponentialBackOff` as a concrete implementation of `RetryPolicy` for exponential back off retry strategy.
  * Created `CircuitBreakerRetryPolicy` as a concrete implementation of `RetryPolicy` for circuit breaker patterns.

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