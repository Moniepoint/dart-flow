


/// Abstract class representing a collector for emitting data in a Flow.
///
/// This class defines the interface for emitting values of type `T` within
/// a `Flow`. Concrete implementations must adhere to
/// this interface and provide a mechanism to send data downstream in the flow.
abstract class FlowCollector<T> {
  /// Emits a value of type `T` into the flow.
  ///
  /// This method is the core functionality of the `FlowCollector`. Specific
  /// implementations will likely delegate this call to an underlying data
  /// processing mechanism within the `Flow` api.
  void emit(T value);
}

