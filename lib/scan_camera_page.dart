import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:miscan/l10n/app_localizations.dart';

import 'detection/document_model.dart';
import 'detection/frame_math.dart';
import 'frame.dart';
import 'loading_page.dart';
import 'main.dart';
import 'scan_input.dart';
import 'transform_page.dart';

enum _Permission { unknown, granted, denied, permanentlyDenied }

/// In-app camera with a live document overlay. The shutter takes a
/// full-resolution photo and opens [TransformPage] with the detected corners
/// (see `HANDOFF-document-detection.md`); no page found behaves exactly as if
/// detection had not run, so there is no separate "not found" UI.
class ScanCameraPage extends StatefulWidget {
  const ScanCameraPage({super.key});

  @override
  State<ScanCameraPage> createState() => _ScanCameraPageState();
}

class _ScanCameraPageState extends State<ScanCameraPage>
    with WidgetsBindingObserver, RouteAware {
  CameraDescription? _camera;
  CameraController? _controller;
  DocumentModel? _model;
  FlashMode _flashMode = FlashMode.off;
  List<Offset> _corners = const [];
  Size _sourceSize = Size.zero;
  bool _busy = false;
  bool _capturing = false;
  bool _disposed = false;
  bool _cameraUnavailable = false;
  _Permission _permission = _Permission.unknown;
  final _repaintNotifier = ValueNotifier<bool>(false);

  // Every start and stop bumps this, and anything async checks it is still
  // current before touching state -- see LivePreviewPage, which this mirrors.
  int _generation = 0;

  /// camerax's dispose(cameraId) ignores the id and unbinds whichever camera
  /// is current, so a controller initialised while another is still being
  /// disposed gets unbound from under it. Every dispose is chained onto this,
  /// and every start waits for it.
  static Future<void> _pendingDispose = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initModel();
    _checkPermissionAndStart();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  // Coming back from the corner editor: the camera was torn down while it was
  // open (see _capture), so this is a retake.
  @override
  void didPopNext() {
    if (_controller == null && _permission == _Permission.granted) {
      _startCamera();
    }
  }

  Future<void> _initModel() async {
    try {
      final model = await DocumentModel.shared();
      if (_disposed) return;
      _model = model;
    } catch (_) {
      // No ORT build for this device/arch: detection stays off, and captures
      // fall back to full-image corners in prepareScanInput.
    }
  }

  Future<void> _checkPermissionAndStart() async {
    final status = await Permission.camera.request();
    if (_disposed || !mounted) return;
    if (status.isGranted) {
      setState(() => _permission = _Permission.granted);
      await _setupCameraDescription();
    } else if (status.isPermanentlyDenied) {
      setState(() => _permission = _Permission.permanentlyDenied);
    } else {
      setState(() => _permission = _Permission.denied);
    }
  }

  Future<void> _setupCameraDescription() async {
    try {
      final cameras = await availableCameras();
      _camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
    } catch (_) {
      _camera = null;
    }
    if (_disposed) return;
    if (_camera == null) {
      if (mounted) setState(() => _cameraUnavailable = true);
      return;
    }
    await _startCamera();
  }

  Future<void> _startCamera() async {
    final camera = _camera;
    if (camera == null) return;
    final gen = ++_generation;
    await _pendingDispose;
    if (gen != _generation || _disposed) return;

    CameraController? controller;
    // Right after the OS permission dialog is granted, CameraX can fail to
    // bind once before the grant has fully propagated to the camera service
    // -- the very next attempt succeeds. One retry absorbs that instead of
    // showing "camera unavailable" for a race that clears itself.
    for (var attempt = 0; controller == null && attempt < 2; attempt++) {
      final candidate = CameraController(
        camera,
        ResolutionPreset.max, // the patched preset -- see third_party/camera_android_camerax
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      try {
        await candidate.initialize();
        controller = candidate;
      } catch (_) {
        _disposeController(candidate);
        if (gen != _generation || _disposed) return;
        if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    if (gen != _generation || _disposed) {
      if (controller != null) _disposeController(controller);
      return;
    }
    if (controller == null) {
      if (mounted) setState(() => _cameraUnavailable = true);
      return;
    }

    try {
      await controller.setFlashMode(_flashMode);
    } catch (_) {}

    final previewSize = controller.value.previewSize!;
    final sourceSize = rotatedFrameSize(
      camera.sensorOrientation,
      previewSize.width.toInt(),
      previewSize.height.toInt(),
    );
    await controller.startImageStream((image) => _onFrame(image, gen));
    if (gen != _generation || _disposed) {
      _disposeController(controller);
      return;
    }
    if (mounted) {
      setState(() {
        _controller = controller;
        _sourceSize = sourceSize;
        _cameraUnavailable = false;
      });
    }
  }

  Future<void> _stopCamera() {
    _generation++;
    final controller = _controller;
    _controller = null;
    _corners = const [];
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
        // The plugin keeps torch state across controllers
        // (camera_android_camerax 0.7.2), so a lit torch would otherwise stay
        // on under a controller that no longer exists to turn it off.
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
    });
  }

  void _onFrame(CameraImage image, int gen) {
    if (gen != _generation || _disposed) return;
    final model = _model;
    final camera = _camera;
    if (_busy || model == null || camera == null) return;
    _busy = true;
    model.predict(image, camera.sensorOrientation).then((det) {
      if (_disposed || !mounted || gen != _generation) return;
      setState(() => _corners = det.corners ?? const []);
    }).catchError((Object _) {
      // One bad frame shouldn't take the overlay down; the next frame tries again.
    }).whenComplete(() => _busy = false);
  }

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.torch,
      FlashMode.torch || FlashMode.always => FlashMode.off,
    };
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } catch (_) {}
  }

  void _onTapToFocus(Offset localPosition, Size destinationSize) {
    final controller = _controller;
    if (controller == null) return;
    final normalized = mapWidgetToNormalized(
      point: localPosition,
      sourceSize: _sourceSize,
      destinationSize: destinationSize,
    );
    if (normalized == null) return; // tapped the letterbox bars
    controller.setFocusPoint(normalized);
    controller.setExposurePoint(normalized);
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);
    final gen = _generation;

    String path;
    try {
      await controller.stopImageStream();
      path = (await controller.takePicture()).path;
    } catch (_) {
      if (gen == _generation &&
          !_disposed &&
          controller.value.isInitialized &&
          !controller.value.isStreamingImages) {
        try {
          await controller.startImageStream((image) => _onFrame(image, gen));
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.captureFailed)),
        );
      }
      return;
    }

    // Keep the camera closed while the editor is open; pausePreview would
    // leave it bound. didPopNext restarts it on the way back for a retake.
    await _stopCamera();
    if (!mounted) return;
    setState(() => _capturing = false);
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => LoadingThen<ScanInput>(
        future: prepareScanInput(path, deleteFile: true),
        builder: (context, input) => TransformPage(image: input.image, initialCorners: input.corners),
      ),
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        if (_controller != null) _stopCamera();
      case AppLifecycleState.resumed:
        // Always re-checked, not just when a camera was running before: the
        // user may have backgrounded the app from the permission-denied
        // screen to grant it in Settings, with no controller to resume.
        if (ModalRoute.of(context)?.isCurrent ?? false) _onResumed();
      default:
        break;
    }
  }

  Future<void> _onResumed() async {
    final status = await Permission.camera.status;
    if (_disposed || !mounted) return;
    if (status.isGranted) {
      if (_permission != _Permission.granted) setState(() => _permission = _Permission.granted);
      if (_controller == null) {
        if (_camera != null) {
          await _startCamera();
        } else {
          await _setupCameraDescription();
        }
      }
    } else {
      setState(() => _permission =
          status.isPermanentlyDenied ? _Permission.permanentlyDenied : _Permission.denied);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _stopCamera();
    _repaintNotifier.dispose();
    super.dispose();
  }

  IconData _flashIcon() => switch (_flashMode) {
        FlashMode.off => Icons.flash_off,
        FlashMode.auto => Icons.flash_auto,
        FlashMode.torch || FlashMode.always => Icons.flash_on,
      };

  Widget _permissionScaffold(AppLocalizations apploc) {
    final permanentlyDenied = _permission == _Permission.permanentlyDenied;
    return Scaffold(
      appBar: AppBar(title: Text(apploc.cameraPermissionTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                permanentlyDenied
                    ? apploc.cameraPermissionDeniedContent
                    : apploc.cameraPermissionContent,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (permanentlyDenied)
                TextButton(onPressed: openAppSettings, child: Text(apploc.openSettings))
              else
                TextButton(onPressed: _checkPermissionAndStart, child: Text(apploc.tryAgain)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apploc = AppLocalizations.of(context)!;

    if (_permission == _Permission.unknown) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_permission != _Permission.granted) return _permissionScaffold(apploc);

    if (_cameraUnavailable) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              apploc.cameraUnavailable,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final destSize = constraints.biggest;
            final mapped = mapCornersToWidget(
              normalizedCorners: _corners,
              sourceSize: _sourceSize,
              destinationSize: destSize,
            );
            return GestureDetector(
              onTapUp: (details) => _onTapToFocus(details.localPosition, destSize),
              child: ClipRect(
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
                          color: Colors.white,
                          cornerSize: 28.0,
                          cornerLineThickness: 3.0,
                          points: mapped,
                          notifier: _repaintNotifier,
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        tooltip: apploc.flashTooltip,
                        icon: Icon(_flashIcon(), color: Colors.white),
                        onPressed: _cycleFlash,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 24,
                      child: Center(
                        child: FloatingActionButton(
                          tooltip: apploc.takePictureTooltip,
                          onPressed: _capturing ? null : _capture,
                          child: _capturing
                              ? const SizedBox(
                                  width: 24, height: 24, child: CircularProgressIndicator())
                              : const Icon(Icons.camera),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
