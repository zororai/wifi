import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'android_wifi_data_source.dart';
import 'wifi_data_source.dart';
import 'wifi_models.dart';
import 'wifi_native_api.dart';
import 'wifi_permissions.dart';
import 'wifi_readiness.dart';

/// Override in tests with a FakeWifiDataSource.
final wifiDataSourceProvider = Provider<WifiDataSource>(
  (ref) => AndroidWifiDataSource(MethodChannelWifiNativeApi()),
);

final wifiPermissionServiceProvider = Provider<WifiPermissionService>(
  (ref) => const PermissionHandlerWifiPermissionService(),
);

/// Current permissions + device state. Invalidate to re-check (e.g. on app
/// resume or after the user returns from Settings).
final wifiReadinessProvider = FutureProvider<WifiReadiness>((ref) async {
  final env = await ref.watch(wifiDataSourceProvider).environment();
  final perms = await ref
      .watch(wifiPermissionServiceProvider)
      .check(sdkInt: env.sdkInt);
  return assessWifiReadiness(env, perms);
});

/// Live connected-network observations (null = not connected to Wi-Fi).
final connectedWifiProvider = StreamProvider<ConnectedWifiInfo?>(
  (ref) => ref.watch(wifiDataSourceProvider).watchConnected(),
);
