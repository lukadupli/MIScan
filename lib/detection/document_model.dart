import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:ffi/ffi.dart' show malloc;
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

typedef _Inference = ({
  Float32List logits,
  int tensorUs,
  int inferenceUs,
  int unpackUs,
});

/// Wraps the segmentation.onnx session (see ml/export.py).
///
/// The app uses one instance, from [shared], for the camera stream and for
/// photos alike: creating the session costs ~0.8 s and the first inference
/// runs several times slower than the rest, so both are paid once. The debug
/// pages [load] their own instead, to try other settings.
class DocumentModel {
  static bool _envInitialized = false;
  static Future<DocumentModel>? _shared;

  final OrtSession _session;
  final bool _isShared;
  final _yuv = YuvConverter();

  /// Input buffer for photos. The camera path has its own, inside [_yuv].
  final ffi.Pointer<ffi.Float> _stillInput = malloc<ffi.Float>(kModelInputLength);

  /// End of the queue every inference runs on -- see [_exclusive].
  Future<void> _tail = Future.value();
  bool _disposed = false;

  DocumentModel._(this._session, {bool isShared = false}) : _isShared = isShared;

  /// XNNPACK threads. 2 on a SM-A137F: with the camera streaming alongside, 4
  /// threads ran inference ~13% faster (116 vs 134 ms) but made 12-13% of UI
  /// frames janky, against 0.5-1.5% for 2 -- for a detection rate nobody can
  /// tell apart (6.75 vs 6.0 a second). 8 threads were slower than 4 even
  /// without the camera: on 8 small cores, a parallel kernel waits on
  /// whichever thread got preempted. Re-tune with the live preview's thread
  /// switch and the execution-provider page (lib/debug/) on other devices.
  static const xnnpackThreads = 2;

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

  /// A new model of its own, for the debug pages; the caller must [dispose]
  /// it. Everything else should use [shared].
  static Future<DocumentModel> load({
    String assetPath = 'assets/models/segmentation.onnx',
    int threads = xnnpackThreads,
  }) =>
      _load(assetPath: assetPath, threads: threads);

  static Future<DocumentModel> _load({
    required String assetPath,
    required int threads,
    bool isShared = false,
  }) async {
    if (!_envInitialized) {
      OrtEnv.instance.init();
      _envInitialized = true;
    }
    final raw = await rootBundle.load(assetPath);
    final bytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    final options = xnnpackOptions(threads);
    final session = OrtSession.fromBuffer(bytes, options);
    options.release(); // ORT copies what it needs into the session
    return DocumentModel._(session, isShared: isShared);
  }

  /// The app-wide model: loaded and warmed up by the first caller, then kept
  /// for the life of the app. Never dispose it.
  ///
  /// If loading fails, the next call tries again rather than handing back the
  /// same failure forever. Where there is no ORT build for the CPU (x86_64
  /// emulators, ChromeOS), it always fails; callers treat that as "no
  /// detection" and fall back to manual corners.
  static Future<DocumentModel> shared() => _shared ??= _loadShared();

  static Future<DocumentModel> _loadShared() async {
    try {
      final model = await _load(
        assetPath: 'assets/models/segmentation.onnx',
        threads: xnnpackThreads,
        isShared: true,
      );
      await model._warmUp();
      return model;
    } catch (_) {
      _shared = null;
      rethrow;
    }
  }

  /// Runs [body] once every inference queued before it has finished.
  ///
  /// The plugin's runAsync is not safe to overlap: concurrent calls share one
  /// broadcast result stream, so each can take the other's output and a
  /// tensor gets released twice (onnxruntime 1.4.1, ort_isolate_session.dart).
  /// The camera stream and a photo can both want the model at once, so every
  /// inference goes through here. The queue also guards the input buffers,
  /// which ORT reads in place while it runs.
  Future<T> _exclusive<T>(Future<T> Function() body) {
    if (_disposed) throw StateError('DocumentModel used after dispose()');
    final run = _tail.then((_) => body());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// One inference on [input], 3 x [kModelInputHeight] x [kModelInputWidth]
  /// floats in native memory that ORT reads in place. Call within [_exclusive].
  Future<_Inference> _infer(ffi.Pointer<ffi.Float> input) async {
    final sw = Stopwatch()..start();
    int lap() {
      final t = sw.elapsedMicroseconds;
      sw.reset();
      return t;
    }

    final tensor = wrapFloat32Tensor(
      input,
      const [1, 3, kModelInputHeight, kModelInputWidth],
    );
    final tensorUs = lap();
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = await _session.runAsync(runOptions, {'image': tensor});
      final inferenceUs = lap();
      final logits = readFloat32Output(
        outputs![0]!,
        kModelInputHeight * kModelInputWidth,
      );
      return (
        logits: logits,
        tensorUs: tensorUs,
        inferenceUs: inferenceUs,
        unpackUs: lap(),
      );
    } finally {
      tensor.release();
      runOptions.release();
      outputs?.forEach((o) => o?.release());
    }
  }

  /// The first run on XNNPACK is several times slower than the rest (~300 vs
  /// ~120 ms on a SM-A137F) -- so it happens here, on a blank input, instead of
  /// on the user's first frame or photo.
  Future<void> _warmUp() => _exclusive(() async {
        _stillInput.asTypedList(kModelInputLength).fillRange(0, kModelInputLength, 0);
        await _infer(_stillInput);
      });

  static List<Offset> _normalise(List<Offset> maskPoints) => [
        for (final p in maskPoints)
          Offset(p.dx / kModelInputWidth, p.dy / kModelInputHeight),
      ];

  /// Runs one camera frame through the model.
  ///
  /// The model emits a per-pixel mask; maskToQuad turns it into the quad. That
  /// second step is ordinary geometry rather than anything learned, which is
  /// what lets the network stop caring which corner is "corner 0" and so
  /// handle a page at any rotation.
  ///
  /// The network is fed the frame as the sensor delivers it -- landscape 4:3,
  /// the shape of its input -- and only the four corners are rotated upright
  /// afterwards. Rotating the frame first would hand it a 3:4 portrait image
  /// squashed into 4:3. Corners come back upright in TL, TR, BR, BL order,
  /// the order FrameController uses by default.
  Future<Detection> predict(CameraImage image, int sensorOrientationDeg) =>
      _exclusive(() async {
        final sw = Stopwatch()..start();
        _yuv.convert(image, 0);
        final yuvUs = sw.elapsedMicroseconds;
        final run = await _infer(_yuv.output);
        sw.reset();
        final stats = MaskToQuadStats();
        final quad = maskToQuad(
          run.logits,
          kModelInputWidth,
          kModelInputHeight,
          stats: stats,
        );
        return Detection(
          corners: quad == null
              ? null
              : sensorToUpright(_normalise(quad), sensorOrientationDeg),
          yuvUs: yuvUs,
          tensorUs: run.tensorUs,
          inferenceUs: run.inferenceUs,
          unpackUs: run.unpackUs,
          postprocessUs: sw.elapsedMicroseconds,
          mask: stats,
        );
      });

  /// Finds the page in a photo: its corners normalised to [image] (which must
  /// be upright, as the engine decodes it), TL, TR, BR, BL -- or null when
  /// there is no plausible page. Throws if inference itself fails.
  ///
  /// A portrait photo goes in turned a quarter anticlockwise, which is how the
  /// camera sensor saw it, so it reaches the network landscape like the camera
  /// stream does and for the same reason (see [predict]). Its corners come
  /// back through the same mapping.
  Future<List<Offset>?> detectImage(ui.Image image) async {
    final portrait = image.height > image.width;
    final small = await _drawForModel(image, rotate: portrait);
    final ByteData? rgba;
    try {
      rgba = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      small.dispose();
    }
    if (rgba == null) throw StateError('could not read back the scaled photo');
    final pixels = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);

    return _exclusive(() async {
      rgbaToChw(pixels, _stillInput);
      final run = await _infer(_stillInput);
      final quad = maskToQuad(run.logits, kModelInputWidth, kModelInputHeight);
      if (quad == null) return null;
      return sensorToUpright(_normalise(quad), portrait ? 90 : 0);
    });
  }

  /// [image] scaled to the network's input over white, turned a quarter
  /// anticlockwise first if [rotate].
  ///
  /// The GPU does the scaling. FilterQuality.medium samples from mipmaps, so a
  /// 12 MP photo is averaged down rather than point-sampled -- close to the
  /// area filter training resized with. White fills anything transparent,
  /// which also makes the premultiplied rawRgba readback plain RGB.
  static Future<ui.Image> _drawForModel(ui.Image image, {required bool rotate}) async {
    const out = Size(kModelInputWidth + 0.0, kModelInputHeight + 0.0);
    final w = image.width.toDouble(), h = image.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(Offset.zero & out, Paint()..color = const Color(0xFFFFFFFF));
    if (rotate) {
      // (x, y) -> (y, w - x): a quarter turn anticlockwise into an h x w
      // frame -- the inverse of sensorToUpright at 90 degrees -- then scaled.
      canvas
        ..scale(out.width / h, out.height / w)
        ..translate(0, w)
        ..rotate(-math.pi / 2);
    } else {
      canvas.scale(out.width / w, out.height / h);
    }
    canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(kModelInputWidth, kModelInputHeight);
    } finally {
      picture.dispose();
    }
  }

  /// Frees the session and buffers once any queued inference has finished,
  /// rather than out from under it. Only for models from [load].
  void dispose() {
    assert(!_isShared, 'the shared DocumentModel lives as long as the app');
    if (_disposed || _isShared) return;
    _disposed = true;
    _tail.whenComplete(_release).ignore();
  }

  void _release() {
    _session.release();
    _yuv.dispose();
    malloc.free(_stillInput);
  }
}
