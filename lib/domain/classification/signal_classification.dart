/// Signal-quality classes, strongest first.
enum SignalClass {
  excellent('Excellent'),
  veryGood('Very good'),
  good('Good'),
  fair('Fair'),
  weak('Weak'),
  veryWeak('Very weak');

  const SignalClass(this.label);
  final String label;
}

/// Lower bounds (inclusive) for each class, in dBm.
///
/// Classes are half-open intervals so that every real value, including
/// non-integer filtered values such as -50.5, maps to exactly one class:
///
///   Excellent  r >= excellentMin                 (default r >= -50)
///   Very good  veryGoodMin <= r < excellentMin   (-60 <= r < -50)
///   Good       goodMin     <= r < veryGoodMin    (-67 <= r < -60)
///   Fair       fairMin     <= r < goodMin        (-75 <= r < -67)
///   Weak       weakMin     <= r < fairMin        (-85 <= r < -75)
///   Very weak  r < weakMin                       (r < -85)
///
/// For integer readings this is exactly the specified table
/// (>= -50, -51..-60, -61..-67, -68..-75, -76..-85, < -85).
final class ClassificationThresholds {
  /// Throws [ArgumentError] unless thresholds are finite and strictly
  /// decreasing.
  ClassificationThresholds({
    this.excellentMin = -50,
    this.veryGoodMin = -60,
    this.goodMin = -67,
    this.fairMin = -75,
    this.weakMin = -85,
  }) {
    final t = [excellentMin, veryGoodMin, goodMin, fairMin, weakMin];
    if (t.any((v) => !v.isFinite)) {
      throw ArgumentError('Thresholds must be finite: $t');
    }
    for (var i = 1; i < t.length; i++) {
      if (!(t[i] < t[i - 1])) {
        throw ArgumentError('Thresholds must be strictly decreasing: $t');
      }
    }
  }

  final double excellentMin;
  final double veryGoodMin;
  final double goodMin;
  final double fairMin;
  final double weakMin;

  /// Throws [ArgumentError] for a non-finite value.
  SignalClass classify(double rssiDbm) {
    if (!rssiDbm.isFinite) {
      throw ArgumentError.value(rssiDbm, 'rssiDbm', 'must be finite');
    }
    if (rssiDbm >= excellentMin) return SignalClass.excellent;
    if (rssiDbm >= veryGoodMin) return SignalClass.veryGood;
    if (rssiDbm >= goodMin) return SignalClass.good;
    if (rssiDbm >= fairMin) return SignalClass.fair;
    if (rssiDbm >= weakMin) return SignalClass.weak;
    return SignalClass.veryWeak;
  }
}

/// Default weak-zone threshold in dBm.
const defaultWeakThresholdDbm = -75.0;

/// A value is weak when it is strictly below [thresholdDbm]. With the
/// default -75 dBm this matches the classes: -75 is Fair, -76 is Weak.
bool isWeak(double rssiDbm, {double thresholdDbm = defaultWeakThresholdDbm}) =>
    rssiDbm < thresholdDbm;
