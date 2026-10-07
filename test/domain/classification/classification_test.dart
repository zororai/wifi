import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/domain/classification/signal_classification.dart';

void main() {
  final t = ClassificationThresholds();

  group('default classification boundaries', () {
    final cases = <double, SignalClass>{
      -30: SignalClass.excellent,
      -50: SignalClass.excellent,
      -51: SignalClass.veryGood,
      -60: SignalClass.veryGood,
      -61: SignalClass.good,
      -67: SignalClass.good,
      -68: SignalClass.fair,
      -75: SignalClass.fair,
      -76: SignalClass.weak,
      -85: SignalClass.weak,
      -86: SignalClass.veryWeak,
      -100: SignalClass.veryWeak,
    };
    cases.forEach((rssi, expected) {
      test('$rssi dBm -> ${expected.label}', () {
        expect(t.classify(rssi), expected);
      });
    });
  });

  group('non-integer filtered values map to exactly one class', () {
    final cases = <double, SignalClass>{
      -50.5: SignalClass.veryGood,
      -60.5: SignalClass.good,
      -67.5: SignalClass.fair,
      -75.5: SignalClass.weak,
      -85.5: SignalClass.veryWeak,
      -49.9: SignalClass.excellent,
    };
    cases.forEach((rssi, expected) {
      test('$rssi dBm -> ${expected.label}', () {
        expect(t.classify(rssi), expected);
      });
    });
  });

  test('non-finite values throw', () {
    expect(() => t.classify(double.nan), throwsArgumentError);
  });

  test('custom thresholds are honoured', () {
    final c = ClassificationThresholds(
      excellentMin: -45,
      veryGoodMin: -55,
      goodMin: -65,
      fairMin: -70,
      weakMin: -80,
    );
    expect(c.classify(-50), SignalClass.veryGood);
    expect(c.classify(-70), SignalClass.fair);
    expect(c.classify(-81), SignalClass.veryWeak);
  });

  test('thresholds must be strictly decreasing', () {
    expect(
      () => ClassificationThresholds(veryGoodMin: -50),
      throwsArgumentError,
    );
    expect(() => ClassificationThresholds(goodMin: -55), throwsArgumentError);
    expect(
      () => ClassificationThresholds(weakMin: double.nan),
      throwsArgumentError,
    );
  });

  group('isWeak', () {
    test('default -75: -75 is not weak, -76 and -75.5 are', () {
      expect(isWeak(-75), isFalse);
      expect(isWeak(-75.5), isTrue);
      expect(isWeak(-76), isTrue);
      expect(isWeak(-60), isFalse);
    });
    test('custom threshold', () {
      expect(isWeak(-70, thresholdDbm: -65), isTrue);
    });
  });
}
