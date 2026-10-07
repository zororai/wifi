import 'room.dart';

/// How a measurement's position was obtained.
enum PositionSource {
  /// User tapped the position on a to-scale room grid.
  manualGrid('MANUAL_GRID'),

  /// Position from the ARCore camera pose converted to room coordinates.
  arTracked('AR_TRACKED');

  const PositionSource(this.storageName);

  /// Stable name used in storage and exports.
  final String storageName;
}

/// Android's "invalid RSSI" sentinel value.
const rssiInvalidSentinelDbm = -127;

/// Plausible range of a real RSSI reading. Values outside are treated as
/// unavailable, never as measurements.
bool isPlausibleRssi(int dbm) => dbm > rssiInvalidSentinelDbm && dbm < 0;

/// One raw reading as reported by the platform. Every field may be
/// unavailable; unavailable values stay null and are never replaced by
/// fabricated numbers.
final class RssiSample {
  const RssiSample({
    required this.timestamp,
    required this.bssid,
    required this.rssiDbm,
    this.ssid,
    this.frequencyMhz,
  });

  final DateTime timestamp;
  final String? bssid;
  final String? ssid;
  final int? rssiDbm;
  final int? frequencyMhz;
}

/// A recorded (MEASURED) point: one filtered RSSI value at a known position.
/// This is the input to statistics, interpolation and evaluation.
final class MeasuredPoint {
  /// Throws [ArgumentError] if [rssiDbm] is not finite.
  MeasuredPoint({required this.position, required this.rssiDbm, this.id}) {
    if (!rssiDbm.isFinite) {
      throw ArgumentError.value(rssiDbm, 'rssiDbm', 'must be finite');
    }
  }

  final RoomPoint position;

  /// Filtered RSSI in dBm. Not necessarily an integer (median of an even
  /// sample count, or a mean).
  final double rssiDbm;

  /// Optional identifier for tracing results back to stored data.
  final String? id;

  @override
  String toString() => 'MeasuredPoint($position, $rssiDbm dBm)';
}
