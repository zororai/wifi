import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/domain/filtering/rssi_filter.dart';
import 'package:rssi_mapper/domain/filtering/sample_validation.dart';
import 'package:rssi_mapper/domain/model/measurement.dart';
import 'package:rssi_mapper/domain/model/network.dart';

final _t0 = DateTime.utc(2026, 10, 7, 12);
const _target = 'aa:bb:cc:dd:ee:01';
const _other = 'aa:bb:cc:dd:ee:02';

RssiSample _s(String? bssid, int? rssi) =>
    RssiSample(timestamp: _t0, bssid: bssid, rssiDbm: rssi, ssid: 'Lab');

void main() {
  final target = TargetNetwork(ssid: 'Lab', bssid: _target);

  group('TargetNetwork / BSSID', () {
    test('BSSID is normalised to lower case', () {
      expect(
        TargetNetwork(ssid: 'x', bssid: 'AA:BB:CC:DD:EE:01').bssid,
        _target,
      );
    });
    test('redacted or malformed BSSID is rejected', () {
      expect(
        () => TargetNetwork(ssid: 'x', bssid: redactedBssid),
        throwsArgumentError,
      );
      expect(
        () => TargetNetwork(ssid: 'x', bssid: 'not-a-mac'),
        throwsArgumentError,
      );
    });
    test('normalizeBssid', () {
      expect(normalizeBssid(null), isNull);
      expect(normalizeBssid(redactedBssid), isNull);
      expect(normalizeBssid(' AA:BB:CC:DD:EE:01 '), _target);
    });
  });

  group('checkSample', () {
    test(
      'valid sample',
      () => expect(checkSample(_s(_target, -55), target), isNull),
    );
    test('BSSID comparison ignores case', () {
      expect(checkSample(_s(_target.toUpperCase(), -55), target), isNull);
    });
    test('other access point', () {
      expect(
        checkSample(_s(_other, -40), target),
        SampleRejection.bssidMismatch,
      );
    });
    test('missing / redacted BSSID', () {
      expect(
        checkSample(_s(null, -40), target),
        SampleRejection.bssidUnavailable,
      );
      expect(
        checkSample(_s(redactedBssid, -40), target),
        SampleRejection.bssidUnavailable,
      );
    });
    test('RSSI unavailable is never turned into a number', () {
      expect(
        checkSample(_s(_target, null), target),
        SampleRejection.rssiUnavailable,
      );
    });
    test('implausible RSSI', () {
      expect(
        checkSample(_s(_target, -127), target),
        SampleRejection.rssiOutOfRange,
      );
      expect(
        checkSample(_s(_target, 0), target),
        SampleRejection.rssiOutOfRange,
      );
      expect(
        checkSample(_s(_target, 5), target),
        SampleRejection.rssiOutOfRange,
      );
    });
  });

  group('aggregateSamples', () {
    final samples = [
      _s(_target, -50),
      _s(_target, -52),
      _s(_other, -30), // different AP: must not contribute
      _s(_target, -54),
      _s(_target, null),
      _s(_target, -56),
      _s(_target, -58),
      _s(_target, -60),
    ];

    test('filters only valid target samples and keeps raw data', () {
      final r = aggregateSamples(
        samples,
        target: target,
        method: FilterMethod.median,
        domain: AveragingDomain.dbm,
        minValidSamples: 5,
      );
      expect(r, isA<AggregationSucceeded>());
      r as AggregationSucceeded;
      expect(r.accepted, hasLength(6));
      expect(r.rejected, hasLength(2));
      expect(
        r.rejected.map((e) => e.reason),
        containsAll([
          SampleRejection.bssidMismatch,
          SampleRejection.rssiUnavailable,
        ]),
      );
      // median of -50,-52,-54,-56,-58,-60
      expect(r.rssiDbm, -55);
    });

    test('fails when too few valid samples remain', () {
      final r = aggregateSamples(
        samples,
        target: target,
        method: FilterMethod.mean,
        domain: AveragingDomain.dbm,
        minValidSamples: 7,
      );
      expect(r, isA<AggregationFailed>());
      expect((r as AggregationFailed).requiredValidSamples, 7);
      expect(r.accepted, hasLength(6));
    });

    test('no samples fails', () {
      final r = aggregateSamples(
        [],
        target: target,
        method: FilterMethod.median,
        domain: AveragingDomain.dbm,
        minValidSamples: 1,
      );
      expect(r, isA<AggregationFailed>());
    });

    test('invalid minValidSamples throws', () {
      expect(
        () => aggregateSamples(
          samples,
          target: target,
          method: FilterMethod.median,
          domain: AveragingDomain.dbm,
          minValidSamples: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
