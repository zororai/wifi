import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/domain/evaluation/error_metrics.dart';
import 'package:rssi_mapper/domain/evaluation/loocv.dart';
import 'package:rssi_mapper/domain/interpolation/idw.dart';
import 'package:rssi_mapper/domain/model/measurement.dart';
import 'package:rssi_mapper/domain/model/room.dart';

MeasuredPoint _p(double x, double y, double rssi) =>
    MeasuredPoint(position: RoomPoint(x, y), rssiDbm: rssi);

void main() {
  group('error metrics', () {
    test('RMSE and MAE of known errors', () {
      expect(rmse([3, -4]), closeTo(math.sqrt(12.5), 1e-12));
      expect(mae([3, -4]), 3.5);
      expect(rmse([0, 0, 0]), 0);
    });
    test('empty or non-finite input throws', () {
      expect(() => rmse([]), throwsArgumentError);
      expect(() => mae([]), throwsArgumentError);
      expect(() => mae([double.nan]), throwsArgumentError);
    });
  });

  group('leaveOneOutCrossValidation', () {
    // Three points on a line, p = 2:
    //  hold A(0): from B(d=1), C(d=2): (-50*1 + -60*0.25)/1.25 = -52 -> err -12
    //  hold B(1): from A, C (d=1 each): -50                       -> err 0
    //  hold C(2): from B(d=1), A(d=2): (-50*1 + -40*0.25)/1.25 = -48 -> err +12
    final line = [_p(0, 0, -40), _p(1, 0, -50), _p(2, 0, -60)];

    test('known small dataset', () {
      final r = leaveOneOutCrossValidation(line, IdwConfig()) as LoocvResult;
      expect(r.sampleCount, 3);
      expect(r.predictions.map((p) => p.predictedDbm), [
        closeTo(-52, 1e-12),
        closeTo(-50, 1e-12),
        closeTo(-48, 1e-12),
      ]);
      expect(r.predictions.map((p) => p.errorDb), [
        closeTo(-12, 1e-12),
        closeTo(0, 1e-12),
        closeTo(12, 1e-12),
      ]);
      expect(r.rmseDb, closeTo(math.sqrt(96), 1e-12));
      expect(r.maeDb, closeTo(8, 1e-12));
      expect(r.predictions.every((p) => p.trainingCount == 2), isTrue);
    });

    test("a point's own value is never used to predict itself", () {
      // If the held-out point leaked into training, the exact-point rule
      // would return its own value and every error would be 0.
      final r = leaveOneOutCrossValidation(line, IdwConfig()) as LoocvResult;
      expect(r.rmseDb, greaterThan(0));
      expect(r.predictions.first.predictedDbm, isNot(-40));
    });

    test('insufficient data', () {
      expect(
        leaveOneOutCrossValidation([], IdwConfig()),
        isA<LoocvInsufficientData>(),
      );
      expect(
        leaveOneOutCrossValidation([_p(1, 1, -50)], IdwConfig()),
        isA<LoocvInsufficientData>(),
      );
      final sameSpot = leaveOneOutCrossValidation([
        _p(1, 1, -50),
        _p(1, 1, -52),
      ], IdwConfig());
      expect(sameSpot, isA<LoocvInsufficientData>());
      expect((sameSpot as LoocvInsufficientData).distinctLocations, 1);
    });

    test('two points is the minimum', () {
      final r = leaveOneOutCrossValidation([
        _p(0, 0, -40),
        _p(1, 0, -60),
      ], IdwConfig()) as LoocvResult;
      expect(r.rmseDb, 20);
      expect(r.maeDb, 20);
    });

    test('exact-point handling: duplicates bias leave-one-point only', () {
      final pts = [...line, _p(0, 0, -42)]; // repeat at A
      final point = leaveOneOutCrossValidation(pts, IdwConfig()) as LoocvResult;
      final location = leaveOneOutCrossValidation(
        pts,
        IdwConfig(),
        mode: LoocvMode.leaveOneLocation,
      ) as LoocvResult;
      // Leave-one-point: A (-40) is predicted by its duplicate (-42).
      expect(point.predictions.first.predictedDbm, -42);
      // Leave-one-location: both A readings removed, predicted from B and C.
      expect(location.predictions.first.predictedDbm, closeTo(-52, 1e-12));
      expect(location.predictions.first.trainingCount, 2);
      expect(location.rmseDb, greaterThan(point.rmseDb));
    });

    test('different IDW settings give different errors', () {
      final grid = [
        for (var x = 0; x < 4; x++)
          for (var y = 0; y < 3; y++)
            _p(
              x.toDouble(),
              y.toDouble(),
              -40 - 6.0 * x - 3.0 * y + (x * y % 3),
            ),
      ];
      final a = leaveOneOutCrossValidation(grid, IdwConfig()) as LoocvResult;
      final b = leaveOneOutCrossValidation(
        grid,
        IdwConfig(power: 1, maxNeighbours: 2),
      ) as LoocvResult;
      expect(a.sampleCount, 12);
      expect(a.rmseDb, isNot(closeTo(b.rmseDb, 1e-9)));
      expect(a.rmseDb, greaterThanOrEqualTo(a.maeDb));
    });

    test('invalid tolerance throws', () {
      expect(
        () => leaveOneOutCrossValidation(
          line,
          IdwConfig(),
          locationToleranceM: -1,
        ),
        throwsArgumentError,
      );
    });
  });
}
