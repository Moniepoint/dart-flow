import 'package:flow/flow.dart';

void main() async {
  print('--- Flow API Example ---\n');

  // 1. Basic Flow: create, map, and filter
  print('1. Basic Flow with Map and Filter:');
  await flowOf([1, 2, 3, 4, 5, 6])
      .filter((value) => value % 2 == 0) // Keep even numbers
      .map((value) => value * 10)        // Multiply by 10
      .onEach((value) => print('  Processing: $value'))
      .collect((value) => print('  Collected: $value'));

  // 2. Flow with Retry Policy
  print('\n2. Flow with Retry Policy (Simulating transient failure):');
  int attempt = 0;
  await flow<String>((collector) async {
    attempt++;
    if (attempt < 3) {
      print('  Attempt $attempt: Failed!');
      throw Exception('Transient error');
    }
    print('  Attempt $attempt: Success!');
    collector.emit('Resilient Data');
  })
  .retryWith((cause) => RetryPolicy.fixedInterval())
  .catchError((error, collector) => print('  Caught error: $error'))
  .collect((value) => print('  Collected after retry: $value'));

  // 3. Combining Flows
  print('\n3. Combining Flows (Combine Latest):');
  final flow1 = flowOf(['A', 'B', 'C']);
  final flow2 = flowOf(['1', '2', '3']);
  
  await Flow.combineLatest(
    [flow1, flow2], 
    (values) => '${values[0]}-${values[1]}'
  ).collect((value) => print('  Combined: $value'));
}
