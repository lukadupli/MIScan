import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../frame.dart';
import 'document_model.dart';
import 'frame_math.dart';

/// Dev-only screen: overlays the segmentation model's live prediction on the
/// camera feed, so model quality can be judged in real-world use, with a
/// per-stage timing panel for finding what is actually slow.
///
/// Reached only via the icon in MyHomePage, which is hidden in release builds
/// (but deliberately not in profile builds -- those are the ones whose timings
/// mean anything). Never part of the real capture flow, so its strings are not
/// localized.
class LivePreviewPage extends StatefulWidget {
  const LivePreviewPage({super.key});

  @override
  State<LivePreviewPage> createState() => _LivePreviewPageState();
}

class _LivePreviewPageState extends State<LivePreviewPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  DocumentModel? _model;
  bool _busy = false;
  bool _disposed = false;
  String? _error;
  String? _inferenceError;
  List<Offset> _corners = const [];
  Size _sourceSize = Size.zero;
  int? _lastLatencyMs;
  final _repaintNotifier = ValueNotifier<bool>(false);

  // Profiling. A rolling window for the per-stage averages -- single frames
  // swing too much to read -- plus fallback totals since the screen opened,
  // because the fallback is rare enough that a 30-frame window would mostly
  // show zero and hide how often it really fires.
  static const _window = 30;
  final _recent = <Detection>[];
  final _recentWallUs = <int>[];
  int _frames = 0;
  int _fallbacks = 0;
  int _fallbackMaxN = 0;
  int _fallbackMaxUs = 0;
  int _fallbackTotalUs = 0;
  bool _showStats = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _setup();
  }

  Future<void> _setup() async {
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      if (mounted) setState(() => _error = 'Camera permission was denied.');
      return;
    }

    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await controller.initialize();
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera init failed: $e');
      return;
    }
    if (_disposed) {
      controller.dispose();
      return;
    }

    final previewSize = controller.value.previewSize!;
    _sourceSize = rotatedFrameSize(
      back.sensorOrientation,
      previewSize.width.toInt(),
      previewSize.height.toInt(),
    );

    _model ??= await DocumentModel.load();
    if (_disposed) {
      controller.dispose();
      return;
    }

    await controller.startImageStream(_onFrame);
    if (mounted) setState(() => _controller = controller);
  }

  void _onFrame(CameraImage image) {
    if (_busy || _disposed || _model == null) return;
    _busy = true;
    final sw = Stopwatch()..start();
    _model!
        .predict(image, _controller!.description.sensorOrientation)
        .then((det) {
      if (!_disposed && mounted) {
        setState(() {
          // null means the mask did not reduce to a plausible quadrilateral.
          // Drawing nothing is the honest response; the readout below says so,
          // so a blank overlay is distinguishable from a frozen one.
          _corners = det.corners ?? const [];
          _lastLatencyMs = sw.elapsedMilliseconds;
          _record(det, sw.elapsedMicroseconds);
        });
      }
    }).catchError((Object e) {
      // One bad frame should not take the stream down -- but silently
      // swallowing every failure makes a model that errors on every single
      // frame look identical to one that simply sees no document. Keep going,
      // and surface the first message so the difference is visible.
      if (!_disposed && mounted && _inferenceError == null) {
        setState(() => _inferenceError = '$e');
      }
    }).whenComplete(() => _busy = false);
  }

  void _record(Detection det, int wallUs) {
    _recent.add(det);
    _recentWallUs.add(wallUs);
    if (_recent.length > _window) {
      _recent.removeAt(0);
      _recentWallUs.removeAt(0);
    }
    _frames++;
    final mask = det.mask;
    if (mask.fallbackRan) {
      _fallbacks++;
      _fallbackTotalUs += mask.fallbackUs;
      if (mask.fallbackN > _fallbackMaxN) _fallbackMaxN = mask.fallbackN;
      if (mask.fallbackUs > _fallbackMaxUs) _fallbackMaxUs = mask.fallbackUs;
    }
  }

  String _statsText() {
    if (_recent.isEmpty) return 'waiting for first frame...';
    double avgMs(int Function(Detection) f) =>
        _recent.map(f).reduce((a, b) => a + b) / _recent.length / 1000.0;
    String row(String label, double ms) =>
        '${label.padRight(12)}${ms.toStringAsFixed(1).padLeft(7)} ms';

    final wallMs =
        _recentWallUs.reduce((a, b) => a + b) / _recentWallUs.length / 1000.0;
    final recentFallbacks = _recent.where((d) => d.mask.fallbackRan).length;
    final pct = 100.0 * _fallbacks / _frames;
    final last = _recent.last.mask;

    return [
      'avg of last ${_recent.length} frames',
      row('yuv->floats', avgMs((d) => d.yuvUs)),
      row('tensor wrap', avgMs((d) => d.tensorUs)),
      row('inference', avgMs((d) => d.inferenceUs)),
      row('unpack', avgMs((d) => d.unpackUs)),
      row('postprocess', avgMs((d) => d.postprocessUs)),
      row(' threshold', avgMs((d) => d.mask.thresholdUs)),
      row(' component', avgMs((d) => d.mask.componentUs)),
      row(' boundary', avgMs((d) => d.mask.boundaryUs)),
      row(' hull', avgMs((d) => d.mask.hullUs)),
      row(' simplify', avgMs((d) => d.mask.simplifyUs)),
      row(' fallback', avgMs((d) => d.mask.fallbackUs)),
      row('stage sum',
          avgMs((d) => d.yuvUs + d.tensorUs + d.inferenceUs + d.unpackUs + d.postprocessUs)),
      // Wall is measured around the whole predict() call from this page, so a
      // gap between it and the stage sum is async scheduling overhead.
      row('wall', wallMs),
      '',
      'fallback $recentFallbacks/${_recent.length} recent, '
          '$_fallbacks/$_frames total (${pct.toStringAsFixed(1)}%)',
      if (_fallbacks > 0)
        ' when run: n max $_fallbackMaxN, '
            'avg ${(_fallbackTotalUs / _fallbacks / 1000).toStringAsFixed(1)} ms, '
            'max ${(_fallbackMaxUs / 1000).toStringAsFixed(1)} ms',
      'last: ${last.path}, hull ${last.hullSize}'
          '${last.fallbackRan ? ', n ${last.fallbackN}' : ''}',
    ].join('\n');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _setup();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _controller?.dispose();
    _model?.dispose();
    _repaintNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live corner preview (debug)')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: openAppSettings,
                  child: const Text('Open app settings'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_lastLatencyMs == null
            ? 'Live corner preview (debug)'
            : '${_corners.isEmpty ? "no doc" : "tracking"}  ${_lastLatencyMs}ms/frame'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final destSize = constraints.biggest;
          final mapped = mapCornersToWidget(
            normalizedCorners: _corners,
            sourceSize: _sourceSize,
            destinationSize: destSize,
          );
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Fills the bars kPreviewFit = contain leaves around the frame,
                // black as in any camera viewfinder.
                const ColoredBox(color: Colors.black),
                FittedBox(
                  fit: kPreviewFit, // must match mapCornersToWidget -- see its docs
                  child: SizedBox(
                    width: _sourceSize.width,
                    height: _sourceSize.height,
                    child: CameraPreview(controller),
                  ),
                ),
                if (mapped.length == 4)
                  CustomPaint(
                    painter: BorderPainter(
                      color: Colors.redAccent,
                      cornerSize: 24.0,
                      cornerLineThickness: 3.0,
                      points: mapped,
                      notifier: _repaintNotifier,
                    ),
                  ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: GestureDetector(
                    // Tap to collapse: the full panel covers a fair slice of
                    // the preview, which gets in the way when aiming.
                    onTap: () => setState(() => _showStats = !_showStats),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _showStats
                            ? _statsText()
                            : 'stats (tap)  fallback $_fallbacks/$_frames',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_inferenceError != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.black87,
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'inference failing: $_inferenceError',
                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
