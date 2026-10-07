import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/domain/classification/weak_zones.dart';
import 'package:rssi_mapper/domain/interpolation/idw.dart';
import 'package:rssi_mapper/domain/interpolation/interpolation_grid.dart';
import 'package:rssi_mapper/domain/model/measurement.dart';
import 'package:rssi_mapper/domain/model/room.dart';

MeasuredPoint _p(double x, double y, double rssi) =>
    MeasuredPoint(position: RoomPoint(x, y), rssiDbm: rssi);

void main() {
  final room = Room(widthM: 4, lengthM: 2, gridSpacingM: 1);

  group('GridSpec', () {
    test('rejects empty and oversized grids', () {
      expect(() => GridSpec(0, 1), throwsArgumentError);
      expect(() => GridSpec(300, 300), throwsArgumentError);
    });
    test('forRoom uses the target cell size', () {
      final s = GridSpec.forRoom(room, targetCellM: 0.5);
      expect(s.columns, 8);
      expect(s.rows, 4);
    });
    test('forRoom stays within the cell budget for large rooms', () {
      final big = Room(widthM: 100, lengthM: 80, gridSpacingM: 1);
      final s = GridSpec.forRoom(big, targetCellM: 0.05);
      expect(s.cellCount, lessThanOrEqualTo(GridSpec.defaultMaxCells));
      expect(s.columns / s.rows, closeTo(100 / 80, 0.05));
    });
  });

  group('computeIdwGrid', () {
    test('NO DATA masking: cells beyond the distance stay empty', () {
      final g = computeIdwGrid(
        points: [_p(0.5, 0.5, -50)],
        room: room,
        spec: GridSpec(4, 2),
        config: IdwConfig(),
        noDataDistanceM: 1.0,
      );
      // Centres: x = 0.5,1.5,2.5,3.5 ; y = 0.5,1.5
      expect(g.valueAt(0, 0), -50);
      expect(g.valueAt(1, 0), -50); // distance 1.0 (inclusive)
      expect(g.valueAt(0, 1), -50); // distance 1.0
      expect(g.valueAt(1, 1), isNull); // distance 1.414
      expect(g.valueAt(2, 0), isNull); // distance 2.0
      expect(g.valueAt(3, 1), isNull);
      expect(g.cellsWithData, hasLength(3));
    });

    test('without masking every cell has a value', () {
      final g = computeIdwGrid(
        points: [_p(0.5, 0.5, -50), _p(3.5, 1.5, -80)],
        room: room,
        spec: GridSpec(4, 2),
        config: IdwConfig(),
        noDataDistanceM: null,
      );
      expect(g.values.every((v) => v != null), isTrue);
      expect(g.valueAt(0, 0), -50);
      expect(g.valueAt(3, 1), -80);
    });

    test('predicted maximum never exceeds the strongest measured value', () {
      final pts = [_p(0.2, 0.3, -48), _p(2.1, 1.7, -66), _p(3.8, 0.4, -79)];
      final g = computeIdwGrid(
        points: pts,
        room: room,
        spec: GridSpec.forRoom(room, targetCellM: 0.1),
        config: IdwConfig(),
        noDataDistanceM: 1.5,
      );
      final max = g.predictedMaximum!;
      expect(max.rssiDbm, lessThanOrEqualTo(-48));
    });

    test('no cell with data gives no predicted maximum', () {
      final g = computeIdwGrid(
        points: [_p(0, 0, -50)],
        room: room,
        spec: GridSpec(4, 2),
        config: IdwConfig(),
        noDataDistanceM: 0.1,
      );
      expect(g.predictedMaximum, isNull);
    });

    test('invalid inputs are rejected', () {
      expect(
        () => computeIdwGrid(
          points: [],
          room: room,
          spec: GridSpec(2, 2),
          config: IdwConfig(),
          noDataDistanceM: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => computeIdwGrid(
          points: [_p(1, 1, -50)],
          room: room,
          spec: GridSpec(2, 2),
          config: IdwConfig(),
          noDataDistanceM: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('analyseWeakZones', () {
    test('separates measured weak points from interpolated weak cells', () {
      final pts = [_p(0.5, 0.5, -70), _p(3.5, 1.5, -80), _p(2, 1, -75)];
      final g = computeIdwGrid(
        points: pts,
        room: room,
        spec: GridSpec(4, 2),
        config: IdwConfig(),
        noDataDistanceM: null,
      );
      final a = analyseWeakZones(points: pts, grid: g);
      expect(a.thresholdDbm, -75);
      expect(a.measuredWeakPoints.map((p) => p.rssiDbm), [-80]);
      expect(a.interpolatedWeakCells, isNotEmpty);
      expect(a.interpolatedWeakCells.every((c) => c.rssiDbm < -75), isTrue);
      expect(a.cellsWithData, 8);
      expect(a.interpolatedWeakFraction, inInclusiveRange(0, 1));
    });

    test('without a grid only measured results exist', () {
      final a = analyseWeakZones(points: [_p(0, 0, -90)], grid: null);
      expect(a.measuredWeakPoints, hasLength(1));
      expect(a.interpolatedWeakCells, isEmpty);
      expect(a.interpolatedWeakFraction, isNull);
    });
  });
}
