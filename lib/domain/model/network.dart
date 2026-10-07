/// Android reports this BSSID when the real value is hidden (e.g. missing
/// location permission). It identifies no access point.
const redactedBssid = '02:00:00:00:00:00';

final _bssidPattern = RegExp(r'^[0-9a-f]{2}(:[0-9a-f]{2}){5}$');

/// Lower-cases and validates a BSSID. Returns null if [raw] is null,
/// malformed, or the redacted placeholder.
String? normalizeBssid(String? raw) {
  if (raw == null) return null;
  final b = raw.trim().toLowerCase();
  if (!_bssidPattern.hasMatch(b) || b == redactedBssid) return null;
  return b;
}

/// The single access point a survey measures.
///
/// Identified by BSSID: several access points (and bands of one router) can
/// share an SSID, so SSID alone is insufficient.
final class TargetNetwork {
  /// Throws [ArgumentError] if [bssid] is not a usable BSSID.
  TargetNetwork({required this.ssid, required String bssid})
    : bssid =
          normalizeBssid(bssid) ??
          (throw ArgumentError.value(bssid, 'bssid', 'Not a usable BSSID'));

  /// Human-readable network name. May be empty for hidden networks.
  final String ssid;

  /// Normalised (lower-case) BSSID.
  final String bssid;

  /// True only if [otherBssid] is a valid BSSID equal to the target's.
  bool matchesBssid(String? otherBssid) => normalizeBssid(otherBssid) == bssid;

  @override
  bool operator ==(Object other) =>
      other is TargetNetwork && other.bssid == bssid && other.ssid == ssid;

  @override
  int get hashCode => Object.hash(ssid, bssid);
}
