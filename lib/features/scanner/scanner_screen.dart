import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/classification/signal_classification.dart';
import '../../domain/model/network.dart';
import '../../platform/wifi/wifi_models.dart';
import '../../platform/wifi/wifi_providers.dart';
import '../../platform/wifi/wifi_readiness.dart';
import 'scanner_controller.dart';

/// Default thresholds until the Settings screen exists.
final _classes = ClassificationThresholds();

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Re-check permissions and device state when returning from Settings.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(wifiReadinessProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readiness = ref.watch(wifiReadinessProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose network')),
      body: switch (readiness) {
        AsyncData(:final value) when value.isReady => const _ReadyView(),
        AsyncData(:final value) => _BlockersView(readiness: value),
        AsyncError(:final error) => _Message(
          icon: Icons.error_outline,
          title: 'Could not read the Wi-Fi state',
          body: '$error',
          action: TextButton(
            onPressed: () => ref.invalidate(wifiReadinessProvider),
            child: const Text('Try again'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Permissions and device state

class _BlockersView extends ConsumerWidget {
  const _BlockersView({required this.readiness});
  final WifiReadiness readiness;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sdk = readiness.environment.sdkInt;
    final perms = ref.read(wifiPermissionServiceProvider);
    final wifi = ref.read(wifiDataSourceProvider);

    Future<void> requestPermissions() async {
      await perms.request(sdkInt: sdk);
      ref.invalidate(wifiReadinessProvider);
    }

    final cards = <Widget>[
      for (final b in readiness.blockers)
        switch (b) {
          WifiBlocker.locationPermissionDenied => _BlockerCard(
            title: 'Location permission needed',
            body: _locationRationale,
            actions: [
              FilledButton(
                onPressed: requestPermissions,
                child: const Text('Grant permission'),
              ),
            ],
          ),
          WifiBlocker.locationPermissionPermanentlyDenied => _BlockerCard(
            title: 'Location permission is turned off',
            body:
                '$_locationRationale\n\nAndroid will not ask again. Open the '
                'app settings, choose Permissions > Location and allow it.',
            actions: [
              FilledButton(
                onPressed: perms.openAppSettings,
                child: const Text('Open app settings'),
              ),
            ],
          ),
          WifiBlocker.preciseLocationRequired => _BlockerCard(
            title: 'Precise location needed',
            body:
                'Only approximate location is allowed. Android hides Wi-Fi '
                'scan results and access-point identifiers (BSSID) unless '
                'precise location is allowed.',
            actions: [
              FilledButton(
                onPressed: requestPermissions,
                child: const Text('Allow precise location'),
              ),
              TextButton(
                onPressed: perms.openAppSettings,
                child: const Text('App settings'),
              ),
            ],
          ),
          WifiBlocker.nearbyWifiPermissionDenied => _BlockerCard(
            title: 'Nearby Wi-Fi devices permission needed',
            body:
                'Android 13 and newer require this permission to read '
                'information about nearby Wi-Fi access points.',
            actions: [
              FilledButton(
                onPressed: requestPermissions,
                child: const Text('Grant permission'),
              ),
            ],
          ),
          WifiBlocker.nearbyWifiPermissionPermanentlyDenied => _BlockerCard(
            title: 'Nearby Wi-Fi devices permission is turned off',
            body:
                'Android will not ask again. Open the app settings, choose '
                'Permissions > Nearby devices and allow it.',
            actions: [
              FilledButton(
                onPressed: perms.openAppSettings,
                child: const Text('Open app settings'),
              ),
            ],
          ),
          WifiBlocker.wifiDisabled => _BlockerCard(
            title: 'Wi-Fi is turned off',
            body: 'Turn on Wi-Fi to find and measure networks.',
            actions: [
              FilledButton(
                onPressed: () => wifi.openSettings(WifiSettingsPage.wifi),
                child: const Text('Open Wi-Fi settings'),
              ),
            ],
          ),
          WifiBlocker.locationServicesOff => _BlockerCard(
            title: 'Location services are off',
            body:
                'Android does not return Wi-Fi scan results while device '
                'location is switched off. Turn it on in Settings. The app '
                'still does not use GPS.',
            actions: [
              FilledButton(
                onPressed: () => wifi.openSettings(WifiSettingsPage.location),
                child: const Text('Open location settings'),
              ),
            ],
          ),
        },
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: cards.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => i < cards.length
          ? cards[i]
          : TextButton.icon(
              onPressed: () => ref.invalidate(wifiReadinessProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Check again'),
            ),
    );
  }
}

const _locationRationale =
    'Android only gives apps Wi-Fi scan results and access-point identifiers '
    '(BSSID) when location permission is granted. RSSI Mapper uses it only '
    'to read Wi-Fi information. It does not use GPS and does not record '
    'where you are on a map.';

class _BlockerCard extends StatelessWidget {
  const _BlockerCard({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleMedium),
            const SizedBox(height: 8),
            Text(body, style: text.bodyMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ready: connected network + scan

class _ReadyView extends ConsumerWidget {
  const _ReadyView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanner = ref.watch(scannerControllerProvider);
    final aps = scanner.accessPoints;
    final ssidCounts = <String, int>{};
    for (final ap in aps) {
      if (ap.ssid case final ssid?) {
        ssidCounts[ssid] = (ssidCounts[ssid] ?? 0) + 1;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _ConnectedCard(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Nearby access points',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            FilledButton.icon(
              onPressed: scanner.scanning
                  ? null
                  : () => ref.read(scannerControllerProvider.notifier).scan(),
              icon: scanner.scanning
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find),
              label: Text(scanner.scanning ? 'Scanning…' : 'Scan'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (scanner.lastOutcome != null) _ScanStatus(scanner),
        if (aps.isEmpty && scanner.lastOutcome == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Tap Scan to look for nearby access points.'),
          ),
        if (aps.isEmpty && scanner.lastOutcome is ScanCompleted)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No access points were found.'),
          ),
        for (final ap in aps)
          _AccessPointTile(
            ap: ap,
            sharedSsid: ap.ssid != null && (ssidCounts[ap.ssid!] ?? 0) > 1,
          ),
      ],
    );
  }
}

class _ScanStatus extends StatelessWidget {
  const _ScanStatus(this.state);
  final ScannerState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, text, isProblem) = switch (state.lastOutcome!) {
      ScanCompleted(:final accessPoints) => (
        Icons.check_circle_outline,
        'New scan completed: ${accessPoints.length} access points.',
        false,
      ),
      ScanBlocked(:final wifiDisabled) => (
        Icons.block,
        wifiDisabled
            ? 'Wi-Fi is off, so no scan was made.'
            : 'Location services are off, so no scan was made.',
        true,
      ),
      ScanNotPerformed(:final kind) => (
        Icons.warning_amber,
        switch (kind) {
          ScanFailureKind.rejected =>
            'Android did not allow a new scan right now. Android limits how '
                'often apps may scan (scan throttling). Wait a little and try '
                'again.',
          ScanFailureKind.noNewResults =>
            'The scan finished without new results (it may have been '
                'throttled or failed). Try again shortly.',
          ScanFailureKind.timedOut =>
            'The scan did not finish in time. Try again.',
          ScanFailureKind.permissionDenied =>
            'Android refused access to Wi-Fi information. Check the app '
                'permissions.',
          ScanFailureKind.platformError =>
            'The scan failed because of a system error.',
        },
        true,
      ),
    };
    return Card(
      color: isProblem ? scheme.errorContainer : scheme.secondaryContainer,
      child: ListTile(
        leading: Icon(icon),
        title: Text(text),
        subtitle: state.showingCachedResults
            ? const Text(
                'The list below shows EARLIER results Android still holds. '
                'They are not from a new scan.',
              )
            : null,
      ),
    );
  }
}

class _AccessPointTile extends ConsumerWidget {
  const _AccessPointTile({required this.ap, required this.sharedSsid});

  final ScannedAccessPoint ap;
  final bool sharedSsid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rssi = ap.rssiDbm;
    final details = [
      ap.bssid ?? 'BSSID unavailable',
      if (ap.frequencyMhz != null)
        '${ap.frequencyMhz} MHz${ap.band == null ? '' : ' (${ap.band!.label})'}',
      ap.security.label,
      if (!ap.seenInLatestScan) 'not in latest scan',
      if (sharedSsid) 'name shared by several access points',
    ];
    return Card(
      child: ListTile(
        enabled: ap.canBeTarget,
        title: Text(ap.ssid ?? '(hidden network)'),
        subtitle: Text(details.join(' · ')),
        trailing: _RssiBadge(rssi),
        onTap: ap.canBeTarget
            ? () => _confirmTarget(
                context,
                ref,
                TargetNetwork(ssid: ap.ssid ?? '', bssid: ap.bssid!),
                rssi: rssi,
                frequencyMhz: ap.frequencyMhz,
              )
            : null,
      ),
    );
  }
}

class _ConnectedCard extends ConsumerWidget {
  const _ConnectedCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(connectedWifiProvider);
    final target = ref.watch(selectedTargetProvider);
    final text = Theme.of(context).textTheme;

    final Widget body = switch (connected) {
      AsyncData(value: final info?) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  info.ssid ?? '(name hidden by Android)',
                  style: text.titleMedium,
                ),
              ),
              _RssiBadge(info.rssiDbm),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              info.bssid ?? 'BSSID hidden by Android',
              if (info.frequencyMhz != null)
                '${info.frequencyMhz} MHz'
                    '${info.band == null ? '' : ' (${info.band!.label})'}',
              if (info.linkSpeedMbps != null) '${info.linkSpeedMbps} Mbps',
            ].join(' · '),
          ),
          if (target != null &&
              info.bssid != null &&
              info.bssid != target.bssid) ...[
            const SizedBox(height: 8),
            Text(
              'The phone is connected to a different access point than the '
              'selected target (${target.bssid}).',
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: info.bssid == null
                  ? null
                  : () => _confirmTarget(
                      context,
                      ref,
                      TargetNetwork(ssid: info.ssid ?? '', bssid: info.bssid!),
                      rssi: info.rssiDbm,
                      frequencyMhz: info.frequencyMhz,
                    ),
              child: const Text('Measure this network'),
            ),
          ),
        ],
      ),
      AsyncData() => const Text(
        'Not connected to Wi-Fi. Connected-network mode needs the phone to '
        'be connected; scan mode works without connecting.',
      ),
      AsyncError(:final error) => Text(
        error is PlatformException && error.code == 'PERMISSION'
            ? 'Android refused access to the connected network details.'
            : 'Connected-network details are unavailable.',
      ),
      _ => const LinearProgressIndicator(),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connected network', style: text.labelLarge),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}

class _RssiBadge extends StatelessWidget {
  const _RssiBadge(this.rssi);
  final int? rssi;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = rssi;
    if (r == null) return Text('RSSI n/a', style: text.bodySmall);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('$r dBm', style: text.titleSmall),
        Text(_classes.classify(r.toDouble()).label, style: text.bodySmall),
      ],
    );
  }
}

Future<void> _confirmTarget(
  BuildContext context,
  WidgetRef ref,
  TargetNetwork target, {
  required int? rssi,
  required int? frequencyMhz,
}) async {
  final band = WifiBand.fromFrequency(frequencyMhz);
  final selected = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            target.ssid.isEmpty ? '(hidden network)' : target.ssid,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            [
              'BSSID ${target.bssid}',
              if (band != null) band.label,
              if (rssi != null) '$rssi dBm now',
            ].join(' · '),
          ),
          const SizedBox(height: 12),
          const Text(
            'A survey measures this exact access point (BSSID). Readings from '
            'other access points, including ones with the same name or the '
            "same router's other band, are rejected.",
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Select as target'),
            ),
          ),
        ],
      ),
    ),
  );
  if (selected != true || !context.mounted) return;
  ref.read(selectedTargetProvider.notifier).select(target);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Target selected: ${target.ssid.isEmpty ? target.bssid : target.ssid}. '
        'Room setup is not available in this build yet.',
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    ),
  );
}
