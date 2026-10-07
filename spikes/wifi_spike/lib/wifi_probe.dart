import 'package:flutter/services.dart';

/// Thin wrapper over the spike's Kotlin WifiProbe channels.
class WifiProbe {
  static const _method = MethodChannel('spike/wifi');
  static const _scanEvents = EventChannel('spike/wifi/scanEvents');
  static const _connected = EventChannel('spike/wifi/connected');

  Future<Map<String, Object?>> deviceInfo() async =>
      Map<String, Object?>.from(
          (await _method.invokeMethod<Map>('deviceInfo')) ?? const {});

  Future<Map<String, Object?>> startScan() async =>
      Map<String, Object?>.from(
          (await _method.invokeMethod<Map>('startScan')) ?? const {});

  Future<List<Map<String, Object?>>> scanResults() async {
    final list = await _method.invokeListMethod<Map>('scanResults') ?? const [];
    return [for (final m in list) Map<String, Object?>.from(m)];
  }

  Future<Map<String, Object?>> legacyConnectionInfo() async =>
      Map<String, Object?>.from(
          (await _method.invokeMethod<Map>('legacyConnectionInfo')) ??
              const {});

  Future<void> openLocationSettings() =>
      _method.invokeMethod<void>('openLocationSettings');

  Future<void> openWifiSettings() =>
      _method.invokeMethod<void>('openWifiSettings');

  Future<String?> saveText(String name, String content) =>
      _method.invokeMethod<String>(
          'saveText', {'name': name, 'content': content});

  /// Every SCAN_RESULTS_AVAILABLE broadcast, including updated == false.
  Stream<Map<String, Object?>> scanEvents() => _scanEvents
      .receiveBroadcastStream()
      .map((e) => Map<String, Object?>.from(e as Map));

  /// Connected-network observations from callback, RSSI broadcast and
  /// (if pollMs > 0) the deprecated legacy getter.
  Stream<Map<String, Object?>> connected({int pollMs = 0}) => _connected
      .receiveBroadcastStream({'pollMs': pollMs})
      .map((e) => Map<String, Object?>.from(e as Map));
}

const redactedBssid = '02:00:00:00:00:00';

bool isRedacted(Map<String, Object?> m) {
  final bssid = m['bssid'];
  final ssid = m['ssid'];
  return bssid == null ||
      bssid == redactedBssid ||
      ssid == null ||
      ssid == '<unknown ssid>';
}
