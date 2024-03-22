import 'dart:async';
import 'dart:math';

void asa() {
}
/// Abstract class that defines the interface for retry strategies in Dart Flow.

abstract class RetryPolicy {
  /// Determines when to retry an operation based on the current retry attempt.

  /// This abstract method must be implemented by concrete subclasses
  /// to define the retry logic. It should return a `FutureOr<bool>`.
  ///
  /// - Returning `true` indicates a retry should be attempted.
  /// - Returning `false` or completing the future with a `false` value signals
  /// the end of retries.
  FutureOr<bool> retry<T>(int attempts);

  /// Factory constructor that creates an instance of a RetryPolicy that
  /// implements an exponential backoff retry logic.
  factory RetryPolicy.exponentialBackOff(
      {int baseDelay,
      int maxAttempts,
      int multiplier,
      int maxDelay}) = _ExponentialBackOff;

  factory RetryPolicy.circuitBreaker(
      {int failureThreshold,
      int resetTimeout,
      int halfOpenThreshold,
      ({int start, int end}) coolDownTime}) = _CircuitBreakerRetryPolicy;

  factory RetryPolicy.noRetry() = _NoRetryPolicy;

  /// Factory constructor that create an instance of a Fixed Interval retry policy
  factory RetryPolicy.fixedInterval({
    int delay,
    int maxAttempts,
  }) = _FixedIntervalRetryPolicy;

  /// Factory constructor that create an instance of a Fixed Interval retry policy
  factory RetryPolicy.decorrelatedJitter({
    int baseDelay,
    int maxAttempts,
    int multiplier,
    int maxDelay,
    double jitterFactor,
  }) = _DecorrelatedJitterRetryPolicy;
}

final class _NoRetryPolicy implements RetryPolicy {
  @override
  FutureOr<bool> retry<T>(int attempts) => false;
}

/// Concrete class that implements a retry strategy with exponential backoff.
final class _ExponentialBackOff implements RetryPolicy {
  /// The initial delay between retries in milliseconds (default: 2000).
  final int baseDelay;

  /// The factor by which the delay is multiplied after each attempt
  /// (default: 2).
  final int multiplier;

  /// The maximum number of retry attempts (default: 20).
  final int maxAttempts;

  /// The maximum allowed delay between retries in milliseconds
  /// (default: 400000).
  final int maxDelay;

  _ExponentialBackOff({
    this.baseDelay = 2000,
    this.maxAttempts = 20,
    this.multiplier = 2,
    this.maxDelay = 400000,
  });

  @override
  FutureOr<bool> retry<T>(int attempts) async {
    int delay = baseDelay * (multiplier ^ (attempts - 1));

    delay = delay.clamp(0, maxDelay);

    await Future.delayed(Duration(milliseconds: delay));

    return attempts < maxAttempts;
  }
}

enum _CircuitState {
  /// Initial state. Retries are allowed.
  closed,

  /// Circuit is tripped due to exceeding the failure threshold. No retries are
  /// allowed.
  open,

  /// Circuit allows a limited number of retries to test if the issue is
  /// resolved.
  halfOpen,
}

/// Implements a retry policy based on the Circuit Breaker pattern for
/// operations prone to failures.
class _CircuitBreakerRetryPolicy implements RetryPolicy {
  /// The number of consecutive failures in the closed state that triggers the
  /// open state (default: 4).
  final int failureThreshold;

  /// The time the circuit remains open before transitioning back to
  /// closed (milliseconds) (default: 10000).
  final int resetTimeout;

  /// The maximum number of retries allowed in the half-open state (default: 2).
  final int halfOpenThreshold;

  /// A random cooldown duration (between `start` and `end`) added to
  /// `resetTimeout` when transitioning back to open from half-open on failure
  /// (default: 1000-2000 milliseconds).
  final ({int start, int end}) coolDownTime;

  /// The current state of the circuit breaker (closed, open, or halfOpen).
  _CircuitState state = _CircuitState.closed;

  int halfOpenAttempts = 0;

  _CircuitBreakerRetryPolicy({
    this.failureThreshold = 4,
    this.resetTimeout = 10000,
    this.halfOpenThreshold = 2,
    this.coolDownTime = const (start: 1000, end: 2000),
  });

  @override
  FutureOr<bool> retry<T>(int attempts) async {
    return await _transitionState(attempts);
  }

  Future<bool> _transitionState(int attempts) async {
    switch (state) {
      case _CircuitState.closed:
        if (attempts >= failureThreshold) {
          state = _CircuitState.open;
          return _transitionState(attempts);
        }
        return true;
      case _CircuitState.open:
        await Future.delayed(Duration(milliseconds: resetTimeout));
        state = _CircuitState.halfOpen;
        halfOpenAttempts = 0;
        return _transitionState(attempts);
      case _CircuitState.halfOpen:
        if (attempts == 0) {
          state = _CircuitState.closed;
        } else if (halfOpenAttempts < halfOpenThreshold) {
          halfOpenAttempts++;
          if (halfOpenAttempts == halfOpenThreshold) {
            final coolDownPeriod = Random()
                .nextInt(coolDownTime.end)
                .clamp(coolDownTime.start, coolDownTime.end);
            await Future.delayed(Duration(milliseconds: coolDownPeriod));
            state = _CircuitState.open;
          }
        }
        return true;
    }
  }
}

/// Implements a fixed interval retry policy
final class _FixedIntervalRetryPolicy implements RetryPolicy {

  /// The delay between retries in milliseconds (default: 2000).
  final int delay;

  /// The maximum number of retry attempts (default: 20).
  final int maxAttempts;

  _FixedIntervalRetryPolicy({
    this.delay = 2000,
    this.maxAttempts = 20,
  });

  @override
  FutureOr<bool> retry<T>(int attempts) async {
    await Future.delayed(Duration(milliseconds: delay));
    return attempts < maxAttempts;
  }
}

/// Implements a retry strategy with decorrelated jitter.
final class _DecorrelatedJitterRetryPolicy implements RetryPolicy {
  /// The initial delay between retries in milliseconds (default: 2000).
  final int baseDelay;

  /// The factor by which the delay is multiplied after each attempt
  /// (default: 2).
  final int multiplier;

  /// The maximum number of retry attempts (default: 20).
  final int maxAttempts;

  /// The maximum allowed delay between retries in milliseconds
  /// (default: 400000).
  final int maxDelay;

  /// A value between 0 and 1 that determines the range of the random jitter.
  final double jitterFactor;

  _DecorrelatedJitterRetryPolicy({
    this.baseDelay = 2000,
    this.maxAttempts = 20,
    this.multiplier = 2,
    this.maxDelay = 400000,
    this.jitterFactor = 0.5,
  });

  @override
  FutureOr<bool> retry<T>(int attempts) async {
    int delay = baseDelay * (multiplier ^ (attempts - 1));

    final jitterAmount = (Random().nextDouble() * delay * jitterFactor).toInt();

    delay = (delay + jitterAmount).clamp(0, maxDelay);

    await Future.delayed(Duration(milliseconds: delay));

    return attempts < maxAttempts;
  }
}
