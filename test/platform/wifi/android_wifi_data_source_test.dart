import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/platform/wifi/android_wifi_data_source.dart';
import 'package:rssi_mapper/platform/wifi/wifi_models.dart';
import 'package:rssi_mapper/platform/wifi/wifi_native_api.dart';

/// Hand-written fake of the native channel.
class FakeWifiNativeApi implements WifiNativeApi {
  Map<Object?, Object?> env = {
    'sdkInt': 34,
    'wifiEnabled': true,
    'locationEnabled': true,
    'scanThrottleEnabled': true,
    'fineLocationGranted': true,
  };

  /// What startScan returns; set [startScanError] to throw instead.
  bool startScanAccepted = true;
  PlatformException? startScanError;

  /// Broadcast emitted after an accepted scan: true/false, or null for none.
  bool? broadcastUpdated = true;

  List<Map<Object?, Object?>> results = [];
  Map<Object?, Object?>? connected;

  final scanController = StreamController<Map<Object?, Object?>>.broadcast();
  final connectedController =
      StreamController<Map<Object?, Object?>>.broadcast();
  int startScanCalls = 0;

  @override
  Future<Map<Object?, Object?>> environment() async => env;

  @override
  Future<bool> startScan() async {
    startScanCalls++;
    if (startScanError != null) throw startScanError!;
    if (startScanAccepted && broadcastUpdated != null) {
      final updated = broadcastUpdated!;
      scheduleMicrotask(() => scanController.add({'updated': updated}));
    }
    return startScanAccepted;
  }

  @override
  Future<List<Map<Object?, Object?>>> scanResults() async => results;

  @override
  Future<Map<Object?, Object?>?> connectedInfo() async => connected;

  @override
  Stream<Map<Object?, Object?>> scanEvents() => scanController.stream;

  @override
  Stream<Map<Object?, Object?>> connectedEvents() => connectedController.stream;

  @override
  Future<void> openSettings(String page) async {}
}

Map<Object?, Object?> _ap(String bssid, int rssi, {int ageMs = 500}) => {
  'ssid': 'Lab',
  'bssid': bssid,
  'rssi': rssi,
  'frequencyMhz': 5180,
  'capabilities': '[RSN-PSK-CCMP][ESS]',
  'ageMs': ageMs,
};

void main() {
  late FakeWifiNativeApi native;
  late AndroidWifiDataSource ds;
  final now = DateTime.utc(2026, 10, 7, 12);

  setUp(() {
    native = FakeWifiNativeApi();
    ds = AndroidWifiDataSource(native, clock: () => now);
  });

  group('scan', () {
    test('fresh results when Android reports updated results', () async {
      native.results = [
        _ap('aa:bb:cc:dd:ee:01', -50),
        _ap('aa:bb:cc:dd:ee:02', -70, ageMs: 600000), // old cache entry
      ];
      final out = await ds.scan();
      expect(out, isA<ScanCompleted>());
      final aps = (out as ScanCompleted).accessPoints;
      expect(out.completedAt, now);
      expect(aps, hasLength(2));
      expect(aps[0].seenInLatestScan, isTrue);
      expect(aps[1].seenInLatestScan, isFalse);
    });

    test('rejected request (throttling) never pretends to be new', () async {
      native
        ..startScanAccepted = false
        ..results = [_ap('aa:bb:cc:dd:ee:01', -50)];
      final out = await ds.scan();
      expect(out, isA<ScanNotPerformed>());
      out as ScanNotPerformed;
      expect(out.kind, ScanFailureKind.rejected);
      expect(out.cachedAccessPoints.single.seenInLatestScan, isFalse);
    });

    test('broadcast with updated=false is a failed scan', () async {
      native
        ..broadcastUpdated = false
        ..results = [_ap('aa:bb:cc:dd:ee:01', -50)];
      final out = await ds.scan() as ScanNotPerformed;
      expect(out.kind, ScanFailureKind.noNewResults);
      expect(out.cachedAccessPoints, hasLength(1));
      expect(out.cachedAccessPoints.every((a) => !a.seenInLatestScan), isTrue);
    });

    test('no broadcast within the timeout', () async {
      native.broadcastUpdated = null;
      final out = await ds.scan(
        timeout: const Duration(milliseconds: 50),
      ) as ScanNotPerformed;
      expect(out.kind, ScanFailureKind.timedOut);
    });

    test('permission errors are reported, not thrown', () async {
      native.startScanError = PlatformException(
        code: 'PERMISSION',
        message: 'denied',
      );
      final out = await ds.scan() as ScanNotPerformed;
      expect(out.kind, ScanFailureKind.permissionDenied);
    });

    test('other platform errors are reported', () async {
      native.startScanError = PlatformException(code: 'FAILED');
      final out = await ds.scan() as ScanNotPerformed;
      expect(out.kind, ScanFailureKind.platformError);
    });

    test('Wi-Fi off or location off blocks the scan', () async {
      native.env = {...native.env, 'wifiEnabled': false};
      final out = await ds.scan();
      expect(out, isA<ScanBlocked>());
      expect((out as ScanBlocked).wifiDisabled, isTrue);
      expect(native.startScanCalls, 0);

      native.env = {
        ...native.env,
        'wifiEnabled': true,
        'locationEnabled': false,
      };
      final out2 = await ds.scan() as ScanBlocked;
      expect(out2.locationOff, isTrue);
    });

    test('no networks is a valid, empty result', () async {
      final out = await ds.scan() as ScanCompleted;
      expect(out.accessPoints, isEmpty);
    });
  });

  group('connected network', () {
    test('connectedInfo parses or returns null', () async {
      expect(await ds.connectedInfo(), isNull);
      native.connected = {
        'ssid': 'Lab',
        'bssid': 'aa:bb:cc:dd:ee:01',
        'rssi': -61,
        'source': 'networkCallback',
      };
      final info = await ds.connectedInfo();
      expect(info!.rssiDbm, -61);
      expect(info.receivedAt, now);
    });

    test(
      'watchConnected maps disconnect to null and keeps BSSID changes',
      () async {
        final events = <ConnectedWifiInfo?>[];
        final sub = ds.watchConnected().listen(events.add);
        native.connectedController
          ..add({'bssid': 'aa:bb:cc:dd:ee:01', 'rssi': -60})
          ..add({'bssid': 'aa:bb:cc:dd:ee:02', 'rssi': -55}) // roamed
          ..add({'connected': false});
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(events, hasLength(3));
        expect(events[0]!.bssid, 'aa:bb:cc:dd:ee:01');
        expect(events[1]!.bssid, 'aa:bb:cc:dd:ee:02');
        expect(events[2], isNull);
      },
    );
  });
}
