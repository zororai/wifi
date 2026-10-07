import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/domain/filtering/power_conversion.dart';
import 'package:rssi_mapper/domain/filtering/rssi_filter.dart';

void main() {
  group('median', () {
    test('empty returns null (no invented value)', () {
      expect(median([]), isNull);
    });
    test('one sample', () => expect(median([-55]), -55));
    test('odd count', () => expect(median([-40, -60, -50]), -50));
    test('even count averages the two middle values', () {
      expect(median([-30, -60, -40, -50]), -45);
    });
    test('does not reorder the input', () {
      final v = [-40.0, -60.0, -50.0];
      median(v);
      expect(v, [-40, -60, -50]);
    });
    test('invalid values throw', () {
      expect(() => median([-50, double.nan]), throwsArgumentError);
      expect(() => median([double.infinity]), throwsArgumentError);
    });
  });

  group('mean', () {
    test('empty returns null', () => expect(mean([]), isNull));
    test('one sample', () => expect(mean([-55]), -55));
    test('odd count', () => expect(mean([-40, -50, -60]), -50));
    test('even count', () => expect(mean([-30, -40, -50, -60]), -45));
    test('invalid values throw', () {
      expect(() => mean([double.negativeInfinity]), throwsArgumentError);
    });
  });

  group('dBm <-> mW', () {
    test('dBm to mW', () {
      expect(dbmToMw(0), closeTo(1, 1e-12));
      expect(dbmToMw(10), closeTo(10, 1e-12));
      expect(dbmToMw(-30), closeTo(0.001, 1e-15));
      expect(dbmToMw(-50), closeTo(1e-5, 1e-17));
    });
    test('mW to dBm', () {
      expect(mwToDbm(1), closeTo(0, 1e-12));
      expect(mwToDbm(100), closeTo(20, 1e-12));
      expect(mwToDbm(0.001), closeTo(-30, 1e-12));
    });
    test('round trip', () {
      for (final d in [-90.0, -67.5, -50.0, -30.25, 0.0]) {
        expect(mwToDbm(dbmToMw(d)), closeTo(d, 1e-9));
      }
    });
    test('invalid inputs throw', () {
      expect(() => mwToDbm(0), throwsArgumentError);
      expect(() => mwToDbm(-1), throwsArgumentError);
      expect(() => mwToDbm(double.nan), throwsArgumentError);
      expect(() => dbmToMw(double.nan), throwsArgumentError);
    });
  });

  group('combineRssi', () {
    test('empty returns null in both domains', () {
      for (final d in AveragingDomain.values) {
        for (final m in FilterMethod.values) {
          expect(combineRssi([], method: m, domain: d), isNull);
        }
      }
    });

    test('mean in dBm vs mean in mW are different choices', () {
      final dbm = combineRssi(
        [-40, -50],
        method: FilterMethod.mean,
        domain: AveragingDomain.dbm,
      );
      final mw = combineRssi(
        [-40, -50],
        method: FilterMethod.mean,
        domain: AveragingDomain.linearMw,
      );
      expect(dbm, -45);
      // 10*log10((1e-4 + 1e-5) / 2) = -42.596...
      expect(mw, closeTo(-42.5964, 1e-4));
      expect(mw! > dbm!, isTrue, reason: 'power mean >= dBm mean');
    });

    test('odd-count median is identical in both domains', () {
      final a = combineRssi(
        [-60, -40, -50],
        method: FilterMethod.median,
        domain: AveragingDomain.dbm,
      );
      final b = combineRssi(
        [-60, -40, -50],
        method: FilterMethod.median,
        domain: AveragingDomain.linearMw,
      );
      expect(a, -50);
      expect(b, closeTo(-50, 1e-9));
    });

    test('even-count median differs between domains', () {
      final a = combineRssi(
        [-40, -50],
        method: FilterMethod.median,
        domain: AveragingDomain.dbm,
      );
      final b = combineRssi(
        [-40, -50],
        method: FilterMethod.median,
        domain: AveragingDomain.linearMw,
      );
      expect(a, -45);
      expect(b, closeTo(-42.5964, 1e-4));
    });

    test('identical samples give that value in every configuration', () {
      for (final d in AveragingDomain.values) {
        for (final m in FilterMethod.values) {
          expect(
            combineRssi([-63, -63, -63], method: m, domain: d),
            closeTo(-63, 1e-9),
          );
        }
      }
    });
  });
}
