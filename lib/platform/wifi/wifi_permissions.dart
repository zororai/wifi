import 'package:permission_handler/permission_handler.dart' as ph;

/// Runtime permission state as the app needs to reason about it.
enum PermissionState {
  granted,
  denied,

  /// Android will no longer show the dialog; the user must use Settings.
  permanentlyDenied,

  /// Not applicable on this Android version.
  notRequired,
}

final class WifiPermissionStatus {
  const WifiPermissionStatus({
    required this.location,
    required this.nearbyWifi,
  });

  /// Location permission (Android requires it for Wi-Fi scan results and the
  /// connected BSSID).
  final PermissionState location;

  /// NEARBY_WIFI_DEVICES (Android 13+).
  final PermissionState nearbyWifi;

  bool get allGranted => _ok(location) && _ok(nearbyWifi);

  static bool _ok(PermissionState s) =>
      s == PermissionState.granted || s == PermissionState.notRequired;
}

abstract interface class WifiPermissionService {
  Future<WifiPermissionStatus> check({required int sdkInt});

  /// Shows the system dialogs for whatever is still missing.
  Future<WifiPermissionStatus> request({required int sdkInt});

  Future<bool> openAppSettings();
}

/// [WifiPermissionService] using the permission_handler plugin.
class PermissionHandlerWifiPermissionService implements WifiPermissionService {
  const PermissionHandlerWifiPermissionService();

  @override
  Future<WifiPermissionStatus> check({required int sdkInt}) async =>
      WifiPermissionStatus(
        location: _map(await ph.Permission.location.status),
        nearbyWifi: sdkInt >= 33
            ? _map(await ph.Permission.nearbyWifiDevices.status)
            : PermissionState.notRequired,
      );

  @override
  Future<WifiPermissionStatus> request({required int sdkInt}) async {
    final location = await ph.Permission.location.request();
    if (location.isGranted && sdkInt >= 33) {
      await ph.Permission.nearbyWifiDevices.request();
    }
    return check(sdkInt: sdkInt);
  }

  @override
  Future<bool> openAppSettings() => ph.openAppSettings();

  static PermissionState _map(ph.PermissionStatus s) {
    if (s.isGranted || s.isLimited) return PermissionState.granted;
    if (s.isPermanentlyDenied || s.isRestricted) {
      return PermissionState.permanentlyDenied;
    }
    return PermissionState.denied;
  }
}
