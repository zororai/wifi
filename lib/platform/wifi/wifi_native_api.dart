import 'package:flutter/services.dart';

/// Raw channel to the Kotlin WifiBridge. Kept minimal so that all decision
/// logic lives in Dart (AndroidWifiDataSource) and is unit-testable with a
/// fake implementation of this interface.
abstract interface class WifiNativeApi {
  Future<Map<Object?, Object?>> environment();

  /// True if Android accepted the scan request.
  Future<bool> startScan();

  Future<List<Map<Object?, Object?>>> scanResults();

  /// Null when not connected to Wi-Fi.
  Future<Map<Object?, Object?>?> connectedInfo();

  /// One event per SCAN_RESULTS_AVAILABLE broadcast: {updated: bool}.
  Stream<Map<Object?, Object?>> scanEvents();

  /// Connected-network observations; {connected: false} when disconnected.
  Stream<Map<Object?, Object?>> connectedEvents();

  Future<void> openSettings(String page);
}

class MethodChannelWifiNativeApi implements WifiNativeApi {
  static const _method = MethodChannel('rssi_mapper/wifi');
  static const _scanEvents = EventChannel('rssi_mapper/wifi/scan_events');
  static const _connected = EventChannel('rssi_mapper/wifi/connected');

  @override
  Future<Map<Object?, Object?>> environment() async =>
      await _method.invokeMapMethod<Object?, Object?>('environment') ??
      const {};

  @override
  Future<bool> startScan() async =>
      await _method.invokeMethod<bool>('startScan') ?? false;

  @override
  Future<List<Map<Object?, Object?>>> scanResults() async {
    final list = await _method.invokeListMethod<Object?>('scanResults');
    return [
      for (final e in list ?? const <Object?>[])
        if (e is Map) Map<Object?, Object?>.from(e),
    ];
  }

  @override
  Future<Map<Object?, Object?>?> connectedInfo() =>
      _method.invokeMapMethod<Object?, Object?>('connectedInfo');

  @override
  Stream<Map<Object?, Object?>> scanEvents() => _scanEvents
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => Map<Object?, Object?>.from(e as Map));

  @override
  Stream<Map<Object?, Object?>> connectedEvents() => _connected
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => Map<Object?, Object?>.from(e as Map));

  @override
  Future<void> openSettings(String page) =>
      _method.invokeMethod<void>('openSettings', {'page': page});
}
