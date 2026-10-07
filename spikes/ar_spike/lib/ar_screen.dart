import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' hide Summary;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'main.dart' show arChannel;
import 'projection.dart';
import 'stats.dart';

enum CompositionMode { hybrid, textureLayer }

const _viewType = 'spike/ar_view';
const _frames = EventChannel('spike/ar/frames');

/// One native frame as received in Dart.
class ArFrame {
  ArFrame(Map<Object?, Object?> m, this.dartReceiveUs)
    : frameTsNs = m['frameTsNs'] as int,
      renderWallUs = m['renderWallUs'] as int,
      sendWallUs = m['sendWallUs'] as int,
      nativeFrameMs = (m['nativeFrameMs'] as num).toDouble(),
      tracking = m['tracking'] as String,
      failure = m['failure'] as String,
      pose = m['pose'] as Float64List,
      view = m['view'] as Float32List,
      proj = m['proj'] as Float32List,
      floorY = (m['floorY'] as num?)?.toDouble(),
      planeCount = m['planeCount'] as int,
      anchor = m['anchor'] as Float64List?;

  final int dartReceiveUs;
  final int frameTsNs;
  final int renderWallUs;
  final int sendWallUs;
  final double nativeFrameMs;
  final String tracking;
  final String failure;
  final Float64List pose;
  final Float32List view;
  final Float32List proj;
  final double? floorY;
  final int planeCount;
  final Float64List? anchor;

  bool get isTracking => tracking == 'TRACKING';
  Vec3 get position => Vec3(pose[0], pose[1], pose[2]);
}

/// Bounded rolling buffer for metrics.
class Rolling {
  Rolling([this.capacity = 900]);
  final int capacity;
  final _v = <double>[];
  void add(num x) {
    _v.add(x.toDouble());
    if (_v.length > capacity) _v.removeAt(0);
  }

  Summary? get summary => Summary.of(_v);
}

class ArScreen extends StatefulWidget {
  const ArScreen({super.key, required this.mode});
  final CompositionMode mode;

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> {
  final _latest = ValueNotifier<ArFrame?>(null);
  StreamSubscription<dynamic>? _sub;
  Timer? _hudTimer;

  // Metrics.
  final _transitMs = Rolling(); // native main-thread send -> Dart receive
  final _renderToReceiveMs = Rolling(); // GL frame drawn -> Dart receive
  final _paintLagMs = Rolling(); // GL frame drawn -> Dart paint() using it
  final _arrivalMs = Rolling(); // Dart inter-arrival interval
  final _cameraFrameMs = Rolling(); // native camera timestamp interval
  final _nativeFrameMs = Rolling(); // update()+draw cost on GL thread
  int _received = 0;
  int _painted = 0;
  int _trackingFrames = 0;
  final _failureCounts = <String, int>{};
  final _errors = <String>[];
  int? _lastReceiveUs;
  int? _lastFrameTsNs;

  // Scene.
  final _markers = <Vec3>[];
  bool _showFloorQuad = true;

  // Drift test.
  Vec3? _driftStart;
  Vec3? _anchorAtCreation;
  Map<String, Object?>? _driftResult;

  @override
  void initState() {
    super.initState();
    _sub = _frames.receiveBroadcastStream().listen(_onEvent);
    _hudTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hudTimer?.cancel();
    _latest.dispose();
    super.dispose();
  }

  void _onEvent(dynamic e) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final m = e as Map<Object?, Object?>;
    if (m['error'] != null) {
      _errors.add('${m['error']}');
      return;
    }
    final f = ArFrame(m, now);
    _received++;
    _transitMs.add((now - f.sendWallUs) / 1000);
    _renderToReceiveMs.add((now - f.renderWallUs) / 1000);
    _nativeFrameMs.add(f.nativeFrameMs);
    if (_lastReceiveUs != null) _arrivalMs.add((now - _lastReceiveUs!) / 1000);
    if (_lastFrameTsNs != null && f.frameTsNs != _lastFrameTsNs) {
      _cameraFrameMs.add((f.frameTsNs - _lastFrameTsNs!) / 1e6);
    }
    _lastReceiveUs = now;
    _lastFrameTsNs = f.frameTsNs;
    if (f.isTracking) {
      _trackingFrames++;
    } else {
      _failureCounts[f.failure] = (_failureCounts[f.failure] ?? 0) + 1;
    }
    if (_driftStart != null && _anchorAtCreation == null && f.anchor != null) {
      _anchorAtCreation = Vec3(f.anchor![0], f.anchor![1], f.anchor![2]);
    }
    _latest.value = f;
  }

  void _onPainted(ArFrame f) {
    _painted++;
    _paintLagMs.add(
      (DateTime.now().microsecondsSinceEpoch - f.renderWallUs) / 1000,
    );
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  void _dropMarker() {
    final f = _latest.value;
    if (f == null || !f.isTracking) {
      return _snack('Not tracking: ${f?.failure ?? 'no frames'}');
    }
    if (f.floorY == null) {
      return _snack('No floor plane yet: move the phone slowly over the floor');
    }
    setState(() => _markers.add(Vec3(f.pose[0], f.floorY!, f.pose[2])));
  }

  void _gridAroundFirst() {
    if (_markers.isEmpty) return _snack('Drop a marker first');
    final c = _markers.first;
    setState(() {
      for (var i = -2; i <= 2; i++) {
        for (var j = -2; j <= 2; j++) {
          if (i == 0 && j == 0) continue;
          _markers.add(Vec3(c.x + i * 0.5, c.y, c.z + j * 0.5));
        }
      }
    });
  }

  Future<void> _markStart() async {
    final f = _latest.value;
    if (f == null || !f.isTracking) return _snack('Not tracking');
    await arChannel.invokeMethod<void>('dropAnchor');
    setState(() {
      _driftStart = f.position;
      _anchorAtCreation = null;
      _driftResult = null;
    });
    _snack(
      'Start marked. Walk the room, return to the taped spot, then "Mark return".',
    );
  }

  void _markReturn() {
    final f = _latest.value;
    if (_driftStart == null) return _snack('Mark start first');
    if (f == null || !f.isTracking) return _snack('Not tracking');
    final s = _driftStart!;
    final now = f.position;
    double hdist(Vec3 a, Vec3 b) =>
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.z - b.z, 2));
    final anchorNow = f.anchor == null
        ? null
        : Vec3(f.anchor![0], f.anchor![1], f.anchor![2]);
    setState(() {
      _driftResult = {
        'rawReturnErrorHorizM': hdist(s, now),
        'rawReturnErrorVertM': (s.y - now.y).abs(),
        'anchorShiftHorizM': (anchorNow != null && _anchorAtCreation != null)
            ? hdist(_anchorAtCreation!, anchorNow)
            : null,
        'returnVsAnchorHorizM': anchorNow == null
            ? null
            : hdist(anchorNow, now),
        'start': s.toJson(),
        'return': now.toJson(),
        'anchorAtCreation': _anchorAtCreation?.toJson(),
        'anchorNow': anchorNow?.toJson(),
      };
    });
  }

  Map<String, Object?> _report() => {
    'mode': widget.mode.name,
    'received': _received,
    'painted': _painted,
    'trackingFraction': _received == 0 ? null : _trackingFrames / _received,
    'failureCounts': _failureCounts,
    'transitMs': _transitMs.summary?.toJson(),
    'renderToReceiveMs': _renderToReceiveMs.summary?.toJson(),
    'paintLagMs': _paintLagMs.summary?.toJson(),
    'dartInterArrivalMs': _arrivalMs.summary?.toJson(),
    'cameraFrameIntervalMs': _cameraFrameMs.summary?.toJson(),
    'nativeUpdateDrawMs': _nativeFrameMs.summary?.toJson(),
    'drift': _driftResult,
    'errors': _errors.take(20).toList(),
  };

  Future<void> _save() async {
    try {
      final path = await arChannel.invokeMethod<String>('saveText', {
        'name':
            'ar_spike_${widget.mode.name}_${DateTime.now().millisecondsSinceEpoch}.json',
        'content': const JsonEncoder.withIndent('  ').convert(_report()),
      });
      _snack('Saved $path');
    } on PlatformException catch (e) {
      _snack('Save failed: ${e.message}');
    }
  }

  Widget _platformView() {
    switch (widget.mode) {
      case CompositionMode.hybrid:
        return PlatformViewLink(
          viewType: _viewType,
          surfaceFactory: (context, controller) => AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          ),
          onCreatePlatformView: (params) =>
              PlatformViewsService.initExpensiveAndroidView(
                  id: params.id,
                  viewType: _viewType,
                  layoutDirection: TextDirection.ltr,
                  creationParamsCodec: const StandardMessageCodec(),
                  onFocus: () => params.onFocusChanged(true),
                )
                ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
                ..create(),
        );
      case CompositionMode.textureLayer:
        return const AndroidView(
          viewType: _viewType,
          creationParamsCodec: StandardMessageCodec(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _latest.value;
    String s(Summary? x) => x == null
        ? '-'
        : 'p50 ${x.p50.toStringAsFixed(1)} p95 ${x.p95.toStringAsFixed(1)} '
              'sd ${x.sd.toStringAsFixed(1)}';
    final hud = [
      'mode: ${widget.mode.name}',
      'tracking: ${f?.tracking ?? '-'} (${f?.failure ?? '-'})  planes: ${f?.planeCount ?? 0}',
      'floorY: ${f?.floorY?.toStringAsFixed(2) ?? 'none'}  cam: ${f == null ? '-' : '${f.pose[0].toStringAsFixed(2)}, ${f.pose[1].toStringAsFixed(2)}, ${f.pose[2].toStringAsFixed(2)}'}',
      'frames rx $_received painted $_painted  tracking ${_received == 0 ? '-' : (100 * _trackingFrames / _received).toStringAsFixed(0)}%',
      'camera dt ms: ${s(_cameraFrameMs.summary)}',
      'dart arrival ms: ${s(_arrivalMs.summary)}',
      'transit ms: ${s(_transitMs.summary)}',
      'render->paint ms: ${s(_paintLagMs.summary)}',
      'native update+draw ms: ${s(_nativeFrameMs.summary)}',
      if (_driftResult != null)
        'drift: raw ${(_driftResult!['rawReturnErrorHorizM'] as double).toStringAsFixed(3)} m, '
            'anchor shift ${(_driftResult!['anchorShiftHorizM'] as double?)?.toStringAsFixed(3) ?? '-'} m',
      if (_errors.isNotEmpty) 'last error: ${_errors.last}',
    ].join('\n');

    return Scaffold(
      appBar: AppBar(title: const Text('AR spike')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _platformView(),
          IgnorePointer(
            child: CustomPaint(
              painter: _OverlayPainter(
                _latest,
                _markers,
                _showFloorQuad,
                _onPainted,
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black.withValues(alpha: 0.55),
              child: Text(
                hud,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 16,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(
                  onPressed: _dropMarker,
                  child: const Text('Drop marker'),
                ),
                FilledButton(
                  onPressed: _gridAroundFirst,
                  child: const Text('Grid 0.5 m'),
                ),
                FilledButton(
                  onPressed: () =>
                      setState(() => _showFloorQuad = !_showFloorQuad),
                  child: Text(_showFloorQuad ? 'Hide quad' : 'Show quad'),
                ),
                FilledButton(
                  onPressed: () => setState(_markers.clear),
                  child: const Text('Clear'),
                ),
                FilledButton.tonal(
                  onPressed: _markStart,
                  child: const Text('Mark start'),
                ),
                FilledButton.tonal(
                  onPressed: _markReturn,
                  child: const Text('Mark return'),
                ),
                FilledButton.tonal(
                  onPressed: _save,
                  child: const Text('Save log'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints floor markers and a translucent 2 x 2 m floor quad using the most
/// recent frame's matrices. Repaints whenever a new frame arrives.
class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.frame, this.markers, this.showQuad, this.onPainted)
    : super(repaint: frame);

  final ValueListenable<ArFrame?> frame;
  final List<Vec3> markers;
  final bool showQuad;
  final void Function(ArFrame) onPainted;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame.value;
    if (f == null) return;
    onPainted(f);
    if (!f.isTracking) return; // Never draw with an untrusted pose.

    if (showQuad && markers.isNotEmpty) {
      final c = markers.first;
      final corners = [
        Vec3(c.x - 1, c.y, c.z - 1),
        Vec3(c.x + 1, c.y, c.z - 1),
        Vec3(c.x + 1, c.y, c.z + 1),
        Vec3(c.x - 1, c.y, c.z + 1),
      ].map((p) => projectToScreen(p, f.view, f.proj, size)).toList();
      if (corners.every((o) => o != null)) {
        final path = Path()..addPolygon(corners.cast<Offset>(), true);
        canvas.drawPath(
          path,
          Paint()..color = Colors.cyan.withValues(alpha: 0.25),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.cyan
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    for (var i = 0; i < markers.length; i++) {
      final o = projectToScreen(markers[i], f.view, f.proj, size);
      if (o == null) continue;
      canvas.drawCircle(
        o,
        10,
        Paint()..color = i == 0 ? Colors.red : Colors.amber,
      );
      canvas.drawCircle(
        o,
        10,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.markers.length != markers.length || old.showQuad != showQuad;
}
