

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

  test('Test that .filterNotNull filters out null from emitted values', () async {
    final fl = flow<String?>((collector) {
      collector.emit("A");
      collector.emit("B");
      collector.emit("C");
      collector.emit(null);
      collector.emit(null);
      collector.emit('D');
    })
    .filterNotNull();

    expect(fl.asStream(), emitsInOrder([
      'A', 'B', 'C', 'D'
    ]));
  });

  test('Test that .mapNotNull returns a flow that contains only non-null results', () {
    final fl = flow<int>((collector) {
      collector.emit(1);
      collector.emit(2);
      collector.emit(3);
      collector.emit(4);
    })
    .mapNotNull((value) {
      if (value % 2 == 0) {
        return value;
      }
      return null;
    });

    expect(fl.asStream(), emitsInOrder([
      2, 4]));
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

  test('onEach with error', () {
    final fl = flow((collector) {
      collector.emit('Something');
    }).onEach((value) => throw Exception('tere')).catchError((p0, p1) {
      p1.emit('love');
    });

    expect(fl.asStream(), emitsInOrder([
      'love', emitsDone
    ]));
  });
  
  test('any object can be thrown as an error asides '
  'Exception and will be passed down to catchError', () {

    final caseOne = flow((collector) {

      collector.emit('bala');
    }).onEach((value) => throw 'blue').catchError((error, _) {
      _.emit(error);
    });

    expect(caseOne.asStream(), emitsInOrder([
      'blue', emitsDone
    ]));

    final caseTwo = flow((collector) {
      collector.emit('bala');
    }).onEach((value) => throw 1).catchError((error, _) {
      _.emit(error);
    });

    expect(caseTwo.asStream(), emitsInOrder([
      1, emitsDone
    ]));

    final caseThree = flow((collector) {
     throw ArgumentError('Argument Error');
    }).catchError((error, _) {
      _.emit(error);
    });

    expect(caseThree.asStream(), emitsInOrder([
      isInstanceOf<ArgumentError>(), emitsDone
    ]));
  });

   group("Combination Operators Tests", () {
    group('MergeFlow ', () {
      test('should emit all values from multiple flows', () async {
        final flow1 = flow<int>((collector) async {
          collector.emit(1);
          collector.emit(2);
        });
        
        final flow2 = flow<int>((collector) async {
          collector.emit(3);
          collector.emit(4);
        });

        final mergeFlow = Flow.merge<dynamic>([flow1, flow2]);
        expect(mergeFlow.asStream(), emitsInOrder([1, 3, 2, 4, emitsDone]));
      });

      test('should emit only values from flows without an error and do nothing when a flow explicitly handles its error', () async {
        final flow1 = flow<int>((collector) async {
          throw Exception("Error message");
        }).catchError((_, __){
        //Do nothing
        returnsNormally;    
       });
        
        final flow2 = flow<String>((collector) async {
          collector.emit("Only value");
        });

        final mergeFlow = Flow.merge<dynamic>([flow1, flow2]);
        expect(mergeFlow.asStream(), emitsInOrder(['Only value', emitsDone]));
      });

      test('should emit error when any flow emits error and not handled', () async {
        final flow1 = flow<int>((collector) async {
          throw Exception("Error in flow1");
        });

        final flow2 = flow<int>((collector) async {
          collector.emit(2);
        });

        final mergeFlow = Flow.merge<int>([flow1, flow2]);
        expect(mergeFlow.asStream(),  emitsError(isA<Exception>().having((e) => e.toString(), 'message', contains('Error in flow1') )));
      });
    });

    group('CombineLatestFlow ', () {
      test('should combine latest values from all flows', () async {
        final flow1 = flow<String>((collector) async {
          collector.emit("A");
          collector.emit("B");
          collector.emit("C");
        });
        
        final flow2 = flow<int>((collector) async {
          collector.emit(1);
          collector.emit(2);
          collector.emit(3);
        });

        final combineFlow = Flow.combineLatest<String>(
          [flow1, flow2],
          (values) => "${values[0]}-${values[1]}"
        );

        expect(combineFlow.asStream(), 
          emitsInOrder(["A-1", "B-1", "B-2", "C-2", "C-3", emitsDone]));
      });

      test('should emit error when any of the flows emits an error and no flow handles it error explicitly', () async {
        final flow1 = flow<String>((collector) async {
          throw Exception("ErrorMessage");
        });
        
        final flow2 = flow<String>((collector) async {
          collector.emit("NeverValue");
        });

        final combineLatestFlow = Flow.combineLatest<String>([flow1, flow2], (values) => values.join());
        expect(combineLatestFlow.asStream(), emitsError(isA<Exception>().having((e) => e.toString(), 'message', contains('ErrorMessage'))));
      });


      test('should emit only default value for flows whose errors are handles explicitly', () async {
        final flow1 = flow<String>((collector) async {
          throw Exception("ErrorMessage");
        }).catchError((value, collector){
          collector.emit("DefaultValue");
        });
        
        final flow2 = flow<String>((collector) async {
          collector.emit("OtherValue");
        });

        final combineLatestFlow = Flow.combineLatest<String>([flow1, flow2], (values) => '${values[0]}-${values[1]}');
        expect(combineLatestFlow.asStream(),  emitsInOrder(['DefaultValue-OtherValue', emitsDone]));
      });
    });

    group('RaceFlow ', () {
      test('should only emit values from the first flow to emit', () async {
        final flow1 = flow<String>((collector) async {
          await Future.delayed(const Duration(milliseconds: 200));
          collector.emit("A");
        });
        
        final flow2 = flow<String>((collector) async {
          collector.emit("B");
        });

        final raceFlow = Flow.race([flow1, flow2]);
        expect(raceFlow.asStream(), emitsInOrder(["B", emitsDone]));
      });

      test('should emit error when any of the flows throws an error', () async {
        final flow1 = flow<String>((collector) async {
          throw Exception("ErrorMessage");
        });
        
        final flow2 = flow<String>((collector) async {
          await Future.delayed(const Duration(milliseconds: 100));
          collector.emit("NeverValue");
        });

        final raceFlow = Flow.race([flow1, flow2]);
        expect(raceFlow.asStream(), emitsError(isA<Exception>().having((e) => e.toString(), 'message', contains('ErrorMessage'))));
      });
    });

    test('startWith should emit the provided value before the flow values', () async {
    final fl = flow<String>((collector) {
      collector.emit("A");
      collector.emit("B");
      collector.emit("C");
    }).startWith("START");

    expect(fl.asStream(), emitsInOrder(['START', 'A', 'B', 'C', emitsDone]));
  });
  });

  test('test that we can convert a flow to future using asFuture', () {
    final fl = flow((collector) {
      collector.emit('Something');
    });

    final future = fl.asFuture();

    expectLater(future, completion('Something'));
  });

  test('test that when a flow is converted to future and an error is thrown the future also throws', () async {
    final fl = flow((collector) {
      collector.emit('Something');
    }).onEach((a) => throw Exception('Error1'));

    try {
      await fl.asFuture();
    } catch(e) {
      expect(e.toString(), contains('Error1'));
    }
  });
}
