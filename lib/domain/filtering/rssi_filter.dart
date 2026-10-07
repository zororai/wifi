import 'power_conversion.dart';

/// How several samples at one point are combined into one value.
enum FilterMethod {
  /// Robust to outliers (default).
  median,

  /// Arithmetic mean.
  mean,
}

/// Which quantity the filter operates on.
///
/// These are mathematically different choices and generally give different
/// results:
/// - [dbm]: combine the logarithmic dBm values directly (default).
/// - [linearMw]: convert to milliwatts, combine, convert back to dBm.
///   A mean in mW is a power average and is pulled towards the strongest
///   samples, so it is always >= the dBm mean (Jensen's inequality).
///   A median is order-preserving, so for an odd count both domains select
///   the same sample; for an even count the two middle values are averaged
///   in different domains and differ slightly.
enum AveragingDomain { dbm, linearMw }

/// Median of [values]. Returns null for an empty list.
/// Throws [ArgumentError] if any value is not finite.
double? median(List<double> values) {
  _checkFinite(values);
  if (values.isEmpty) return null;
  final s = [...values]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/// Arithmetic mean of [values]. Returns null for an empty list.
/// Throws [ArgumentError] if any value is not finite.
double? mean(List<double> values) {
  _checkFinite(values);
  if (values.isEmpty) return null;
  var sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  return sum / values.length;
}

/// Combines dBm samples into one dBm value using [method] in [domain].
/// Returns null when there are no samples (no value is invented).
double? combineRssi(
  List<double> dbmValues, {
  required FilterMethod method,
  required AveragingDomain domain,
}) {
  _checkFinite(dbmValues);
  if (dbmValues.isEmpty) return null;
  double? apply(List<double> v) => switch (method) {
    FilterMethod.median => median(v),
    FilterMethod.mean => mean(v),
  };
  return switch (domain) {
    AveragingDomain.dbm => apply(dbmValues),
    AveragingDomain.linearMw => mwToDbm(
      apply([for (final d in dbmValues) dbmToMw(d)])!,
    ),
  };
}

void _checkFinite(List<double> values) {
  for (final v in values) {
    if (!v.isFinite) {
      throw ArgumentError.value(v, 'values', 'contains a non-finite value');
    }
  }
}
