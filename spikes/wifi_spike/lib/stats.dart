import 'dart:math' as math;

/// Descriptive statistics for spike measurements (not production code).
class Summary {
  Summary._(this.n, this.mean, this.sd, this.min, this.p50, this.p95, this.max);

  final int n;
  final double mean;
  final double sd;
  final double min;
  final double p50;
  final double p95;
  final double max;

  /// Returns null for an empty input: no fake values.
  static Summary? of(Iterable<num> values) {
    final v = values.map((e) => e.toDouble()).toList()..sort();
    if (v.isEmpty) return null;
    final mean = v.reduce((a, b) => a + b) / v.length;
    final variance = v.length < 2
        ? 0.0
        : v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
            (v.length - 1);
    return Summary._(v.length, mean, math.sqrt(variance), v.first,
        _percentile(v, 0.5), _percentile(v, 0.95), v.last);
  }

  static double _percentile(List<double> sorted, double q) {
    if (sorted.length == 1) return sorted.first;
    final pos = q * (sorted.length - 1);
    final lo = pos.floor();
    final hi = pos.ceil();
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }

  Map<String, Object> toJson() => {
        'n': n,
        'mean': mean,
        'sd': sd,
        'min': min,
        'p50': p50,
        'p95': p95,
        'max': max,
      };

  @override
  String toString() =>
      'n=$n mean=${mean.toStringAsFixed(1)} sd=${sd.toStringAsFixed(1)} '
      'min=${min.toStringAsFixed(1)} p50=${p50.toStringAsFixed(1)} '
      'p95=${p95.toStringAsFixed(1)} max=${max.toStringAsFixed(1)}';
}

/// Intervals between consecutive timestamps (same unit as input).
List<num> intervals(List<num> timestamps) => [
      for (var i = 1; i < timestamps.length; i++)
        timestamps[i] - timestamps[i - 1],
    ];
