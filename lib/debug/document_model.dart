import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

import 'frame_math.dart';
import 'mask_to_quad.dart';
import 'ort_tensor_io.dart';

/// One frame's result, plus where the time went. The timings exist to answer
/// "what is actually slow" with numbers: pure inference benchmarks at a flat
/// cost, but the live preview's total swings with content, so the variable
/// part has to be somewhere in the Dart around it.
class Detection {
  /// Four corners normalised to [0,1] of the upright frame, TL/TR/BR/BL, or
  /// null when no document was found.
  final List<Offset>? corners;

  /// YUV planes -> normalised CHW floats (native, plus copying the planes in
  /// and the result out).
  final int yuvUs;

  /// Wrapping the converted frame as an ORT tensor. It is not copied: ORT
  /// reads the converter's native buffer in place.
  final int tensorUs;

  /// Wall time of runAsync, including the hop to ORT's worker isolate and back
  /// -- that round trip is part of what the preview waits for.
  final int inferenceUs;

  /// Getting the mask out of ORT's native buffer into a Float32List.
  final int unpackUs;

  /// maskToQuad in total; [mask] has the breakdown.
  final int postprocessUs;

  final MaskToQuadStats mask;

  const Detection({
    required this.corners,
    required this.yuvUs,
    required this.tensorUs,
    required this.inferenceUs,
    required this.unpackUs,
    required this.postprocessUs,
    required this.mask,
  });
}

/// Wraps the segmentation.onnx session (see ml/export.py). Created once per
/// debug screen visit and reused across frames -- session creation is
/// expensive, inference is not.
class DocumentModel {
  static bool _envInitialized = false;
  final OrtSession _session;
  final _yuv = YuvConverter();

  /// The frame currently being run, if any. [dispose] waits for it: ORT's
  /// worker isolate reads [_yuv]'s buffer in place during inference, and the
  /// session has to outlive the run as well, so neither may be freed mid-frame.
  Future<Detection>? _inFlight;
  bool _disposed = false;

  DocumentModel._(this._session);

  /// XNNPACK threads for the live model. 4 beat 8 on a SM-A137F (116 vs 147 ms)
  /// -- 8 threads on 8 small cores leaves nothing for the camera and UI, and a
  /// parallel kernel waits on whichever thread got preempted. Re-tune with the
  /// execution-provider page (lib/debug/benchmark_page.dart) on other devices.
  static const xnnpackThreads = 4;

  /// Session options that run the graph on XNNPACK with [threads] threads.
  ///
  /// XNNPACK has its own thread pool, so ORT's own pool must be 1: two pools
  /// competing for the same cores is ORT's documented way to make XNNPACK
  /// slow. The plugin's appendXnnpackProvider() hands XNNPACK whatever value
  /// setIntraOpNumThreads() last received, so it is the order of these three
  /// calls that gives XNNPACK [threads] and ORT one. Do not reorder them.
  ///
  /// On a SM-A137F this ran inference 2.2x faster than the default CPU path
  /// (116 vs 254 ms), with logits within 1.4e-5 and no mask pixel changed.
  /// That phone runs a 32-bit userspace, where ORT's own CPU kernels are weak
  /// and XNNPACK's are not; the gap may be smaller on 64-bit devices.
  static OrtSessionOptions xnnpackOptions(int threads) => OrtSessionOptions()
    ..setIntraOpNumThreads(threads)
    ..appendXnnpackProvider()
    ..setIntraOpNumThreads(1);

  static Future<DocumentModel> load({
    String assetPath = 'assets/models/segmentation.onnx',
  }) async {
    if (!_envInitialized) {
      OrtEnv.instance.init();
      _envInitialized = true;
    }
    final raw = await rootBundle.load(assetPath);
    final bytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    final options = xnnpackOptions(xnnpackThreads);
    final session = OrtSession.fromBuffer(bytes, options);
    options.release(); // ORT copies what it needs into the session
    return DocumentModel._(session);
  }

  /// Runs one camera frame through the model.
  ///
  /// The model emits a per-pixel mask; maskToQuad turns it into the quad. That
  /// second step is ordinary geometry rather than anything learned, which is
  /// what lets the network stop caring which corner is "corner 0" and so
  /// handle a page at any rotation. Corners come back in TL, TR, BR, BL order
  /// -- the order FrameController uses by default, so no reordering is needed.
  Future<Detection> predict(CameraImage image, int sensorOrientationDeg) {
    if (_disposed) throw StateError('predict() called after dispose()');
    final run = _predict(image, sensorOrientationDeg);
    _inFlight = run;
    return run;
  }

  Future<Detection> _predict(CameraImage image, int sensorOrientationDeg) async {
    final sw = Stopwatch()..start();
    int lap() {
      final t = sw.elapsedMicroseconds;
      sw.reset();
      return t;
    }

    _yuv.convert(image, sensorOrientationDeg);
    final yuvUs = lap();
    final inputTensor = wrapFloat32Tensor(
      _yuv.output,
      const [1, 3, kModelInputHeight, kModelInputWidth],
    );
    final tensorUs = lap();
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = await _session.runAsync(runOptions, {'image': inputTensor});
      final inferenceUs = lap();
      final logits = readFloat32Output(
        outputs![0]!,
        kModelInputHeight * kModelInputWidth,
      );
      final unpackUs = lap();
      final stats = MaskToQuadStats();
      final quad = maskToQuad(
        logits,
        kModelInputWidth,
        kModelInputHeight,
        stats: stats,
      );
      final postprocessUs = lap();
      return Detection(
        corners: quad == null
            ? null
            : [
                for (final p in quad)
                  Offset(p.dx / kModelInputWidth, p.dy / kModelInputHeight),
              ],
        yuvUs: yuvUs,
        tensorUs: tensorUs,
        inferenceUs: inferenceUs,
        unpackUs: unpackUs,
        postprocessUs: postprocessUs,
        mask: stats,
      );
    } finally {
      inputTensor.release();
      runOptions.release();
      outputs?.forEach((o) => o?.release());
    }
  }

  /// Frees the session and buffers -- after the in-flight frame if there is
  /// one, rather than out from under it.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final pending = _inFlight;
    if (pending == null) {
      _release();
    } else {
      // Any error on that frame has already gone to predict()'s caller.
      pending.whenComplete(_release).ignore();
    }
  }

  void _release() {
    _session.release();
    _yuv.dispose();
  }
}
