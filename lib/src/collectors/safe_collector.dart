
import 'dart:async';

import 'flow_collector.dart';

/// Class representing a safe collector for Flow values.
class SafeCollector {
  /// Internal collector reference for handling values, errors, and completion.
  FlowCollector<dynamic>? _collector;
  Function()? _onDone;
  Function? _onError;

  /// Default error handling function.
  ///
  /// This function forwards errors encountered during collection to the
  /// collector's `addError` method (if a collector is set). You can customize
  /// error handling behavior using the `tryCatch` method.
  void onError(e, [StackTrace? trace]) async {
    if (null != _onError) {
      if (_onError is Function(dynamic, dynamic)) {
        await _onError?.call(e, trace);
      } else if (_onError is Function(dynamic)) {
        await _onError?.call(e);
      }
    } else {
      _collector?.addError(e);
    }
  }

  /// Default completion handling function.
  ///
  /// This function calls the collector's `close` method (if a collector is set)
  /// upon completion of the flow. You can customize completion behavior using
  /// the `done` method.
  void onDone() {
    if (null != _onDone) {
      _onDone?.call();
    } else {
      _collector?.close();
    }
  }

  /// Associates a specific `FlowCollector` with this SafeCollector.
  ///
  /// This allows for tailored handling of values, errors, and completion
  /// within the provided collector.
  SafeCollector collectWith(FlowCollector<dynamic> collector) {
    _collector = collector;
    return this;
  }

  /// Configures a custom error handling function.
  ///
  /// This allows you to handle errors differently than the default behavior
  /// of forwarding them to the collector's `addError` method. The provided
  /// function can take either one or two arguments: the error object and an
  /// optional stack trace.
  SafeCollector tryCatch(Function onError) {
    _onError = onError;
    return this;
  }

  /// Configures a custom completion handling function.
  ///
  /// This allows you to define custom actions to be performed upon
  /// completion of the flow, beyond the default behavior of closing the collector.
  SafeCollector done(void Function() onDone) {
    _onDone = onDone;
    return this;
  }

  /// Safely sends an error even if a collector is not yet set.
  ///
  /// This method utilizes the configured error handler (`onError`) to handle
  /// the provided error object and optional stack trace. It ensures errors
  /// are not silently swallowed even before a collector is associated.
  FutureOr<void> sendError(Object a, [StackTrace? trace]) async {
    return onError(a, trace);
  }

  /// Cleans up internal resources associated with the SafeCollector.
  void destroy() {
    _collector = null;
  }
}