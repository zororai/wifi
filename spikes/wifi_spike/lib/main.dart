import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'stats.dart';
import 'wifi_probe.dart';

/// Phase 0 Wi-Fi spike. Throwaway measurement tool, NOT production code.
void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Wi-Fi spike',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const SpikeHome(),
  );
}

class SpikeHome extends StatefulWidget {
  const SpikeHome({super.key});

  @override
  State<SpikeHome> createState() => _SpikeHomeState();
}

class _SpikeHomeState extends State<SpikeHome> {
  final _probe = WifiProbe();
  final _events = <Map<String, Object?>>[];
  final _results = <String, Object?>{};

  Map<String, Object?> _device = const {};
  String _perms = '';
  String _busy = '';
  String _scanText = '';
  String _burstText = '';
  String _connectedText = '';
  String _saveText = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _log(String kind, Map<String, Object?> data) {
    _events.add({
      'kind': kind,
      'dartWallUs': DateTime.now().microsecondsSinceEpoch,
      ...data,
    });
  }

  Future<void> _refresh() async {
    final device = await _probe.deviceInfo();
    final loc = await Permission.location.status;
    final locService = await Permission.location.serviceStatus;
    final nearby = await Permission.nearbyWifiDevices.status;
    if (!mounted) return;
    setState(() {
      _device = device;
      _perms =
          'location: ${loc.name}  (service: ${locService.name})\n'
          'nearbyWifiDevices: ${nearby.name}';
    });
    _log('deviceInfo', device);
  }

  Future<void> _guard(String label, Future<void> Function() body) async {
    if (_busy.isNotEmpty) return;
    setState(() => _busy = label);
    try {
      await body();
    } on PlatformException catch (e) {
      _log('error', {'during': label, 'code': e.code, 'message': e.message});
      _snack('$label failed: ${e.code} ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = '');
      await _refresh();
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // --- Experiment 1: single scan snapshot -----------------------------------

  Future<void> _scanSnapshot() => _guard('Scan', () async {
    final completer = Completer<Map<String, Object?>?>();
    final sub = _probe.scanEvents().listen((e) {
      if (!completer.isCompleted) completer.complete(e);
    });
    final start = await _probe.startScan();
    _log('startScan', start);
    Map<String, Object?>? event;
    if (start['accepted'] == true) {
      event = await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => null,
      );
    }
    await sub.cancel();
    // Read whatever the OS currently holds (may be a stale cache).
    final results = await _probe.scanResults();
    _log('scanResults', {'results': results, 'broadcast': event?['updated']});
    results.sort((a, b) => (b['rssi'] as int).compareTo(a['rssi'] as int));
    final redacted = results.where(isRedacted).length;
    final ages = Summary.of(results.map((r) => r['ageMs'] as int));
    setState(() {
      _scanText =
          'startScan accepted: ${start['accepted']}\n'
          'broadcast updated: ${event == null ? 'no broadcast' : event['updated']}\n'
          'results: ${results.length}, redacted: $redacted\n'
          'result age ms: $ages\n\n'
          '${results.take(15).map((r) => '${r['rssi']} dBm  ${r['frequencyMhz']} MHz  '
              '${r['bssid']}  "${r['ssid']}"  age ${r['ageMs']} ms').join('\n')}';
    });
  });

  // --- Experiment 2: throttling burst ---------------------------------------

  Future<void> _throttleBurst() => _guard('Throttle burst', () async {
    const interval = Duration(seconds: 5);
    const duration = Duration(seconds: 150);
    final attempts = <Map<String, Object?>>[];
    final broadcasts = <Map<String, Object?>>[];
    final sub = _probe.scanEvents().listen((e) {
      final results = (e['results'] as List?) ?? const [];
      final ages = [for (final r in results) ((r as Map)['ageMs'] as num)];
      final b = {
        'updated': e['updated'],
        'elapsedMs': e['elapsedMs'],
        'resultCount': results.length,
        'minAgeMs': ages.isEmpty ? null : ages.reduce((a, b) => a < b ? a : b),
      };
      broadcasts.add(b);
      _log('scanBroadcast', b);
    });
    final sw = Stopwatch()..start();
    while (sw.elapsed < duration) {
      final r = await _probe.startScan();
      final a = {...r, 'tSec': sw.elapsed.inMilliseconds / 1000};
      attempts.add(a);
      _log('burstAttempt', a);
      if (mounted) {
        setState(
          () => _burstText =
              'running… ${sw.elapsed.inSeconds}/${duration.inSeconds} s, '
              'accepted ${attempts.where((x) => x['accepted'] == true).length}'
              '/${attempts.length}',
        );
      }
      await Future<void>.delayed(interval);
    }
    await Future<void>.delayed(const Duration(seconds: 10));
    await sub.cancel();

    final accepted = attempts.where((a) => a['accepted'] == true).toList();
    final rejected = attempts.where((a) => a['accepted'] != true).toList();
    final summary = {
      'intervalSec': interval.inSeconds,
      'durationSec': duration.inSeconds,
      'attempts': attempts.length,
      'accepted': accepted.length,
      'rejected': rejected.length,
      'acceptedAtSec': [for (final a in accepted) a['tSec']],
      'broadcastsUpdatedTrue': broadcasts
          .where((b) => b['updated'] == true)
          .length,
      'broadcastsUpdatedFalse': broadcasts
          .where((b) => b['updated'] != true)
          .length,
      'scanThrottleEnabled': _device['scanThrottleEnabled'],
    };
    _results['throttleBurst'] = summary;
    setState(
      () => _burstText = const JsonEncoder.withIndent('  ').convert(summary),
    );
  });

  // --- Experiment 3: connected-network update cadence ----------------------

  Future<void> _connectedCadence() => _guard('Connected cadence', () async {
    const duration = Duration(seconds: 60);
    const pollMs = 200;
    final bySource = <String, List<Map<String, Object?>>>{};
    final sub = _probe.connected(pollMs: pollMs).listen((e) {
      final src = (e['source'] as String?) ?? 'unknown';
      (bySource[src] ??= []).add(e);
      _log('connected', e);
    });
    final sw = Stopwatch()..start();
    while (sw.elapsed < duration) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(
          () => _connectedText =
              'running… ${sw.elapsed.inSeconds}/${duration.inSeconds} s  '
              '${bySource.map((k, v) => MapEntry(k, v.length))}\n'
              'Hold the phone still for this test.',
        );
      }
    }
    await sub.cancel();

    final summary = <String, Object?>{'pollMs': pollMs};
    bySource.forEach((src, list) {
      final valid = list.where((e) => e['rssi'] is int).toList();
      // Times at which the RSSI value actually changed.
      final changeTimes = <num>[];
      int? prev;
      for (final e in valid) {
        final r = e['rssi'] as int;
        if (prev == null || r != prev) changeTimes.add(e['elapsedMs'] as num);
        prev = r;
      }
      summary[src] = {
        'events': list.length,
        'validRssi': valid.length,
        'unavailableRssi': list.length - valid.length,
        'redacted': list
            .where((e) => e.containsKey('bssid') && isRedacted(e))
            .length,
        'distinctBssids': {
          for (final e in list)
            if (e['bssid'] != null) e['bssid'],
        }.toList(),
        'frequenciesMhz': {
          for (final e in list)
            if (e['frequencyMhz'] != null) e['frequencyMhz'],
        }.toList(),
        'rssi': Summary.of(valid.map((e) => e['rssi'] as int))?.toJson(),
        'eventIntervalMs': Summary.of(
          intervals([
            for (final e in list)
              if (e['elapsedMs'] is num) e['elapsedMs'] as num,
          ]),
        )?.toJson(),
        'valueChangeIntervalMs': Summary.of(intervals(changeTimes))?.toJson(),
      };
    });
    // Simulates a naive "take 8 readings, pollMs apart" protocol on the poll
    // data: how many genuinely new readings (value runs) does a point contain?
    // 8 means every reading was fresh; 1 means the same value was copied 8x.
    final poll = (bySource['legacyPoll'] ?? const [])
        .where((e) => e['rssi'] is int)
        .toList();
    final runsPerWindow = <int>[];
    for (var i = 0; i + 8 <= poll.length; i += 8) {
      var runs = 0;
      int? last;
      for (final e in poll.sublist(i, i + 8)) {
        final r = e['rssi'] as int;
        if (last == null || r != last) runs++;
        last = r;
      }
      runsPerWindow.add(runs);
    }
    summary['naive8x${pollMs}ms_valueRunsPerWindow'] = Summary.of(runsPerWindow)
        ?.toJson();
    _results['connectedCadence'] = summary;
    setState(
      () =>
          _connectedText = const JsonEncoder.withIndent('  ').convert(summary),
    );
  });

  // --- Save -----------------------------------------------------------------

  Future<void> _save() => _guard('Save', () async {
    final payload = {
      'flavor': appFlavor,
      'savedAt': DateTime.now().toIso8601String(),
      'device': _device,
      'results': _results,
      'events': _events,
    };
    final name =
        'wifi_spike_${appFlavor ?? 'none'}_${DateTime.now().millisecondsSinceEpoch}.json';
    final path = await _probe.saveText(name, jsonEncode(payload));
    setState(() => _saveText = 'Saved: $path');
  });

  Future<void> _copySummary() async {
    final text = const JsonEncoder.withIndent('  ')
        .convert({'flavor': appFlavor, 'device': _device, 'results': _results});
    await Clipboard.setData(ClipboardData(text: text));
    _snack('Summary copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text('Wi-Fi spike (${appFlavor ?? 'no flavor'})'),
        bottom: busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Section(
            title: 'Device and permissions',
            body:
                '${_device.entries.map((e) => '${e.key}: ${e.value}').join('\n')}\n\n$_perms',
            actions: [
              _btn('Refresh', busy ? null : _refresh),
              _btn(
                'Request location',
                busy
                    ? null
                    : () => _guard(
                        'Location',
                        () => Permission.location.request(),
                      ),
              ),
              _btn(
                'Request nearby Wi-Fi',
                busy
                    ? null
                    : () => _guard(
                        'Nearby',
                        () => Permission.nearbyWifiDevices.request(),
                      ),
              ),
              _btn('App settings', () => openAppSettings()),
              _btn('Location settings', _probe.openLocationSettings),
              _btn('Wi-Fi settings', _probe.openWifiSettings),
            ],
          ),
          _Section(
            title: '1. Scan snapshot',
            body: _scanText,
            actions: [_btn('Scan once', busy ? null : _scanSnapshot)],
          ),
          _Section(
            title: '2. Throttling burst (startScan every 5 s for 150 s)',
            body: _burstText,
            actions: [_btn('Run burst', busy ? null : _throttleBurst)],
          ),
          _Section(
            title: '3. Connected RSSI cadence (60 s, phone still)',
            body: _connectedText,
            actions: [
              _btn('Run cadence test', busy ? null : _connectedCadence),
            ],
          ),
          _Section(
            title: 'Results',
            body: _saveText,
            actions: [
              _btn('Save JSON log', busy ? null : _save),
              _btn('Copy summary', _copySummary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback? onPressed) =>
      FilledButton.tonal(onPressed: onPressed, child: Text(label));
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              body,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );
}
