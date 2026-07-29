import 'dart:async';

import 'package:flow/src/collectors/collectors.dart';
import 'package:test/test.dart';

void main() {
  group('FlowCollectorImpl', () {
    test('emit/addError after the controller is closed are dropped, not thrown', () async {
      final controller = StreamController<String>.broadcast();
      final collector = FlowCollectorImpl<String>(controller);

      final events = <String>[];
      final errors = <Object>[];
      controller.stream.listen(events.add, onError: errors.add);

      collector.emit('before close');
      await controller.close();

      // Cancellation in this library is cooperative — an emit/addError
      // that was already on its way when the controller closed is an
      // expected race, not a bug. It must be dropped silently, like
      // Stream.multi already does for a cancelled listener, not throw
      // "Bad state: Cannot add new events after calling close".
      expect(() => collector.emit('after close'), returnsNormally);
      expect(() => collector.addError(Exception('after close')), returnsNormally);

      expect(events, ['before close']);
      expect(errors, isEmpty);
    });
  });
}
