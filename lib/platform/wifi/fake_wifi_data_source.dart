import 'dart:async';

import 'wifi_data_source.dart';
import 'wifi_models.dart';

/// Scriptable [WifiDataSource] for tests and development without a device.
class FakeWifiDataSource implements WifiDataSource {
  FakeWifiDataSource({
    WifiEnvironment? environment,
    List<ScanOutcome>? scanOutcomes,
    this.connected,
  }) : env =
           environment ??
           const WifiEnvironment(
             sdkInt: 34,
             wifiEnabled: true,
             locationEnabled: true,
             scanThrottleEnabled: true,
           ),
       _scanOutcomes = [...?scanOutcomes];

  WifiEnvironment env;

  /// Current connected network (null = not connected).
  ConnectedWifiInfo? connected;

  final List<ScanOutcome> _scanOutcomes;
  final _connectedController = StreamController<ConnectedWifiInfo?>.broadcast();

  int scanCalls = 0;
  final openedSettings = <WifiSettingsPage>[];

  /// Queues the outcome returned by the next [scan] call.
  void enqueueScan(ScanOutcome outcome) => _scanOutcomes.add(outcome);

  /// Pushes a connected-network observation to listeners.
  void emitConnected(ConnectedWifiInfo? info) {
    connected = info;
    _connectedController.add(info);
  }

  @override
  Future<WifiEnvironment> environment() async => env;

  @override
  Future<ScanOutcome> scan({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    scanCalls++;
    if (_scanOutcomes.isEmpty) {
      return const ScanNotPerformed(ScanFailureKind.timedOut);
    }
    return _scanOutcomes.length == 1
        ? _scanOutcomes.first
        : _scanOutcomes.removeAt(0);
  }

  @override
  Future<ConnectedWifiInfo?> connectedInfo() async => connected;

  @override
  Stream<ConnectedWifiInfo?> watchConnected() async* {
    yield connected;
    yield* _connectedController.stream;
  }

  @override
  Future<void> openSettings(WifiSettingsPage page) async =>
      openedSettings.add(page);

  Future<void> dispose() => _connectedController.close();
}
