import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/domain/interpolation/idw.dart';
import 'package:rssi_mapper/domain/model/measurement.dart';
import 'package:rssi_mapper/domain/model/room.dart';

MeasuredPoint _p(double x, double y, double rssi) =>
    MeasuredPoint(position: RoomPoint(x, y), rssiDbm: rssi);

void main() {
  final pair = [_p(0, 0, -40), _p(2, 0, -60)];

  group('IdwConfig', () {
    test('defaults are p = 2 and 8 neighbours', () {
      final c = IdwConfig();
      expect(c.power, 2);
      expect(c.maxNeighbours, 8);
    });
    test('invalid configuration is rejected', () {
      expect(() => IdwConfig(power: 0), throwsArgumentError);
      expect(() => IdwConfig(power: -1), throwsArgumentError);
      expect(() => IdwConfig(power: double.nan), throwsArgumentError);
      expect(() => IdwConfig(maxNeighbours: 0), throwsArgumentError);
    });
  });

  test('no points is rejected', () {
    expect(() => IdwInterpolator([], IdwConfig()), throwsArgumentError);
  });

  test('one point: every query returns that value', () {
    final idw = IdwInterpolator([_p(1, 1, -63)], IdwConfig());
    // w*v/w is not bit-exact in floating point.
    expect(idw.predict(const RoomPoint(4, 3)), closeTo(-63, 1e-9));
    expect(idw.predict(const RoomPoint(1, 1)), -63);
  });

  test('normal case, p = 2 (weights 9:1 at a quarter of the way)', () {
    final idw = IdwInterpolator(pair, IdwConfig());
    expect(idw.predict(const RoomPoint(1, 0)), closeTo(-50, 1e-12));
    expect(idw.predict(const RoomPoint(0.5, 0)), closeTo(-42, 1e-12));
  });

  test('different p changes the result', () {
    final p1 = IdwInterpolator(pair, IdwConfig(power: 1));
    final p3 = IdwInterpolator(pair, IdwConfig(power: 3));
    expect(p1.predict(const RoomPoint(0.5, 0)), closeTo(-45, 1e-12));
    // weights 1/0.125 : 1/3.375 = 27 : 1
    expect(p3.predict(const RoomPoint(0.5, 0)), closeTo(-40.7142857, 1e-6));
  });

  test('query exactly on a measured point returns it (zero distance)', () {
    final idw = IdwInterpolator(pair, IdwConfig());
    expect(idw.predict(const RoomPoint(0, 0)), -40);
    expect(idw.predict(const RoomPoint(2, 0)), -60);
  });

  test('duplicate positions: exact query returns their mean', () {
    final idw = IdwInterpolator([
      _p(1, 1, -40),
      _p(1, 1, -50),
      _p(3, 3, -70),
    ], IdwConfig());
    expect(idw.predict(const RoomPoint(1, 1)), closeTo(-45, 1e-12));
    final v = idw.predict(const RoomPoint(2, 1));
    expect(v.isFinite, isTrue);
  });

  test('neighbours limit: only the k nearest are used', () {
    final pts = [_p(0, 0, -40), _p(1, 0, -50), _p(10, 0, -90)];
    final k1 = IdwInterpolator(pts, IdwConfig(maxNeighbours: 1));
    expect(k1.predict(const RoomPoint(0.2, 0)), -40);
    final k2 = IdwInterpolator(pts, IdwConfig(maxNeighbours: 2));
    final all = IdwInterpolator(pts, IdwConfig(maxNeighbours: 3));
    final q = const RoomPoint(0.5, 0);
    expect(k2.predict(q), closeTo(-45, 1e-12));
    expect(all.predict(q), lessThan(-45));
  });

  test('neighbours greater than points uses all points', () {
    final idw = IdwInterpolator(pair, IdwConfig(maxNeighbours: 50));
    expect(idw.predict(const RoomPoint(1, 0)), closeTo(-50, 1e-12));
  });

  test('many points: prediction never leaves [measured min, measured max]', () {
    final rnd = math.Random(42);
    final pts = [
      for (var i = 0; i < 60; i++)
        _p(
          rnd.nextDouble() * 8,
          rnd.nextDouble() * 6,
          -90 + rnd.nextDouble() * 55,
        ),
    ];
    final lo = pts.map((p) => p.rssiDbm).reduce(math.min);
    final hi = pts.map((p) => p.rssiDbm).reduce(math.max);
    for (final cfg in [IdwConfig(), IdwConfig(power: 1, maxNeighbours: 3)]) {
      final idw = IdwInterpolator(pts, cfg);
      for (var i = 0; i < 500; i++) {
        final v = idw.predict(
          RoomPoint(rnd.nextDouble() * 8, rnd.nextDouble() * 6),
        );
        expect(v, inInclusiveRange(lo, hi));
      }
    }
  });

  test('non-finite query is rejected', () {
    final idw = IdwInterpolator(pair, IdwConfig());
    expect(
      () => idw.predict(const RoomPoint(double.nan, 0)),
      throwsArgumentError,
    );
  });
}
