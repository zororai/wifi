import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/network.dart';
import '../../platform/wifi/wifi_models.dart';
import '../../platform/wifi/wifi_providers.dart';

final class ScannerState {
  const ScannerState({
    this.scanning = false,
    this.lastOutcome,
    this.accessPoints = const [],
    this.showingCachedResults = false,
  });

  final bool scanning;
  final ScanOutcome? lastOutcome;

  /// Access points currently displayed, strongest first.
  final List<ScannedAccessPoint> accessPoints;

  /// True when [accessPoints] are older cached results (no new scan data).
  final bool showingCachedResults;

  ScannerState copyWith({
    bool? scanning,
    ScanOutcome? lastOutcome,
    List<ScannedAccessPoint>? accessPoints,
    bool? showingCachedResults,
  }) => ScannerState(
    scanning: scanning ?? this.scanning,
    lastOutcome: lastOutcome ?? this.lastOutcome,
    accessPoints: accessPoints ?? this.accessPoints,
    showingCachedResults: showingCachedResults ?? this.showingCachedResults,
  );
}

class ScannerController extends Notifier<ScannerState> {
  @override
  ScannerState build() => const ScannerState();

  Future<void> scan() async {
    if (state.scanning) return;
    state = state.copyWith(scanning: true);
    final outcome = await ref.read(wifiDataSourceProvider).scan();
    if (!ref.mounted) return;
    state = switch (outcome) {
      ScanCompleted(:final accessPoints) => ScannerState(
        lastOutcome: outcome,
        accessPoints: sortByStrength(accessPoints),
      ),
      ScanNotPerformed(:final cachedAccessPoints)
          when cachedAccessPoints.isNotEmpty =>
        ScannerState(
          lastOutcome: outcome,
          accessPoints: sortByStrength(cachedAccessPoints),
          showingCachedResults: true,
        ),
      _ => state.copyWith(scanning: false, lastOutcome: outcome),
    };
  }
}

/// Strongest first; access points without a valid RSSI last.
List<ScannedAccessPoint> sortByStrength(List<ScannedAccessPoint> aps) =>
    [...aps]..sort((a, b) {
      final ra = a.rssiDbm;
      final rb = b.rssiDbm;
      if (ra == null && rb == null) return 0;
      if (ra == null) return 1;
      if (rb == null) return -1;
      return rb.compareTo(ra);
    });

final scannerControllerProvider =
    NotifierProvider<ScannerController, ScannerState>(ScannerController.new);

/// The access point chosen for the next survey (SSID + BSSID).
class SelectedTargetController extends Notifier<TargetNetwork?> {
  @override
  TargetNetwork? build() => null;

  void select(TargetNetwork target) => state = target;

  void clear() => state = null;
}

final selectedTargetProvider =
    NotifierProvider<SelectedTargetController, TargetNetwork?>(
      SelectedTargetController.new,
    );
