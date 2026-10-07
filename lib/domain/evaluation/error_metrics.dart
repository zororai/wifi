import 'dart:math' as math;

/// Root mean square error of [errors] (predicted - actual), in dB.
/// Throws [ArgumentError] for an empty or non-finite input.
double rmse(List<double> errors) {
  _check(errors);
  var sq = 0.0;
  for (final e in errors) {
    sq += e * e;
  }
  return math.sqrt(sq / errors.length);
}

/// Mean absolute error of [errors] (predicted - actual), in dB.
/// Throws [ArgumentError] for an empty or non-finite input.
double mae(List<double> errors) {
  _check(errors);
  var sum = 0.0;
  for (final e in errors) {
    sum += e.abs();
  }
  return sum / errors.length;
}

void _check(List<double> errors) {
  if (errors.isEmpty) throw ArgumentError('No errors to summarise');
  if (errors.any((e) => !e.isFinite)) {
    throw ArgumentError('Errors must be finite');
  }
}
