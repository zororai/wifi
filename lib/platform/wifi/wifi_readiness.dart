import 'wifi_models.dart';
import 'wifi_permissions.dart';

/// Something that currently prevents reading Wi-Fi data, in the order the
/// user should resolve them.
enum WifiBlocker {
  locationPermissionDenied,
  locationPermissionPermanentlyDenied,

  /// User granted only approximate location (Android 12+).
  preciseLocationRequired,
  nearbyWifiPermissionDenied,
  nearbyWifiPermissionPermanentlyDenied,
  wifiDisabled,
  locationServicesOff,
}

final class WifiReadiness {
  const WifiReadiness({
    required this.environment,
    required this.permissions,
    required this.blockers,
  });

  final WifiEnvironment environment;
  final WifiPermissionStatus permissions;
  final List<WifiBlocker> blockers;

  bool get isReady => blockers.isEmpty;
}

/// Pure assessment of what blocks Wi-Fi access.
WifiReadiness assessWifiReadiness(
  WifiEnvironment env,
  WifiPermissionStatus perms,
) {
  final b = <WifiBlocker>[];
  switch (perms.location) {
    case PermissionState.denied:
      b.add(WifiBlocker.locationPermissionDenied);
    case PermissionState.permanentlyDenied:
      b.add(WifiBlocker.locationPermissionPermanentlyDenied);
    case PermissionState.granted:
      if (!env.fineLocationGranted) b.add(WifiBlocker.preciseLocationRequired);
    case PermissionState.notRequired:
      break;
  }
  if (env.requiresNearbyWifiPermission) {
    switch (perms.nearbyWifi) {
      case PermissionState.denied:
        b.add(WifiBlocker.nearbyWifiPermissionDenied);
      case PermissionState.permanentlyDenied:
        b.add(WifiBlocker.nearbyWifiPermissionPermanentlyDenied);
      case PermissionState.granted:
      case PermissionState.notRequired:
        break;
    }
  }
  if (!env.wifiEnabled) b.add(WifiBlocker.wifiDisabled);
  if (!env.locationEnabled) b.add(WifiBlocker.locationServicesOff);
  return WifiReadiness(environment: env, permissions: perms, blockers: b);
}
