import 'dart:math' as math;

import '../model/measurement.dart';
import '../model/room.dart';

/// Inverse Distance Weighting parameters.
final class IdwConfig {
  /// Throws [ArgumentError] if [power] <= 0 or non-finite, or
  /// [maxNeighbours] < 1.
  IdwConfig({
    this.power = defaultPower,
    this.maxNeighbours = defaultNeighbours,
  }) {
    if (!power.isFinite || power <= 0) {
      throw ArgumentError.value(power, 'power', 'must be > 0 and finite');
    }
    if (maxNeighbours < 1) {
      throw ArgumentError.value(maxNeighbours, 'maxNeighbours', 'must be >= 1');
    }
  }

  static const defaultPower = 2.0;
  static const defaultNeighbours = 8;

  /// Distance exponent p in w = 1 / d^p.
  final double power;

  /// Number of nearest measured points used per prediction. If fewer points
  /// exist, all are used.
  final int maxNeighbours;

  @override
  String toString() => 'IdwConfig(p=$power, k=$maxNeighbours)';
}

/// Inverse Distance Weighting over MEASURED points, in metres:
///
///   RSSI(x) = sum(w_i * RSSI_i) / sum(w_i),   w_i = 1 / d_i^p
///
/// using the [IdwConfig.maxNeighbours] nearest points.
///
/// Properties relied on elsewhere:
/// - The result is a weighted average with positive weights, so it always
///   lies between the minimum and maximum of the neighbours used. IDW can
///   therefore never exceed the strongest measured value, nor go below the
///   weakest. It cannot reveal a stronger spot that was never measured.
/// - A query exactly on a measured location (distance <= [exactMatchM])
///   returns the measured value without dividing by zero. If several points
///   share that location (repeated measurements), their mean in dBm is
///   returned.
///
/// Values are combined in dBm (not mW), the conventional choice for RSSI
/// maps; this is documented so results can be reproduced.
final class IdwInterpolator {
  /// Throws [ArgumentError] if [points] is empty.
  IdwInterpolator(List<MeasuredPoint> points, this.config)
    : _xs = [for (final p in points) p.position.x],
      _ys = [for (final p in points) p.position.y],
      _vs = [for (final p in points) p.rssiDbm] {
    if (points.isEmpty) {
      throw ArgumentError.value(
        points,
        'points',
        'IDW needs at least one point',
      );
    }
  }

  /// Distances at or below this are treated as the same location (metres).
  static const exactMatchM = 1e-9;

  final IdwConfig config;
  final List<double> _xs;
  final List<double> _ys;
  final List<double> _vs;

  int get pointCount => _vs.length;

  /// Predicted RSSI (dBm) at [q]. Throws [ArgumentError] for a non-finite
  /// query position.
  double predict(RoomPoint q) {
    if (!q.x.isFinite || !q.y.isFinite) {
      throw ArgumentError.value(q, 'q', 'must be finite');
    }
    final n = _vs.length;
    final d = List<double>.filled(n, 0);
    var exactSum = 0.0;
    var exactCount = 0;
    for (var i = 0; i < n; i++) {
      final dx = _xs[i] - q.x;
      final dy = _ys[i] - q.y;
      d[i] = math.sqrt(dx * dx + dy * dy);
      if (d[i] <= exactMatchM) {
        exactSum += _vs[i];
        exactCount++;
      }
    }
    if (exactCount > 0) return exactSum / exactCount;

    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) {
        final c = d[a].compareTo(d[b]);
        return c != 0 ? c : a.compareTo(b); // deterministic ties
      });
    final k = math.min(config.maxNeighbours, n);
    var num = 0.0;
    var den = 0.0;
    for (var j = 0; j < k; j++) {
      final i = order[j];
      final w = 1 / math.pow(d[i], config.power);
      num += w * _vs[i];
      den += w;
    }
    return num / den;
  }
}
