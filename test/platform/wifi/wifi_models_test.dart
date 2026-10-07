import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/platform/wifi/wifi_models.dart';

void main() {
  group('WifiBand', () {
    test('maps frequencies to bands', () {
      expect(WifiBand.fromFrequency(2412), WifiBand.ghz2_4);
      expect(WifiBand.fromFrequency(2484), WifiBand.ghz2_4);
      expect(WifiBand.fromFrequency(5180), WifiBand.ghz5);
      expect(WifiBand.fromFrequency(5825), WifiBand.ghz5);
      expect(WifiBand.fromFrequency(5955), WifiBand.ghz6);
      expect(WifiBand.fromFrequency(null), isNull);
      expect(WifiBand.fromFrequency(900), isNull);
    });
  });

  group('WifiSecurity.parse', () {
    const cases = {
      '[WPA2-PSK-CCMP][RSN-PSK-CCMP][ESS]': WifiSecurity.wpa2,
      '[RSN-SAE-CCMP][ESS]': WifiSecurity.wpa3,
      '[RSN-PSK+SAE-CCMP][ESS]': WifiSecurity.wpa2Wpa3,
      '[WPA2-EAP-CCMP][RSN-EAP-CCMP][ESS]': WifiSecurity.enterprise,
      '[WPA-PSK-TKIP][ESS]': WifiSecurity.wpa,
      '[WEP][ESS]': WifiSecurity.wep,
      '[RSN-OWE-CCMP][ESS]': WifiSecurity.owe,
      '[ESS]': WifiSecurity.open,
      '': WifiSecurity.open,
    };
    cases.forEach((caps, expected) {
      test('"$caps" -> ${expected.name}', () {
        expect(WifiSecurity.parse(caps), expected);
      });
    });
    test('null is unknown', () {
      expect(WifiSecurity.parse(null), WifiSecurity.unknown);
    });
  });

  group('ScannedAccessPoint.fromMap', () {
    test('parses a complete entry', () {
      final ap = ScannedAccessPoint.fromMap({
        'ssid': 'Lab',
        'bssid': 'AA:BB:CC:DD:EE:01',
        'rssi': -58,
        'frequencyMhz': 5180,
        'capabilities': '[RSN-PSK-CCMP][ESS]',
        'ageMs': 1200,
      });
      expect(ap.ssid, 'Lab');
      expect(ap.bssid, 'aa:bb:cc:dd:ee:01');
      expect(ap.rssiDbm, -58);
      expect(ap.band, WifiBand.ghz5);
      expect(ap.security, WifiSecurity.wpa2);
      expect(ap.age, const Duration(milliseconds: 1200));
      expect(ap.canBeTarget, isTrue);
    });

    test('missing or malformed values become null, never invented', () {
      final ap = ScannedAccessPoint.fromMap({
        'ssid': '',
        'bssid': '02:00:00:00:00:00',
        'rssi': 'n/a',
      });
      expect(ap.ssid, isNull);
      expect(ap.bssid, isNull);
      expect(ap.rssiDbm, isNull);
      expect(ap.frequencyMhz, isNull);
      expect(ap.age, isNull);
      expect(ap.security, WifiSecurity.unknown);
      expect(ap.canBeTarget, isFalse);
    });
  });

  group('ConnectedWifiInfo.fromMap', () {
    final t = DateTime.utc(2026, 10, 7);

    test('not connected', () {
      expect(ConnectedWifiInfo.fromMap(null, receivedAt: t), isNull);
      expect(
        ConnectedWifiInfo.fromMap({'connected': false}, receivedAt: t),
        isNull,
      );
    });

    test('parses a connected observation', () {
      final info = ConnectedWifiInfo.fromMap({
        'ssid': 'Lab',
        'bssid': 'aa:bb:cc:dd:ee:01',
        'rssi': -61,
        'frequencyMhz': 2437,
        'linkSpeedMbps': 72,
        'source': 'networkCallback',
        'sequence': 4,
        'elapsedRealtimeMs': 123456,
      }, receivedAt: t)!;
      expect(info.ssid, 'Lab');
      expect(info.rssiDbm, -61);
      expect(info.band, WifiBand.ghz2_4);
      expect(info.source, ConnectedInfoSource.networkCallback);
      expect(info.sequence, 4);
      expect(info.receivedAt, t);
    });

    test('redacted identity and missing RSSI stay unavailable', () {
      final info = ConnectedWifiInfo.fromMap({
        'bssid': '02:00:00:00:00:00',
        'rssi': null,
      }, receivedAt: t)!;
      expect(info.bssid, isNull);
      expect(info.ssid, isNull);
      expect(info.rssiDbm, isNull);
      expect(info.source, ConnectedInfoSource.unknown);
    });
  });

  test('WifiEnvironment.fromMap tolerates missing fields', () {
    final env = WifiEnvironment.fromMap({'sdkInt': 33, 'wifiEnabled': true});
    expect(env.sdkInt, 33);
    expect(env.wifiEnabled, isTrue);
    expect(env.locationEnabled, isFalse);
    expect(env.scanThrottleEnabled, isNull);
    expect(env.fineLocationGranted, isFalse);
    expect(env.requiresNearbyWifiPermission, isTrue);
  });
}
