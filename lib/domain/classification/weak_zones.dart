import '../interpolation/interpolation_grid.dart';
import '../model/measurement.dart';
import 'signal_classification.dart';

/// Weak-signal findings, keeping MEASURED and INTERPOLATED results apart:
/// a measured weak point is an observation; an interpolated weak region is
/// an estimate.
final class WeakZoneAnalysis {
  const WeakZoneAnalysis._({
    required this.thresholdDbm,
    required this.measuredWeakPoints,
    required this.interpolatedWeakCells,
    required this.cellsWithData,
  });

  final double thresholdDbm;

  /// Measured points strictly below the threshold.
  final List<MeasuredPoint> measuredWeakPoints;

  /// Interpolated cells strictly below the threshold (NO DATA cells excluded).
  final List<GridCell> interpolatedWeakCells;

  /// Number of grid cells that have data.
  final int cellsWithData;

  /// Fraction of the covered (non NO DATA) area estimated weak; null when no
  /// cell has data.
  double? get interpolatedWeakFraction =>
      cellsWithData == 0 ? null : interpolatedWeakCells.length / cellsWithData;
}

WeakZoneAnalysis analyseWeakZones({
  required List<MeasuredPoint> points,
  required InterpolatedGrid? grid,
  double thresholdDbm = defaultWeakThresholdDbm,
}) {
  if (!thresholdDbm.isFinite) {
    throw ArgumentError.value(thresholdDbm, 'thresholdDbm');
  }
  final weakCells = <GridCell>[];
  var withData = 0;
  for (final cell in grid?.cellsWithData ?? const <GridCell>[]) {
    withData++;
    if (isWeak(cell.rssiDbm, thresholdDbm: thresholdDbm)) weakCells.add(cell);
  }
  return WeakZoneAnalysis._(
    thresholdDbm: thresholdDbm,
    measuredWeakPoints: List.unmodifiable(
      points.where((p) => isWeak(p.rssiDbm, thresholdDbm: thresholdDbm)),
    ),
    interpolatedWeakCells: List.unmodifiable(weakCells),
    cellsWithData: withData,
  );
}
