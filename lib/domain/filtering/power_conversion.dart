import 'dart:math' as math;

/// dBm -> milliwatts: mW = 10^(dBm / 10).
double dbmToMw(double dbm) {
  if (!dbm.isFinite) throw ArgumentError.value(dbm, 'dbm', 'must be finite');
  return math.pow(10, dbm / 10).toDouble();
}

/// Milliwatts -> dBm: dBm = 10 * log10(mW). [mw] must be positive and finite.
double mwToDbm(double mw) {
  if (!mw.isFinite || mw <= 0) {
    throw ArgumentError.value(mw, 'mw', 'must be positive and finite');
  }
  return 10 * math.log(mw) / math.ln10;
}
