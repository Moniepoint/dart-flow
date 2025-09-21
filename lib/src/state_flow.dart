import 'dart:async';
import 'package:flow/src/abstract_hot_flow.dart';
import 'package:meta/meta.dart';

class StateFlow<T> extends AbstractHotFlow<T> {
  T _currentValue;
  final bool Function(T oldValue, T newValue) _areEqual;

  StateFlow(T initialValue, {bool Function(T oldValue, T newValue)? areEqual})
      : _currentValue = initialValue,
        _areEqual = areEqual ?? ((a, b) => a == b),
        super();

  T get value => _currentValue;

  set value(T newValue) {
    if (isClosed) return;
    if (!_areEqual(_currentValue, newValue)) {
      _currentValue = newValue;
      dispatchValue(_currentValue);
    }
  }

  void update(T newValue) {
    this.value = newValue;
  }

  @override
  @protected
  FutureOr<void> emitInitialValues(FutureOr<void> Function(T value) collector) async {
    await collector(_currentValue);
  }
}
