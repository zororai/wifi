import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/platform/wifi/wifi_models.dart';
import 'package:rssi_mapper/platform/wifi/wifi_permissions.dart';
import 'package:rssi_mapper/platform/wifi/wifi_readiness.dart';

WifiEnvironment _env({
  int sdk = 34,
  bool wifi = true,
  bool location = true,
  bool fine = true,
}) => WifiEnvironment(
  sdkInt: sdk,
  wifiEnabled: wifi,
  locationEnabled: location,
  scanThrottleEnabled: null,
  fineLocationGranted: fine,
);

const _granted = WifiPermissionStatus(
  location: PermissionState.granted,
  nearbyWifi: PermissionState.granted,
);

void main() {
  test('everything in place is ready', () {
    final r = assessWifiReadiness(_env(), _granted);
    expect(r.isReady, isTrue);
  });

  test('missing location permission blocks', () {
    final r = assessWifiReadiness(
      _env(fine: false),
      const WifiPermissionStatus(
        location: PermissionState.denied,
        nearbyWifi: PermissionState.granted,
      ),
    );
    expect(r.blockers, [WifiBlocker.locationPermissionDenied]);
  });

  test('permanently denied is distinguished (needs Settings)', () {
    final r = assessWifiReadiness(
      _env(fine: false),
      const WifiPermissionStatus(
        location: PermissionState.permanentlyDenied,
        nearbyWifi: PermissionState.permanentlyDenied,
      ),
    );
    expect(r.blockers, [
      WifiBlocker.locationPermissionPermanentlyDenied,
      WifiBlocker.nearbyWifiPermissionPermanentlyDenied,
    ]);
  });

  test('approximate-only location is not enough', () {
    final r = assessWifiReadiness(_env(fine: false), _granted);
    expect(r.blockers, [WifiBlocker.preciseLocationRequired]);
  });

  test('nearby Wi-Fi permission only matters on Android 13+', () {
    const noNearby = WifiPermissionStatus(
      location: PermissionState.granted,
      nearbyWifi: PermissionState.denied,
    );
    expect(assessWifiReadiness(_env(sdk: 33), noNearby).blockers, [
      WifiBlocker.nearbyWifiPermissionDenied,
    ]);
    expect(assessWifiReadiness(_env(sdk: 30), noNearby).isReady, isTrue);
  });

  test('Wi-Fi off and location services off are reported', () {
    final r = assessWifiReadiness(_env(wifi: false, location: false), _granted);
    expect(r.blockers, [
      WifiBlocker.wifiDisabled,
      WifiBlocker.locationServicesOff,
    ]);
  });
}
