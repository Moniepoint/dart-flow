
class CancellationException implements Exception {
  final dynamic cause;
  CancellationException(this.cause);
}

class FlowException implements Exception {
  final Object? cause;
  FlowException(this.cause);

  @override
  String toString() => "FlowException($cause)";
}

class CombinedFlowException implements Exception {
  final List<dynamic> errors;
  CombinedFlowException(this.errors);

  void add(dynamic exception) {
    errors.add(exception);
  }

  /// Safely retrieves an exception of type T from the errors list.
  /// If `T` is not found, returns `null`.
  T? get<T>() {
    for (var error in errors) {
      if (error is T) {
        return error;
      }
    }
    return null;
  }

  @override
  String toString() {
    return 'CombinedFlowException(${errors.join(',')})';
  }
}

class TimeoutCancellationException implements Exception {
  final Duration duration;

  TimeoutCancellationException(this.duration);

  @override
  String toString() => "Flow execution timed out after $duration";
}

extension ErrorX on Object? {
  Exception toException() {
    if (this is Exception) {
      return this as Exception;
    }
    return FlowException(this);
  }

  bool isIdenticalWith(dynamic exception) {
    return this == exception ||
        (runtimeType == exception.runtimeType &&
            toString() == exception.toString());
  }
}
