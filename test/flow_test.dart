
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
      'A', 'B', 'C'
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
      'A', 'B', 'C'
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
    }).onCompletion((p0, collector) => print('Completed'));

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
    }).retryWhen((cause, attempts) {
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

  test('Test that we can flatMap on an existing flow and return a new flow', () async {
    final fl = flow<String>((collector) {
      collector.emit("A");
    }).flatMap((value) => flowOf(['1', '2', '3']));

    expect(fl.asStream(), emitsInOrder([
      '1','2', '3', emitsDone
    ]));
  });
}

