import '../../domain/model/network.dart';

/// Wi-Fi frequency band derived from the channel centre frequency.
enum WifiBand {
  ghz2_4('2.4 GHz'),
  ghz5('5 GHz'),
  ghz6('6 GHz');

  const WifiBand(this.label);
  final String label;

  /// Returns null for frequencies outside the known Wi-Fi bands.
  static WifiBand? fromFrequency(int? mhz) {
    if (mhz == null) return null;
    if (mhz >= 2400 && mhz < 2500) return WifiBand.ghz2_4;
    if (mhz >= 4900 && mhz < 5925) return WifiBand.ghz5;
    if (mhz >= 5925 && mhz <= 7125) return WifiBand.ghz6;
    return null;
  }
}

/// Security type parsed from Android's ScanResult.capabilities string,
/// e.g. "[WPA2-PSK-CCMP][RSN-PSK-CCMP][ESS]".
enum WifiSecurity {
  open('Open'),
  owe('Enhanced Open (OWE)'),
  wep('WEP'),
  wpa('WPA'),
  wpa2('WPA2'),
  wpa3('WPA3'),
  wpa2Wpa3('WPA2/WPA3'),
  enterprise('Enterprise (802.1X)'),
  unknown('Unknown');

  const WifiSecurity(this.label);
  final String label;

  static WifiSecurity parse(String? capabilities) {
    if (capabilities == null) return WifiSecurity.unknown;
    final c = capabilities.toUpperCase();
    if (c.contains('EAP')) return WifiSecurity.enterprise;
    final sae = c.contains('SAE');
    final psk = c.contains('PSK');
    if (sae && psk) return WifiSecurity.wpa2Wpa3;
    if (sae) return WifiSecurity.wpa3;
    if (c.contains('OWE')) return WifiSecurity.owe;
    if (c.contains('RSN') || c.contains('WPA2')) return WifiSecurity.wpa2;
    if (c.contains('WPA')) return WifiSecurity.wpa;
    if (c.contains('WEP')) return WifiSecurity.wep;
    if (c.contains('ESS') || c.trim().isEmpty) return WifiSecurity.open;
    return WifiSecurity.unknown;
  }
}

/// One access point from a scan. Unavailable values are null.
final class ScannedAccessPoint {
  const ScannedAccessPoint({
    required this.ssid,
    required this.bssid,
    required this.rssiDbm,
    required this.frequencyMhz,
    required this.security,
    required this.age,
    this.seenInLatestScan = true,
  });

  /// Null for hidden networks.
  final String? ssid;

  /// Normalised BSSID; null if missing or redacted (cannot be targeted).
  final String? bssid;

  final int? rssiDbm;
  final int? frequencyMhz;
  final WifiSecurity security;

  /// Time since the access point was last seen, as reported by Android.
  final Duration? age;

  /// False when Android returned an older cached entry that the latest scan
  /// did not refresh.
  final bool seenInLatestScan;

  WifiBand? get band => WifiBand.fromFrequency(frequencyMhz);

  bool get canBeTarget => bssid != null;

  ScannedAccessPoint copyWith({bool? seenInLatestScan}) => ScannedAccessPoint(
    ssid: ssid,
    bssid: bssid,
    rssiDbm: rssiDbm,
    frequencyMhz: frequencyMhz,
    security: security,
    age: age,
    seenInLatestScan: seenInLatestScan ?? this.seenInLatestScan,
  );

  /// Tolerant parser: missing or malformed fields become null, never throw.
  factory ScannedAccessPoint.fromMap(Map<Object?, Object?> m) =>
      ScannedAccessPoint(
        ssid: _string(m['ssid']),
        bssid: normalizeBssid(_string(m['bssid'])),
        rssiDbm: _int(m['rssi']),
        frequencyMhz: _int(m['frequencyMhz']),
        security: WifiSecurity.parse(_string(m['capabilities'])),
        age: switch (_int(m['ageMs'])) {
          final ms? => Duration(milliseconds: ms),
          null => null,
        },
      );
}

enum ConnectedInfoSource { networkCallback, legacyConnectionInfo, unknown }

/// The network the device is currently associated with.
final class ConnectedWifiInfo {
  const ConnectedWifiInfo({
    required this.ssid,
    required this.bssid,
    required this.rssiDbm,
    required this.frequencyMhz,
    required this.linkSpeedMbps,
    required this.source,
    required this.receivedAt,
    this.sequence,
    this.elapsedRealtimeMs,
  });

  /// Null when Android hides it (e.g. no location permission).
  final String? ssid;

  /// Normalised; null when missing or redacted ("02:00:00:00:00:00").
  final String? bssid;

  /// Null when Android reports no valid RSSI.
  final int? rssiDbm;
  final int? frequencyMhz;
  final int? linkSpeedMbps;
  final ConnectedInfoSource source;

  /// When Dart received the observation.
  final DateTime receivedAt;

  /// Monotonic native counter; increases with every observation.
  final int? sequence;

  /// Native monotonic clock at observation time (ms since boot).
  final int? elapsedRealtimeMs;

  WifiBand? get band => WifiBand.fromFrequency(frequencyMhz);

  /// Null-safe parser; returns null when the map reports "not connected".
  static ConnectedWifiInfo? fromMap(
    Map<Object?, Object?>? m, {
    required DateTime receivedAt,
  }) {
    if (m == null || m['connected'] == false) return null;
    return ConnectedWifiInfo(
      ssid: _string(m['ssid']),
      bssid: normalizeBssid(_string(m['bssid'])),
      rssiDbm: _int(m['rssi']),
      frequencyMhz: _int(m['frequencyMhz']),
      linkSpeedMbps: _int(m['linkSpeedMbps']),
      source: switch (m['source']) {
        'networkCallback' => ConnectedInfoSource.networkCallback,
        'legacyConnectionInfo' => ConnectedInfoSource.legacyConnectionInfo,
        _ => ConnectedInfoSource.unknown,
      },
      receivedAt: receivedAt,
      sequence: _int(m['sequence']),
      elapsedRealtimeMs: _int(m['elapsedRealtimeMs']),
    );
  }
}

/// Device state relevant to Wi-Fi access.
final class WifiEnvironment {
  const WifiEnvironment({
    required this.sdkInt,
    required this.wifiEnabled,
    required this.locationEnabled,
    required this.scanThrottleEnabled,
    this.fineLocationGranted = false,
  });

  final int sdkInt;
  final bool wifiEnabled;
  final bool locationEnabled;

  /// Developer option "Wi-Fi scan throttling" (API 30+); null if unknown.
  final bool? scanThrottleEnabled;

  /// ACCESS_FINE_LOCATION as reported by Android itself.
  final bool fineLocationGranted;

  bool get requiresNearbyWifiPermission => sdkInt >= 33;

  factory WifiEnvironment.fromMap(Map<Object?, Object?> m) => WifiEnvironment(
    sdkInt: _int(m['sdkInt']) ?? 0,
    wifiEnabled: m['wifiEnabled'] == true,
    locationEnabled: m['locationEnabled'] == true,
    scanThrottleEnabled: m['scanThrottleEnabled'] is bool
        ? m['scanThrottleEnabled'] as bool
        : null,
    fineLocationGranted: m['fineLocationGranted'] == true,
  );
}

enum WifiSettingsPage { wifi, location }

/// Why a scan produced no new results.
enum ScanFailureKind {
  /// Android rejected the request (commonly scan throttling).
  rejected,

  /// The scan finished but Android reported no updated results.
  noNewResults,

  /// No result broadcast arrived in time.
  timedOut,

  /// Android refused access (permission missing or revoked).
  permissionDenied,

  /// Unexpected platform error.
  platformError,
}

sealed class ScanOutcome {
  const ScanOutcome();
}

/// Device state prevents scanning (Wi-Fi off, location services off).
final class ScanBlocked extends ScanOutcome {
  const ScanBlocked({required this.wifiDisabled, required this.locationOff});
  final bool wifiDisabled;
  final bool locationOff;
}

/// A new scan completed and Android reported fresh results.
final class ScanCompleted extends ScanOutcome {
  const ScanCompleted(this.accessPoints, {required this.completedAt});
  final List<ScannedAccessPoint> accessPoints;
  final DateTime completedAt;
}

/// No new scan data. [cachedAccessPoints] are OLDER results Android still
/// holds; they may be shown for discovery but must never count as new
/// measurements.
final class ScanNotPerformed extends ScanOutcome {
  const ScanNotPerformed(
    this.kind, {
    this.cachedAccessPoints = const [],
    this.message,
  });
  final ScanFailureKind kind;
  final List<ScannedAccessPoint> cachedAccessPoints;
  final String? message;
}

String? _string(Object? v) => v is String && v.isNotEmpty ? v : null;

int? _int(Object? v) => switch (v) {
  final int i => i,
  final double d when d.isFinite => d.round(),
  _ => null,
};
