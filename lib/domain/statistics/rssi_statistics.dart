import 'dart:math' as math;

import '../filtering/power_conversion.dart';
import '../model/measurement.dart';

/// Summary statistics over MEASURED points. Computed on demand, never stored.
///
/// Duplicate locations: every valid point contributes, including repeated
/// measurements at the same location (see [findDuplicateLocations]).
final class RssiStatistics {
  const RssiStatistics._({
    required this.count,
    required this.minDbm,
    required this.maxDbm,
    required this.meanDbm,
    required this.powerMeanDbm,
    required this.stdDevDb,
    required this.strongest,
    required this.weakest,
  });

  /// Returns null for an empty list: no statistics are invented.
  static RssiStatistics? of(List<MeasuredPoint> points) {
    if (points.isEmpty) return null;
    var minV = double.infinity;
    var maxV = double.negativeInfinity;
    var sum = 0.0;
    var sumMw = 0.0;
    for (final p in points) {
      minV = math.min(minV, p.rssiDbm);
      maxV = math.max(maxV, p.rssiDbm);
      sum += p.rssiDbm;
      sumMw += dbmToMw(p.rssiDbm);
    }
    final mean = sum / points.length;
    var sq = 0.0;
    for (final p in points) {
      sq += (p.rssiDbm - mean) * (p.rssiDbm - mean);
    }
    return RssiStatistics._(
      count: points.length,
      minDbm: minV,
      maxDbm: maxV,
      meanDbm: mean,
      powerMeanDbm: mwToDbm(sumMw / points.length),
      stdDevDb: points.length < 2 ? null : math.sqrt(sq / (points.length - 1)),
      strongest: List.unmodifiable(points.where((p) => p.rssiDbm == maxV)),
      weakest: List.unmodifiable(points.where((p) => p.rssiDbm == minV)),
    );
  }

  final int count;
  final double minDbm;
  final double maxDbm;

  /// Arithmetic mean of dBm values.
  final double meanDbm;

  /// Mean in linear power (mW) converted back to dBm. Always >= [meanDbm].
  final double powerMeanDbm;

  /// Sample standard deviation in dB; null for fewer than two points.
  final double? stdDevDb;

  /// All points sharing the maximum value (the strongest MEASURED points),
  /// in input order. Never empty.
  final List<MeasuredPoint> strongest;

  /// All points sharing the minimum value, in input order. Never empty.
  final List<MeasuredPoint> weakest;
}

/// Groups of indices whose positions lie within [toleranceM] of the group's
/// first point. Only groups with two or more points are returned.
///
/// Duplicates are reported, never removed: repeated measurements can be
/// intentional (e.g. repeatability studies).
List<List<int>> findDuplicateLocations(
  List<MeasuredPoint> points, {
  double toleranceM = 0.01,
}) {
  if (!toleranceM.isFinite || toleranceM < 0) {
    throw ArgumentError.value(toleranceM, 'toleranceM');
  }
  final assigned = List<bool>.filled(points.length, false);
  final groups = <List<int>>[];
  for (var i = 0; i < points.length; i++) {
    if (assigned[i]) continue;
    final group = [i];
    for (var j = i + 1; j < points.length; j++) {
      if (!assigned[j] &&
          points[i].position.distanceTo(points[j].position) <= toleranceM) {
        group.add(j);
        assigned[j] = true;
      }
    }
    if (group.length > 1) groups.add(group);
  }
  return groups;
}
