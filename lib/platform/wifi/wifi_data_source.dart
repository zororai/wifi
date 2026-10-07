import 'wifi_models.dart';

/// Wi-Fi access used by the rest of the app. Implementations:
/// [AndroidWifiDataSource] (native bridge) and [FakeWifiDataSource] (tests).
///
/// Two measurement modes are served by this interface:
/// - SCAN: [scan] requests a new scan; Android may throttle or reject it and
///   that is reported, never hidden.
/// - CONNECTED: [watchConnected] observes the associated network.
abstract interface class WifiDataSource {
  Future<WifiEnvironment> environment();

  /// Requests a new scan and waits up to [timeout] for fresh results.
  Future<ScanOutcome> scan({Duration timeout = const Duration(seconds: 15)});

  /// Current connected network, or null when not connected to Wi-Fi.
  Future<ConnectedWifiInfo?> connectedInfo();

  /// Connected-network observations; emits null when disconnected.
  Stream<ConnectedWifiInfo?> watchConnected();

  Future<void> openSettings(WifiSettingsPage page);
}
