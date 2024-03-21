
class CancellationException implements Exception {
  final Exception cause;
  CancellationException(this.cause);
}

class FlowException implements Exception {
  final Object? cause;
  FlowException(this.cause);
}

class CombinedFlowException implements Exception {
  final List<Exception> errors;
  CombinedFlowException(this.errors);

  void add(Exception exception) {
    errors.add(exception);
  }

  @override
  String toString() {
    return 'CombinedFlowException(${errors.join(',')})';
  }
}

extension ErrorX on Object? {
  Exception toException() {
    if (this is Exception) {
      return this as Exception;
    }
    return FlowException(this);
  }

  bool isIdenticalWith(Exception exception) {
    return this == exception ||
        (runtimeType == exception.runtimeType &&
            toString() == exception.toString());
  }
}
