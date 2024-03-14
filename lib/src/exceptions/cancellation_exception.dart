class CancellationException implements Exception {
  final Exception cause;
  CancellationException(this.cause);
}