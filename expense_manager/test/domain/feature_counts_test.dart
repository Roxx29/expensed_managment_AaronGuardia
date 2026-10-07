import 'package:expense_manager/domain/usage/feature_counts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bump adds one and caps the number of keys', () {
    expect(bumpFeature({}, 'a'), {'a': 1});
    expect(bumpFeature({'a': 1}, 'a'), {'a': 2});
    final full = {for (var i = 0; i < maxFeatureKeys; i++) 'k$i': 1};
    expect(bumpFeature(full, 'new'), full);
    expect(bumpFeature(full, 'k0')['k0'], 2);
  });

  test('parse survives garbage and round-trips', () {
    expect(parseFeatures(null), isEmpty);
    expect(parseFeatures('nope'), isEmpty);
    expect(parseFeatures('{"a":2,"b":"x"}'), {'a': 2});
    expect(parseFeatures(encodeFeatures({'x': 3})), {'x': 3});
  });

  test('route paths map to feature names without ids', () {
    expect(featureForPath('/'), 'home');
    expect(featureForPath('/more/statistics'), 'statistics');
    expect(featureForPath('/more'), 'more');
    expect(featureForPath('/transactions'), 'history');
    expect(featureForPath('/wallet/abc123'), 'wallet_open');
    expect(featureForPath('/transaction/new'), isNull);
  });
}
