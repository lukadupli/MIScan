import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../frame.dart';
import '../helpers.dart';
import '../detection/document_model.dart';
import '../detection/frame_math.dart';

/// Dev-only screen: overlays the segmentation model's live prediction on the
/// camera feed, so model quality can be judged in real-world use, with a
/// per-stage timing panel for finding what is actually slow.
///
/// It also carries the measurements that decide how detection goes into the
/// real capture flow: camera preset and XNNPACK thread switches, an automatic
/// A/B sweep over them, and a test capture. Each is logged as a one-line
/// `PHASE0 kind=... key=value ...` record, so `adb logcat | grep PHASE0` reads
/// as a table.
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

/// What one logging interval measured, for one camera/model configuration.
class _Window {
  final clock = Stopwatch()..start();
  int delivered = 0; // frames the camera handed over, used or not
  int detected = 0; // frames that went through the model
  int noDoc = 0;
  int yuvUs = 0, inferUs = 0, postUs = 0, wallUs = 0;
  int uiFrames = 0, jankFrames = 0, slowFrames = 0;
  int worstBuildUs = 0, worstRasterUs = 0, worstVsyncUs = 0;
  final quads = <List<Offset>>[];
}

class _LivePreviewPageState extends State<LivePreviewPage>
    with WidgetsBindingObserver {
  CameraDescription? _camera;
  CameraController? _controller;
  DocumentModel? _model;
  ResolutionPreset _preset = ResolutionPreset.max;
  int _threads = DocumentModel.xnnpackThreads;
  bool _busy = false;
  bool _disposed = false;
  String? _error;
  String? _inferenceError;
  List<Offset> _corners = const [];
  Size _sourceSize = Size.zero;
  int? _lastLatencyMs;
  final _repaintNotifier = ValueNotifier<bool>(false);

  // Camera lifecycle. Every start and stop bumps _generation, and anything
  // async checks it is still current before touching state, so a stop that
  // lands mid-start (a preset switch, the app going to the background) cannot
  // leave two controllers alive or resurrect a stale one.
  int _generation = 0;
  bool _resumeCamera = false;

  /// camerax's dispose(cameraId) ignores the id and unbinds whichever camera
  /// is current (camera_android_camerax 0.7.2), so a controller initialised
  /// while another is still being disposed gets unbound from under it. Every
  /// dispose is chained onto this, and every start waits for it.
  static Future<void> _pendingDispose = Future.value();

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

  // Phase 0 measurements.
  static const _logEvery = Duration(seconds: 5);
  static const _sweepConfigs = [
    (ResolutionPreset.max, 4),
    (ResolutionPreset.max, 3),
    (ResolutionPreset.max, 2),
  ];
  // Two rounds, so each configuration is measured early and late: thermal
  // drift over the run then shows up as a round-to-round difference instead
  // of passing for a difference between configurations.
  static const _sweepRounds = 2;
  static const _sweepStep = Duration(seconds: 30);

  var _win = _Window();
  final _sinceConfig = Stopwatch()..start();
  Timer? _logTimer;
  String _lastWindow = '';
  Size? _streamSize;
  bool _streamLogged = false;
  bool _switching = false;
  int _sweepId = 0;
  bool _sweeping = false;
  bool _capturing = false;
  int _captures = 0;
  ui.Image? _still;
  List<Offset> _stillCorners = const [];
  String _stillInfo = '';
  double _refreshRate = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final displays = WidgetsBinding.instance.platformDispatcher.displays;
    if (displays.isNotEmpty && displays.first.refreshRate > 0) {
      _refreshRate = displays.first.refreshRate;
    }
    _logTimer = Timer.periodic(_logEvery, (_) => _flushWindow());
    _setup();
  }

  void _log(String kind, Map<String, Object?> fields) {
    debugPrint('PHASE0 kind=$kind '
        '${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}');
  }

  Future<void> _setup() async {
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      if (mounted) setState(() => _error = 'Camera permission was denied.');
      return;
    }

    final cameras = await availableCameras();
    _camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    if (_disposed) return;

    await _loadModel(_threads);
    await _startCamera();
  }

  Future<void> _loadModel(int threads) async {
    final old = _model;
    _model = null; // no new frames go to it...
    old?.dispose(); // ...and it is freed once its in-flight frame is done
    final sw = Stopwatch()..start();
    try {
      final model = await DocumentModel.load(threads: threads);
      _log('model_load', {'threads': threads, 'ms': sw.elapsedMilliseconds});
      if (_disposed) {
        model.dispose();
        return;
      }
      _model = model;
      _threads = threads;
    } catch (e) {
      if (mounted) setState(() => _inferenceError = 'model load failed: $e');
    }
  }

  Future<void> _startCamera() async {
    final camera = _camera;
    if (camera == null) return;
    final gen = ++_generation;
    await _pendingDispose;
    if (gen != _generation || _disposed) return;

    final controller = CameraController(
      camera,
      _preset,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    final sw = Stopwatch()..start();
    try {
      await controller.initialize();
    } catch (e) {
      _disposeController(controller);
      if (gen == _generation && mounted) {
        setState(() => _error = 'Camera init failed: $e');
      }
      return;
    }
    final initMs = sw.elapsedMilliseconds;
    if (gen != _generation || _disposed) {
      _disposeController(controller);
      return;
    }

    final previewSize = controller.value.previewSize!;
    _sourceSize = rotatedFrameSize(
      camera.sensorOrientation,
      previewSize.width.toInt(),
      previewSize.height.toInt(),
    );
    _streamLogged = false;
    _streamSize = null;
    await controller.startImageStream((image) => _onFrame(image, gen));
    if (gen != _generation || _disposed) {
      _disposeController(controller);
      return;
    }
    _log('camera_start', {
      'preset': _preset.name,
      'preview': '${previewSize.width.toInt()}x${previewSize.height.toInt()}',
      'initMs': initMs,
    });
    if (mounted) setState(() => _controller = controller);
  }

  Future<void> _stopCamera() {
    _generation++;
    final controller = _controller;
    _controller = null;
    if (controller == null) return _pendingDispose;
    if (mounted && !_disposed) setState(() {});
    return _disposeController(controller);
  }

  static Future<void> _disposeController(CameraController controller) {
    return _pendingDispose = _pendingDispose.then((_) async {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
    });
  }

  /// Switches camera preset and/or thread count, starting a fresh measurement
  /// window so no window mixes two configurations.
  Future<void> _applyConfig(ResolutionPreset preset, int threads) async {
    if (_switching || _disposed) return;
    setState(() => _switching = true);
    _flushWindow();
    try {
      if (threads != _threads || _model == null) await _loadModel(threads);
      if (preset != _preset || _controller == null) {
        _preset = preset;
        await _stopCamera();
        await _startCamera();
      }
    } finally {
      _recent.clear();
      _recentWallUs.clear();
      _win = _Window();
      _sinceConfig.reset();
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _toggleSweep() async {
    if (_sweeping) {
      _sweepId++;
      setState(() => _sweeping = false);
      _log('sweep_cancel', {});
      return;
    }
    final id = ++_sweepId;
    setState(() => _sweeping = true);
    _log('sweep_start', {
      'configs': _sweepConfigs.map((c) => '${c.$1.name}/${c.$2}').join(','),
      'rounds': _sweepRounds,
      'stepS': _sweepStep.inSeconds,
    });
    for (var round = 0; round < _sweepRounds; round++) {
      for (final (preset, threads) in _sweepConfigs) {
        if (id != _sweepId || _disposed) return;
        _log('sweep_step', {'round': round, 'preset': preset.name, 'threads': threads});
        await _applyConfig(preset, threads);
        await Future<void>.delayed(_sweepStep);
      }
    }
    if (id != _sweepId || _disposed) return;
    _flushWindow();
    _log('sweep_end', {});
    setState(() => _sweeping = false);
  }

  void _onFrame(CameraImage image, int gen) {
    if (gen != _generation || _disposed) return;
    _win.delivered++;
    if (!_streamLogged) {
      _streamLogged = true;
      _streamSize = Size(image.width.toDouble(), image.height.toDouble());
      _log('stream', {
        'preset': _preset.name,
        'size': '${image.width}x${image.height}',
        'format': image.format.group.name,
        // bytesPerRow/bytesPerPixel/length per plane
        'planes': image.planes
            .map((p) => '${p.bytesPerRow}/${p.bytesPerPixel}/${p.bytes.length}')
            .join(','),
        'uprightPreview':
            '${_sourceSize.width.toInt()}x${_sourceSize.height.toInt()}',
      });
    }

    final model = _model;
    final camera = _camera;
    if (_busy || _switching || model == null || camera == null) return;
    _busy = true;
    final sw = Stopwatch()..start();
    model.predict(image, camera.sensorOrientation).then((det) {
      if (_disposed || !mounted || gen != _generation) return;
      setState(() {
        // null means the mask did not reduce to a plausible quadrilateral.
        // Drawing nothing is the honest response; the readout below says so,
        // so a blank overlay is distinguishable from a frozen one.
        _corners = det.corners ?? const [];
        _lastLatencyMs = sw.elapsedMilliseconds;
        _record(det, sw.elapsedMicroseconds);
      });
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

    final w = _win;
    w.detected++;
    w.yuvUs += det.yuvUs;
    w.inferUs += det.inferenceUs;
    w.postUs += det.postprocessUs;
    w.wallUs += wallUs;
    final corners = det.corners;
    if (corners == null) {
      w.noDoc++;
    } else {
      w.quads.add(corners);
    }
  }

  /// Janky: build or raster over the frame budget, Flutter DevTools' own
  /// definition. Slow: vsync to raster end over budget, which also catches a
  /// UI thread stalled before build began -- where decoding a big camera frame
  /// off the platform channel would show up.
  void _onTimings(List<FrameTiming> timings) {
    final budgetUs = 1e6 / _refreshRate;
    final w = _win;
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds;
      final raster = t.rasterDuration.inMicroseconds;
      final vsync = t.vsyncOverhead.inMicroseconds;
      w.uiFrames++;
      if (build > budgetUs || raster > budgetUs) w.jankFrames++;
      if (t.totalSpan.inMicroseconds > budgetUs) w.slowFrames++;
      w.worstBuildUs = math.max(w.worstBuildUs, build);
      w.worstRasterUs = math.max(w.worstRasterUs, raster);
      w.worstVsyncUs = math.max(w.worstVsyncUs, vsync);
    }
  }

  /// RMS wander of each corner about its own mean over the window, averaged
  /// over the four, in model-input (mask) pixels. Only meaningful with the
  /// phone and the page both held still -- otherwise it measures the motion.
  static double? _jitter(List<List<Offset>> quads) {
    if (quads.length < 3) return null;
    var total = 0.0;
    for (var k = 0; k < 4; k++) {
      var mx = 0.0, my = 0.0;
      for (final q in quads) {
        mx += q[k].dx;
        my += q[k].dy;
      }
      mx /= quads.length;
      my /= quads.length;
      var ss = 0.0;
      for (final q in quads) {
        final dx = (q[k].dx - mx) * kModelInputWidth;
        final dy = (q[k].dy - my) * kModelInputHeight;
        ss += dx * dx + dy * dy;
      }
      total += math.sqrt(ss / quads.length);
    }
    return total / 4;
  }

  void _flushWindow() {
    final w = _win;
    _win = _Window();
    final secs = w.clock.elapsedMicroseconds / 1e6;
    if (secs < 1 || _controller == null) return;
    final n = w.detected;
    String avg(int us) => n == 0 ? '-' : (us / n / 1000).toStringAsFixed(1);
    String pct(int k) =>
        w.uiFrames == 0 ? '-' : (100 * k / w.uiFrames).toStringAsFixed(1);
    final stream = _streamSize;
    final fields = <String, Object?>{
      'preset': _preset.name,
      'threads': _threads,
      'stream': stream == null ? '-' : '${stream.width.toInt()}x${stream.height.toInt()}',
      // seconds since this configuration was applied; early windows include
      // camera start-up and the model's first (slow) runs
      't': _sinceConfig.elapsed.inSeconds,
      'secs': secs.toStringAsFixed(1),
      'deliveredFps': (w.delivered / secs).toStringAsFixed(1),
      'detFps': (n / secs).toStringAsFixed(2),
      'noDoc': w.noDoc,
      'yuvMs': avg(w.yuvUs),
      'inferMs': avg(w.inferUs),
      'postMs': avg(w.postUs),
      'wallMs': avg(w.wallUs),
      'uiFrames': w.uiFrames,
      'jankPct': pct(w.jankFrames),
      'slowPct': pct(w.slowFrames),
      'worstBuildMs': (w.worstBuildUs / 1000).toStringAsFixed(1),
      'worstRasterMs': (w.worstRasterUs / 1000).toStringAsFixed(1),
      'worstVsyncMs': (w.worstVsyncUs / 1000).toStringAsFixed(1),
      'rssMB': ProcessInfo.currentRss >> 20,
      'jitterPx': _jitter(w.quads)?.toStringAsFixed(2) ?? '-',
    };
    _log('window', fields);
    if (mounted) {
      setState(() => _lastWindow =
          '${fields['deliveredFps']} fps in, ${fields['detFps']} det/s, '
          'jank ${fields['jankPct']}%, ${fields['rssMB']} MB');
    }
  }

  /// Takes one photo the way the real capture flow would, timing each step,
  /// and checks what the decoded still looks like.
  Future<void> _captureTest() async {
    final controller = _controller;
    if (controller == null || _capturing || _switching) return;
    final gen = _generation;
    setState(() => _capturing = true);
    final sw = Stopwatch()..start();
    int lap() {
      final t = sw.elapsedMilliseconds;
      sw.reset();
      return t;
    }

    String? path;
    try {
      await controller.stopImageStream();
      final stopMs = lap();
      path = (await controller.takePicture()).path;
      final takeMs = lap();
      final bytes = await File(path).readAsBytes();
      final readMs = lap();
      // The engine's decoder applies the EXIF orientation itself (Skia's
      // codec reads it), so this image should already be upright -- the
      // thumbnail shows whether it is.
      final image = await bytesToImage(bytes);
      final decodeMs = lap();

      // The detection the real flow runs on the photo before opening the
      // corner editor. The stream is stopped, so the model is free.
      List<Offset>? stillCorners;
      int? detectMs;
      final model = _model;
      if (model != null) {
        stillCorners = await model.detectImage(image);
        detectMs = lap();
      }
      // Kept where `adb pull` reaches it, to rerun the same photo through
      // ml/ on the host and compare corners.
      final kept = await _keepCapture(bytes, _captures + 1);
      lap();

      final exif = await Exif.fromPath(path);
      final orientation = await exif.getAttribute<String>('Orientation');
      final storedW = await exif.getAttribute<String>('ImageWidth');
      final storedH = await exif.getAttribute<String>('ImageLength');
      await exif.close();
      lap();

      final fields = <String, Object?>{
        'n': ++_captures,
        'preset': _preset.name,
        'stopMs': stopMs,
        'takeMs': takeMs,
        'readMs': readMs,
        'decodeMs': decodeMs,
        'sumMs': stopMs + takeMs + readMs + decodeMs,
        'fileKB': bytes.length >> 10,
        'stored': '${storedW}x$storedH',
        'exifOrientation': orientation,
        'decoded': '${image.width}x${image.height}',
        'stillAspect': (image.width / image.height).toStringAsFixed(3),
        'previewAspect':
            (_sourceSize.width / _sourceSize.height).toStringAsFixed(3),
        'rssMB': ProcessInfo.currentRss >> 20,
        'detectMs': detectMs ?? '-',
        'stillCorners': stillCorners == null
            ? 'none'
            : stillCorners
                .map((c) => '${c.dx.toStringAsFixed(4)},${c.dy.toStringAsFixed(4)}')
                .join(';'),
        'kept': kept ?? '-',
      };
      _log('capture', fields);
      _still?.dispose();
      _still = image;
      _stillCorners = stillCorners ?? const [];
      _stillInfo = '#${fields['n']} ${fields['decoded']} '
          'exif ${fields['exifOrientation']}\n'
          'take ${fields['takeMs']} decode ${fields['decodeMs']} '
          'detect ${fields['detectMs']} ms';
    } catch (e) {
      _log('capture_error', {'error': '$e'.replaceAll(' ', '_')});
      _stillInfo = 'capture failed: $e';
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (gen == _generation && !_disposed && _controller == controller) {
        final restart = Stopwatch()..start();
        await controller.startImageStream((image) => _onFrame(image, gen));
        _log('stream_restart', {'ms': restart.elapsedMilliseconds});
      }
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<String?> _keepCapture(List<int> bytes, int n) async {
    final dir = await getExternalStorageDirectory();
    if (dir == null) return null;
    final file = File('${dir.path}/phase0/capture_$n.jpg');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  String _statsText() {
    final header = '${_preset.name} x$_threads'
        '${_streamSize == null ? '' : '  stream ${_streamSize!.width.toInt()}x${_streamSize!.height.toInt()}'}'
        '${_lastWindow.isEmpty ? '' : '\n$_lastWindow'}';
    if (_recent.isEmpty) return '$header\nwaiting for first frame...';
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
      header,
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
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        if (_controller != null) {
          _resumeCamera = true;
          _stopCamera();
        }
      case AppLifecycleState.resumed:
        if (_resumeCamera) {
          _resumeCamera = false;
          _startCamera();
        }
      default:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sweepId++;
    _logTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _stopCamera();
    _model?.dispose();
    _still?.dispose();
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
    final busyUi = _switching || _sweeping || _capturing;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _lastLatencyMs == null
              ? 'Live preview (debug)'
              : '${_corners.isEmpty ? "no doc" : "tracking"}  ${_lastLatencyMs}ms',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: busyUi
                ? null
                : () => _applyConfig(
                    _preset == ResolutionPreset.max
                        ? ResolutionPreset.medium
                        : ResolutionPreset.max,
                    _threads),
            child: Text(_preset == ResolutionPreset.max ? 'MAX' : 'MED'),
          ),
          TextButton(
            onPressed: busyUi
                ? null
                : () => _applyConfig(_preset, _threads <= 2 ? 4 : _threads - 1),
            child: Text('x$_threads'),
          ),
          IconButton(
            tooltip: 'A/B sweep',
            icon: Icon(_sweeping ? Icons.stop : Icons.play_arrow),
            onPressed: _switching || _capturing ? null : _toggleSweep,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Test capture',
        onPressed: busyUi || controller == null ? null : _captureTest,
        child: _capturing
            ? const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator())
            : const Icon(Icons.camera),
      ),
      body: controller == null || !controller.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
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
                      // Fills the bars kPreviewFit = contain leaves around the
                      // frame, black as in any camera viewfinder.
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
                          // Tap to collapse: the full panel covers a fair slice
                          // of the preview, which gets in the way when aiming.
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
                              style: _mono,
                            ),
                          ),
                        ),
                      ),
                      if (_still != null)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _still?.dispose();
                              _still = null;
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              color: Colors.black.withValues(alpha: 0.72),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 120,
                                    height: 160,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        RawImage(image: _still, fit: BoxFit.contain),
                                        // mapCornersToWidget fits with
                                        // contain, as the RawImage does.
                                        if (_stillCorners.length == 4)
                                          CustomPaint(
                                            painter: BorderPainter(
                                              color: Colors.lightGreenAccent,
                                              cornerSize: 6.0,
                                              cornerLineThickness: 1.5,
                                              points: mapCornersToWidget(
                                                normalizedCorners: _stillCorners,
                                                sourceSize: Size(
                                                  _still!.width.toDouble(),
                                                  _still!.height.toDouble(),
                                                ),
                                                destinationSize: const Size(120, 160),
                                              ),
                                              notifier: _repaintNotifier,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(_stillInfo, style: _mono),
                                ],
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
                              style: const TextStyle(
                                  color: Colors.orangeAccent, fontSize: 12),
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

  static const _mono = TextStyle(
    color: Colors.white,
    fontSize: 10.5,
    fontFamily: 'monospace',
    height: 1.25,
  );
}
