import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../frame.dart';
import 'corner_model.dart';
import 'frame_math.dart';

/// Debug-only screen: overlays the corner-detection model's live prediction
/// on the camera feed, so model quality can be judged in real-world use.
/// Reached only via the kDebugMode-gated icon in MyHomePage -- never part of
/// the real capture flow, so its strings are not localized.
class LivePreviewPage extends StatefulWidget {
  const LivePreviewPage({super.key});

  @override
  State<LivePreviewPage> createState() => _LivePreviewPageState();
}

class _LivePreviewPageState extends State<LivePreviewPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CornerModel? _model;
  bool _busy = false;
  bool _disposed = false;
  String? _error;
  List<Offset> _corners = const [];
  Size _sourceSize = Size.zero;
  int? _lastLatencyMs;
  final _repaintNotifier = ValueNotifier<bool>(false);

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

    _model ??= await CornerModel.load();
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
        .then((corners) {
      if (!_disposed && mounted) {
        setState(() {
          _corners = corners;
          _lastLatencyMs = sw.elapsedMilliseconds;
        });
      }
    }).catchError((_) {
      // A dropped/malformed frame shouldn't take the stream down.
    }).whenComplete(() => _busy = false);
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
            : 'Live corner preview  ${_lastLatencyMs}ms/frame'),
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
                FittedBox(
                  fit: BoxFit.cover,
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
              ],
            ),
          );
        },
      ),
    );
  }
}
