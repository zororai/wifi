import '../model/measurement.dart';
import '../model/network.dart';
import 'rssi_filter.dart';

/// Why a raw sample cannot contribute to a measured point.
enum SampleRejection {
  /// No RSSI value was reported.
  rssiUnavailable,

  /// RSSI outside the plausible range (e.g. Android's -127 sentinel).
  rssiOutOfRange,

  /// BSSID missing, malformed or redacted, so the access point is unknown.
  bssidUnavailable,

  /// Sample came from a different access point than the survey target.
  bssidMismatch,
}

/// Returns null if [sample] is valid for [target], otherwise the reason.
/// BSSID is checked on every sample: access points are never mixed.
SampleRejection? checkSample(RssiSample sample, TargetNetwork target) {
  final bssid = normalizeBssid(sample.bssid);
  if (bssid == null) return SampleRejection.bssidUnavailable;
  if (bssid != target.bssid) return SampleRejection.bssidMismatch;
  final rssi = sample.rssiDbm;
  if (rssi == null) return SampleRejection.rssiUnavailable;
  if (!isPlausibleRssi(rssi)) return SampleRejection.rssiOutOfRange;
  return null;
}

final class RejectedSample {
  const RejectedSample(this.sample, this.reason);
  final RssiSample sample;
  final SampleRejection reason;
}

/// Result of turning the raw samples taken at one position into one value.
/// Raw samples are always preserved in [accepted] and [rejected].
sealed class PointAggregation {
  const PointAggregation(this.accepted, this.rejected);
  final List<RssiSample> accepted;
  final List<RejectedSample> rejected;
}

final class AggregationSucceeded extends PointAggregation {
  const AggregationSucceeded(super.accepted, super.rejected, this.rssiDbm);

  /// Filtered value for the point, in dBm.
  final double rssiDbm;
}

final class AggregationFailed extends PointAggregation {
  const AggregationFailed(
    super.accepted,
    super.rejected, {
    required this.requiredValidSamples,
  });

  /// The point must not be recorded: fewer valid samples than required.
  final int requiredValidSamples;
}

/// Validates every sample against [target] and, if at least
/// [minValidSamples] are valid, filters them into one value.
PointAggregation aggregateSamples(
  List<RssiSample> samples, {
  required TargetNetwork target,
  required FilterMethod method,
  required AveragingDomain domain,
  required int minValidSamples,
}) {
  if (minValidSamples < 1) {
    throw ArgumentError.value(minValidSamples, 'minValidSamples', 'must be >= 1');
  }
  final accepted = <RssiSample>[];
  final rejected = <RejectedSample>[];
  for (final s in samples) {
    final reason = checkSample(s, target);
    if (reason == null) {
      accepted.add(s);
    } else {
      rejected.add(RejectedSample(s, reason));
    }
  }
  if (accepted.length < minValidSamples) {
    return AggregationFailed(
      List.unmodifiable(accepted),
      List.unmodifiable(rejected),
      requiredValidSamples: minValidSamples,
    );
  }
  final value = combineRssi(
    [for (final s in accepted) s.rssiDbm!.toDouble()],
    method: method,
    domain: domain,
  )!;
  return AggregationSucceeded(
    List.unmodifiable(accepted),
    List.unmodifiable(rejected),
    value,
  );
}
