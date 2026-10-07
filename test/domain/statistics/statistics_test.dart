import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/domain/model/measurement.dart';
import 'package:rssi_mapper/domain/model/room.dart';
import 'package:rssi_mapper/domain/statistics/rssi_statistics.dart';

MeasuredPoint _p(double x, double y, double rssi, [String? id]) =>
    MeasuredPoint(position: RoomPoint(x, y), rssiDbm: rssi, id: id);

void main() {
  test('empty set returns null', () {
    expect(RssiStatistics.of([]), isNull);
  });

  test('single point', () {
    final s = RssiStatistics.of([_p(1, 1, -55)])!;
    expect(s.count, 1);
    expect(s.minDbm, -55);
    expect(s.maxDbm, -55);
    expect(s.meanDbm, -55);
    expect(s.powerMeanDbm, closeTo(-55, 1e-9));
    expect(s.stdDevDb, isNull);
    expect(s.strongest.single.rssiDbm, -55);
    expect(s.weakest.single.rssiDbm, -55);
  });

  test('min, max, mean, strongest and weakest measured points', () {
    final pts = [
      _p(0, 0, -60, 'a'),
      _p(1, 0, -40, 'b'),
      _p(2, 0, -50, 'c'),
      _p(3, 0, -70, 'd'),
    ];
    final s = RssiStatistics.of(pts)!;
    expect(s.count, 4);
    expect(s.minDbm, -70);
    expect(s.maxDbm, -40);
    expect(s.meanDbm, -55);
    expect(s.strongest.single.id, 'b');
    expect(s.weakest.single.id, 'd');
    expect(s.stdDevDb, closeTo(12.9099, 1e-4));
    expect(s.powerMeanDbm, greaterThanOrEqualTo(s.meanDbm));
  });

  test('ties: every point sharing the extreme value is reported', () {
    final s = RssiStatistics.of([
      _p(0, 0, -40, 'a'),
      _p(1, 0, -50, 'b'),
      _p(2, 0, -40, 'c'),
    ])!;
    expect(s.strongest.map((p) => p.id), ['a', 'c']);
  });

  test('duplicate locations are kept and all contribute', () {
    final pts = [_p(1, 1, -40), _p(1, 1, -50), _p(2, 2, -60)];
    final s = RssiStatistics.of(pts)!;
    expect(s.count, 3);
    expect(s.meanDbm, -50);
  });

  group('findDuplicateLocations', () {
    test('groups points within tolerance and reports only groups', () {
      final pts = [
        _p(1, 1, -40),
        _p(3, 3, -50),
        _p(1.005, 1, -45),
        _p(5, 5, -60),
        _p(3, 3, -52),
      ];
      expect(findDuplicateLocations(pts), [
        [0, 2],
        [1, 4],
      ]);
    });
    test('no duplicates', () {
      expect(findDuplicateLocations([_p(0, 0, -1), _p(1, 1, -2)]), isEmpty);
    });
    test('invalid tolerance throws', () {
      expect(
        () => findDuplicateLocations([], toleranceM: -1),
        throwsArgumentError,
      );
    });
  });

  test('MeasuredPoint rejects non-finite RSSI', () {
    expect(
      () => MeasuredPoint(position: const RoomPoint(0, 0), rssiDbm: double.nan),
      throwsArgumentError,
    );
  });
}
