import 'package:flow/flow.dart';

typedef KeySelector<K, T> = K Function(T value);
typedef EquivalenceMethod<K> = bool Function(K? previousKey, K? nextKey);

class Distinct<K, T> {
  final Flow<T> upstreamFlow;
  KeySelector<K, T> keySelector;
  EquivalenceMethod<K> equivalenceMethod;

  Distinct({
    required this.upstreamFlow,
    KeySelector<K, T>? keySelector,
    EquivalenceMethod<K>? equivalenceMethod,
  })  : keySelector = keySelector ?? ((value) => value as K),
        equivalenceMethod = equivalenceMethod ?? ((K? oldValue, K? newValue) => oldValue == newValue);

  Flow<T> call() {
    return flow((collector) async {
      dynamic previousKey;

      await upstreamFlow.collect((value) async {
        final key = keySelector(value);

        if ((previousKey == null) || (!equivalenceMethod(previousKey, key))) {
          previousKey = key;
          collector.emit(value);
        }
      });
    });
  }
}
