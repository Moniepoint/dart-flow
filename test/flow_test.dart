

import 'package:flutter_test/flutter_test.dart';
import 'package:flow/flow.dart';


void main() {
  test('Test that we can create a flow and emit values', () async {
    final fl = flow<String>((collector) {
      collector.emit("A");
      collector.emit("B");
      collector.emit("C");
    });

    expect(fl.asStream(), emitsInOrder([
      'A', 'B', 'C', emitsDone
    ]));
  });

  test('Test that we can handle errors in a flow', () async {
    final fl = flow<String>((collector) {
      collector.emit("A");
      collector.emit("B");
      collector.emit("C");
      throw Exception('ProducerBlock Exception');
    }).catchError((p0, p1) {
      print('This exception should be ignored');
    });

    expect(fl.asStream(), emitsInOrder([
      'A', 'B', 'C', emitsDone
    ]));
  });

  test('Test that we can emit a value downstream when an error is encountered', () async {
    final fl = flow<String>((collector) {
      collector.emit("A");
      collector.emit("B");
      collector.emit("C");
      collector.emit("D");
      collector.emit("E");
      throw Exception('502');
    }).catchError((error, collector) {
      if (error.toString().contains('502')) {
        collector.emit('F');
        return;
      }
      throw error;
    });

    expect(fl.asStream(), emitsInOrder([
      'A', 'B', 'C', 'D', 'E', 'F', emitsDone
    ]));
  });

  test('Test that the onCompletion callback is triggered when the flow is done', () async {
    final fl = flow<String>((collector) {
      collector.emit("A");
      collector.emit("B");
      collector.emit("C");
    }).onCompletion((p0, collector) async {
      print('Completed');
    });

    expect(fl.asStream(), emitsInOrder([
      'A', 'B', 'C', emitsDone
    ]));
  });

  test('Test that we can retry a flow based on certain conditions when an error is encountered', () async {

    final fl = flow<String>((collector) {
      collector.emit("A");
      collector.emit("B");
      collector.emit("C");
      throw Exception('Loveliness');
    }).retryWhen((cause, attempts) async {
      if (attempts < 2) {
        return true;
      }
      return false;
    });

    expect(fl.asStream(), emitsInOrder([
      'A', 'B', 'C', 'A', 'B', 'C', 'A', 'B', 'C',
      emitsError(isInstanceOf<Exception>().having((p0) => p0.toString(), 'exception message', contains('Loveliness')))
    ]));
  });


  test('Test that onStart is called before the flow block is triggered', () async {

    final fl = flow<String>((collector) {
      collector.emit("A");
      collector.emit("B");
      collector.emit("C");
    }).onStart((collector) {
      collector.emit('0');
    });

    expect(fl.asStream(), emitsInOrder([
      '0','A', 'B', 'C', emitsDone
    ]));
  });

  test('Test that we can subsequent repitions from a flow', () async {

    final fl = flow<String>((collector) {
      collector.emit("A");
      collector.emit("B");
      collector.emit("A");
      collector.emit("C");
      collector.emit("C");
    }).distinctUntilChanged();

    expect(fl.asStream(),emitsInOrder([
      "A","B","A","C", emitsDone
    ]));
  });

  test('Test that we can subsequent repitions from a flow, by using a key that we set', () async {

    final fl = flow<(String,int)>((collector) {
      collector.emit(('A',1));
      collector.emit(('B',3));
      collector.emit(('C',3));
    }).distinctUntilChangedBy((value) => value.$2);

    expect(fl.asStream(),emitsInOrder([
      ('A', 1), ('B', 3), emitsDone
    ]));
  });


  test('Test that we can flatMap on an existing flow and return a new flow', () async {
    final fl = flow<String>((collector) {
      collector.emit("A");
    }).flatMap((value) => flowOf(['1', '2', '3']));

    expect(fl.asStream(), emitsInOrder([
      '1','2', '3', emitsDone
    ]));
  });

  test('Test that onEmpty is called when the flow doesnt emit any value', () async {
    final fl = flow<String>((collector) {}).onEmpty((collector) {
      collector.emit('Empty');
    });

    expect(fl.asStream(), emitsInOrder([
      'Empty', emitsDone
    ]));
  });

  test('Test that onEmpty IS NOT called when the flow emits any value', () async {
    final fl = flow<String>((collector) {
      collector.emit('NotEmpty');
    }).onEmpty((collector) {
      collector.emit('Empty');
    });

    expect(fl.asStream(), emitsInOrder([
      'NotEmpty', emitsDone
    ]));
  });

  group('Timeout', () {
    test('Test that when the timeout expires a TimeoutCancellationException is thrown', () async {
      final fl = flow<String>((collector) async {
        await Future.delayed(const Duration(milliseconds: 1000));
        collector.emit('NotEmpty');
      }).timeout(const Duration(milliseconds: 400));

      expect(fl.asStream(), emitsInOrder([
        emitsError(isInstanceOf<TimeoutCancellationException>())
      ]));
    });

    test('Test that if we emit values before a timeout it is emitted ', () async {
      final fl = flow<String>((collector) async {
        await Future.delayed(const Duration(milliseconds: 300));
        collector.emit('EscapesTimeout-1');
        await Future.delayed(const Duration(milliseconds: 1000));
      }).timeout(const Duration(milliseconds: 400));

      expect(fl.asStream(), emitsInOrder([
        'EscapesTimeout-1', emitsError(isInstanceOf<TimeoutCancellationException>())
      ]));
    });

    test('Test that the timeout is restarted/reset for each emission', () async {
      final fl = flow<String>((collector) async {
        await Future.delayed(const Duration(milliseconds: 300));
        collector.emit('EscapesTimeout-1');
        await Future.delayed(const Duration(milliseconds: 350));
        collector.emit('EscapesTimeout-2');
      }).timeout(const Duration(milliseconds: 400));

      expect(fl.asStream(), emitsInOrder([
        'EscapesTimeout-1', 'EscapesTimeout-2'
      ]));
    });
  });

  test('Test that when theres a delay and onEach continually throws catchError catches it', () async {
    bool caughtError = false;
    flow<String>((collector) async {
      await Future.delayed(const Duration(milliseconds: 200));
      collector.emit('A');
    }).onEach((value) => throw Exception('Pending'))
        .catchError((e, _) async {
          caughtError = true;
          _.emit('test1');
          _.emit('test2');
          _.emit('test3');
          await Future.delayed(const Duration(milliseconds: 400));
          _.emit('emission1');
          _.emit('emission2');
        })
        .collect(print);

    await Future.delayed(const Duration(seconds: 1));
    expect(true, caughtError);
  });
}




