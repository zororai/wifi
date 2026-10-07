import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/features/scanner/scanner_controller.dart';
import 'package:rssi_mapper/features/scanner/scanner_screen.dart';
import 'package:rssi_mapper/platform/wifi/fake_wifi_data_source.dart';
import 'package:rssi_mapper/platform/wifi/wifi_models.dart';
import 'package:rssi_mapper/platform/wifi/wifi_permissions.dart';
import 'package:rssi_mapper/platform/wifi/wifi_providers.dart';

class FakePermissionService implements WifiPermissionService {
  FakePermissionService(this.status);
  WifiPermissionStatus status;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<WifiPermissionStatus> check({required int sdkInt}) async => status;

  @override
  Future<WifiPermissionStatus> request({required int sdkInt}) async {
    requests++;
    return status;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }
}

const _granted = WifiPermissionStatus(
  location: PermissionState.granted,
  nearbyWifi: PermissionState.granted,
);

const _env = WifiEnvironment(
  sdkInt: 34,
  wifiEnabled: true,
  locationEnabled: true,
  scanThrottleEnabled: true,
  fineLocationGranted: true,
);

ScannedAccessPoint _ap(String ssid, String bssid, int? rssi) =>
    ScannedAccessPoint(
      ssid: ssid,
      bssid: bssid,
      rssiDbm: rssi,
      frequencyMhz: 5180,
      security: WifiSecurity.wpa2,
      age: const Duration(seconds: 1),
    );

Widget _app(FakeWifiDataSource wifi, FakePermissionService perms) =>
    ProviderScope(
      overrides: [
        wifiDataSourceProvider.overrideWithValue(wifi),
        wifiPermissionServiceProvider.overrideWithValue(perms),
      ],
      child: const MaterialApp(home: ScannerScreen()),
    );

void main() {
  testWidgets('explains and requests a missing location permission', (
    tester,
  ) async {
    final perms = FakePermissionService(
      const WifiPermissionStatus(
        location: PermissionState.denied,
        nearbyWifi: PermissionState.granted,
      ),
    );
    await tester.pumpWidget(_app(FakeWifiDataSource(environment: _env), perms));
    await tester.pumpAndSettle();

    expect(find.text('Location permission needed'), findsOneWidget);
    expect(find.textContaining('does not use GPS'), findsOneWidget);
    await tester.tap(find.text('Grant permission'));
    await tester.pumpAndSettle();
    expect(perms.requests, 1);
  });

  testWidgets('permanently denied permission points to app settings', (
    tester,
  ) async {
    final perms = FakePermissionService(
      const WifiPermissionStatus(
        location: PermissionState.permanentlyDenied,
        nearbyWifi: PermissionState.granted,
      ),
    );
    await tester.pumpWidget(_app(FakeWifiDataSource(environment: _env), perms));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open app settings'));
    expect(perms.settingsOpened, 1);
  });

  testWidgets('Wi-Fi off and location off are explained', (tester) async {
    final wifi = FakeWifiDataSource(
      environment: const WifiEnvironment(
        sdkInt: 34,
        wifiEnabled: false,
        locationEnabled: false,
        scanThrottleEnabled: null,
        fineLocationGranted: true,
      ),
    );
    await tester.pumpWidget(_app(wifi, FakePermissionService(_granted)));
    await tester.pumpAndSettle();

    expect(find.text('Wi-Fi is turned off'), findsOneWidget);
    expect(find.text('Location services are off'), findsOneWidget);
    await tester.tap(find.text('Open location settings'));
    expect(wifi.openedSettings, [WifiSettingsPage.location]);
  });

  testWidgets('shows the connected network with RSSI and class', (
    tester,
  ) async {
    final wifi = FakeWifiDataSource(
      environment: _env,
      connected: ConnectedWifiInfo(
        ssid: 'HomeNet',
        bssid: 'aa:bb:cc:dd:ee:01',
        rssiDbm: -58,
        frequencyMhz: 5180,
        linkSpeedMbps: 433,
        source: ConnectedInfoSource.networkCallback,
        receivedAt: DateTime.utc(2026),
      ),
    );
    await tester.pumpWidget(_app(wifi, FakePermissionService(_granted)));
    await tester.pumpAndSettle();

    expect(find.text('HomeNet'), findsOneWidget);
    expect(find.text('-58 dBm'), findsOneWidget);
    expect(find.text('Very good'), findsOneWidget);
    expect(find.textContaining('aa:bb:cc:dd:ee:01'), findsOneWidget);
  });

  testWidgets('not connected is stated, not hidden', (tester) async {
    await tester.pumpWidget(
      _app(
        FakeWifiDataSource(environment: _env),
        FakePermissionService(_granted),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Not connected to Wi-Fi'), findsOneWidget);
  });

  testWidgets('scan lists networks strongest first and flags shared names', (
    tester,
  ) async {
    final wifi = FakeWifiDataSource(
      environment: _env,
      scanOutcomes: [
        ScanCompleted([
          _ap('Office', 'aa:bb:cc:dd:ee:02', -72),
          _ap('Office', 'aa:bb:cc:dd:ee:03', -48),
          _ap('Guest', 'aa:bb:cc:dd:ee:04', null),
        ], completedAt: DateTime.utc(2026)),
      ],
    );
    await tester.pumpWidget(_app(wifi, FakePermissionService(_granted)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.textContaining('New scan completed: 3'), findsOneWidget);
    final rssiTexts = tester
        .widgetList<Text>(find.textContaining(RegExp(r'dBm$|RSSI n/a')))
        .map((t) => t.data)
        .toList();
    expect(rssiTexts, ['-48 dBm', '-72 dBm', 'RSSI n/a']);
    expect(
      find.textContaining('name shared by several access points'),
      findsNWidgets(2),
    );
  });

  testWidgets('throttled scan shows earlier results clearly labelled', (
    tester,
  ) async {
    final wifi = FakeWifiDataSource(
      environment: _env,
      scanOutcomes: [
        ScanNotPerformed(
          ScanFailureKind.rejected,
          cachedAccessPoints: [
            _ap(
              'Office',
              'aa:bb:cc:dd:ee:02',
              -60,
            ).copyWith(seenInLatestScan: false),
          ],
        ),
      ],
    );
    await tester.pumpWidget(_app(wifi, FakePermissionService(_granted)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.textContaining('scan throttling'), findsOneWidget);
    expect(find.textContaining('EARLIER results'), findsOneWidget);
    expect(find.textContaining('not in latest scan'), findsOneWidget);
  });

  testWidgets('selecting an access point stores SSID and BSSID', (
    tester,
  ) async {
    final wifi = FakeWifiDataSource(
      environment: _env,
      scanOutcomes: [
        ScanCompleted([
          _ap('Office', 'aa:bb:cc:dd:ee:03', -48),
        ], completedAt: DateTime.utc(2026)),
      ],
    );
    await tester.pumpWidget(_app(wifi, FakePermissionService(_granted)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    expect(find.textContaining('exact access point (BSSID)'), findsOneWidget);
    await tester.tap(find.text('Select as target'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ScannerScreen)),
    );
    final target = container.read(selectedTargetProvider)!;
    expect(target.ssid, 'Office');
    expect(target.bssid, 'aa:bb:cc:dd:ee:03');
  });
}
