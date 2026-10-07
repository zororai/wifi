import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ar_screen.dart';

/// Phase 0 AR spike. Throwaway measurement tool, NOT production code.
void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AR spike',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const GateScreen(),
  );
}

const arChannel = MethodChannel('spike/ar');

/// Checks ARCore availability, offers install, requests camera permission.
class GateScreen extends StatefulWidget {
  const GateScreen({super.key});

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> with WidgetsBindingObserver {
  String _availability = 'checking…';
  bool _supported = false;
  bool _installed = false;
  PermissionStatus? _camera;
  String _message = '';
  CompositionMode _mode = CompositionMode.hybrid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the Play Store install flow.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    // checkAvailability may be transient (UNKNOWN_CHECKING) at first.
    for (var i = 0; i < 20; i++) {
      final a = Map<String, Object?>.from(
        (await arChannel.invokeMethod<Map>('availability')) ?? const {},
      );
      if (!mounted) return;
      setState(() {
        _availability = '${a['name']}';
        _supported = a['supported'] == true;
        _installed = a['name'] == 'SUPPORTED_INSTALLED';
      });
      if (a['transient'] != true) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final cam = await Permission.camera.status;
    if (mounted) setState(() => _camera = cam);
  }

  Future<void> _install() async {
    final r = await arChannel.invokeMethod<String>('requestInstall', {
      'userRequested': true,
    });
    setState(() => _message = 'requestInstall: $r');
    await _check();
  }

  Future<void> _requestCamera() async {
    final s = await Permission.camera.request();
    setState(() => _camera = s);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _supported && _installed && (_camera?.isGranted ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text('AR spike')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('ARCore availability: $_availability'),
          Text('Camera permission: ${_camera?.name ?? '…'}'),
          if (_message.isNotEmpty) Text(_message),
          const SizedBox(height: 12),
          if (_supported && !_installed)
            FilledButton(
              onPressed: _install,
              child: const Text('Install / update Google Play Services for AR'),
            ),
          if (!(_camera?.isGranted ?? false))
            FilledButton(
              onPressed: _requestCamera,
              child: const Text('Grant camera permission'),
            ),
          if (_camera?.isPermanentlyDenied ?? false)
            TextButton(
              onPressed: openAppSettings,
              child: const Text('Open app settings'),
            ),
          if (!_supported && !_availability.startsWith('UNKNOWN'))
            const Text(
              'This device does not support ARCore. The real app would fall '
              'back to manual grid positioning.',
            ),
          const Divider(height: 32),
          const Text('PlatformView composition mode:'),
          RadioGroup<CompositionMode>(
            groupValue: _mode,
            onChanged: (m) => setState(() => _mode = m ?? _mode),
            child: const Column(
              children: [
                RadioListTile(
                  value: CompositionMode.hybrid,
                  title: Text('Hybrid Composition (initExpensiveAndroidView)'),
                ),
                RadioListTile(
                  value: CompositionMode.textureLayer,
                  title: Text('Texture Layer / default (AndroidView)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.view_in_ar),
            onPressed: ready
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ArScreen(mode: _mode),
                    ),
                  )
                : null,
            label: const Text('Start AR test'),
          ),
        ],
      ),
    );
  }
}
