import '../interpolation/idw.dart';
import '../model/measurement.dart';
import 'error_metrics.dart';

enum LoocvMode {
  /// Remove one point at a time; predict it from all others.
  ///
  /// Caveat: if the same location was measured more than once, the remaining
  /// duplicate sits at distance zero and predicts the removed point almost
  /// perfectly, so the error is optimistic.
  leaveOnePoint,

  /// Remove every point at the evaluated point's location (within the
  /// location tolerance) before predicting it. Avoids the duplicate bias
  /// above and is the recommended mode when repeats exist.
  leaveOneLocation,
}

/// One held-out prediction.
final class LoocvPrediction {
  const LoocvPrediction({
    required this.point,
    required this.predictedDbm,
    required this.trainingCount,
  });

  final MeasuredPoint point;
  final double predictedDbm;

  /// Number of points the prediction was made from.
  final int trainingCount;

  double get actualDbm => point.rssiDbm;

  /// predicted - actual, in dB.
  double get errorDb => predictedDbm - point.rssiDbm;
}

sealed class LoocvOutcome {
  const LoocvOutcome();
}

final class LoocvInsufficientData extends LoocvOutcome {
  const LoocvInsufficientData({
    required this.availablePoints,
    required this.distinctLocations,
    required this.reason,
  });

  final int availablePoints;
  final int distinctLocations;
  final String reason;
}

final class LoocvResult extends LoocvOutcome {
  const LoocvResult({
    required this.mode,
    required this.config,
    required this.predictions,
    required this.rmseDb,
    required this.maeDb,
  });

  final LoocvMode mode;
  final IdwConfig config;
  final List<LoocvPrediction> predictions;
  final double rmseDb;
  final double maeDb;

  /// Number of held-out predictions.
  int get sampleCount => predictions.length;
}

/// Leave-one-out cross-validation of IDW on MEASURED points.
///
/// For each point, the point itself (and, in [LoocvMode.leaveOneLocation],
/// every point at its location) is removed and the value is predicted from
/// the rest. A point's own value is never used to predict itself.
///
/// Needs at least two points at two distinct locations.
LoocvOutcome leaveOneOutCrossValidation(
  List<MeasuredPoint> points,
  IdwConfig config, {
  LoocvMode mode = LoocvMode.leaveOnePoint,
  double locationToleranceM = 0.01,
}) {
  if (!locationToleranceM.isFinite || locationToleranceM < 0) {
    throw ArgumentError.value(locationToleranceM, 'locationToleranceM');
  }
  bool sameLocation(MeasuredPoint a, MeasuredPoint b) =>
      a.position.distanceTo(b.position) <= locationToleranceM;

  final distinct = <MeasuredPoint>[];
  for (final p in points) {
    if (!distinct.any((d) => sameLocation(d, p))) distinct.add(p);
  }
  if (points.length < 2 || distinct.length < 2) {
    return LoocvInsufficientData(
      availablePoints: points.length,
      distinctLocations: distinct.length,
      reason:
          'Cross-validation needs at least 2 measured points at 2 '
          'different locations.',
    );
  }

  final predictions = <LoocvPrediction>[];
  for (var i = 0; i < points.length; i++) {
    final held = points[i];
    final training = <MeasuredPoint>[
      for (var j = 0; j < points.length; j++)
        if (j != i &&
            !(mode == LoocvMode.leaveOneLocation &&
                sameLocation(points[j], held)))
          points[j],
    ];
    final predicted = IdwInterpolator(training, config).predict(held.position);
    predictions.add(
      LoocvPrediction(
        point: held,
        predictedDbm: predicted,
        trainingCount: training.length,
      ),
    );
  }
  final errors = [for (final p in predictions) p.errorDb];
  return LoocvResult(
    mode: mode,
    config: config,
    predictions: List.unmodifiable(predictions),
    rmseDb: rmse(errors),
    maeDb: mae(errors),
  );
}
