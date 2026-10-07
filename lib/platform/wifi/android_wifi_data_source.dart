import 'dart:async';

import 'package:flutter/services.dart';

import 'wifi_data_source.dart';
import 'wifi_models.dart';
import 'wifi_native_api.dart';

/// [WifiDataSource] backed by the Kotlin WifiBridge.
class AndroidWifiDataSource implements WifiDataSource {
  AndroidWifiDataSource(this._native, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final WifiNativeApi _native;
  final DateTime Function() _clock;

  /// Results older than (time since the scan request + this slack) were not
  /// refreshed by the scan and are flagged as such.
  static const freshnessSlack = Duration(seconds: 2);

  @override
  Future<WifiEnvironment> environment() async =>
      WifiEnvironment.fromMap(await _native.environment());

  @override
  Future<ScanOutcome> scan({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final env = await environment();
    if (!env.wifiEnabled || !env.locationEnabled) {
      return ScanBlocked(
        wifiDisabled: !env.wifiEnabled,
        locationOff: !env.locationEnabled,
      );
    }

    // Listen BEFORE requesting so the result broadcast cannot be missed.
    final broadcast = Completer<bool>();
    final sub = _native.scanEvents().listen(
      (e) {
        if (!broadcast.isCompleted) broadcast.complete(e['updated'] == true);
      },
      onError: (Object e) {
        if (!broadcast.isCompleted) broadcast.completeError(e);
      },
    );
    final sinceRequest = Stopwatch()..start();
    try {
      final bool accepted;
      try {
        accepted = await _native.startScan();
      } on PlatformException catch (e) {
        return _failure(e);
      }
      if (!accepted) {
        return ScanNotPerformed(
          ScanFailureKind.rejected,
          cachedAccessPoints: await _readCached(),
        );
      }

      final bool? updated;
      try {
        updated = await broadcast.future.timeout(timeout);
      } on TimeoutException {
        return ScanNotPerformed(
          ScanFailureKind.timedOut,
          cachedAccessPoints: await _readCached(),
        );
      }
      if (updated != true) {
        return ScanNotPerformed(
          ScanFailureKind.noNewResults,
          cachedAccessPoints: await _readCached(),
        );
      }

      final List<ScannedAccessPoint> results;
      try {
        results = await _readResults();
      } on PlatformException catch (e) {
        return _failure(e);
      }
      final freshLimit = sinceRequest.elapsed + freshnessSlack;
      return ScanCompleted([
        for (final ap in results)
          ap.copyWith(
            seenInLatestScan: ap.age != null && ap.age! <= freshLimit,
          ),
      ], completedAt: _clock());
    } finally {
      await sub.cancel();
    }
  }

  ScanNotPerformed _failure(PlatformException e) => ScanNotPerformed(
    e.code == 'PERMISSION'
        ? ScanFailureKind.permissionDenied
        : ScanFailureKind.platformError,
    message: e.message,
  );

  Future<List<ScannedAccessPoint>> _readResults() async => [
    for (final m in await _native.scanResults()) ScannedAccessPoint.fromMap(m),
  ];

  /// Cached results, all flagged as not refreshed. Errors yield an empty list.
  Future<List<ScannedAccessPoint>> _readCached() async {
    try {
      return [
        for (final ap in await _readResults())
          ap.copyWith(seenInLatestScan: false),
      ];
    } on PlatformException {
      return const [];
    }
  }

  @override
  Future<ConnectedWifiInfo?> connectedInfo() async => ConnectedWifiInfo.fromMap(
    await _native.connectedInfo(),
    receivedAt: _clock(),
  );

  @override
  Stream<ConnectedWifiInfo?> watchConnected() => _native.connectedEvents().map(
    (m) => ConnectedWifiInfo.fromMap(m, receivedAt: _clock()),
  );

  @override
  Future<void> openSettings(WifiSettingsPage page) =>
      _native.openSettings(page.name);
}
