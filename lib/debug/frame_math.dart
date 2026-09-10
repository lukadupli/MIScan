import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:ffi/ffi.dart' show malloc;
import 'package:flutter/material.dart';

/// Contract enforced here has to match ml/common.py's INPUT_SIZE exactly, or
/// the model sees input unlike anything it was trained on and returns garbage.
/// Not square: 4:3 matches the camera, so nothing is stretched on the way in.
const int kModelInputHeight = 240;
const int kModelInputWidth = 320;
const List<double> kImagenetMean = [0.485, 0.456, 0.406];
const List<double> kImagenetStd = [0.229, 0.224, 0.225];

/// Size of the camera frame once rotated upright, given the sensor's
/// mounting angle. Width/height swap for a 90/270 sensor orientation.
Size rotatedFrameSize(int sensorOrientationDeg, int rawWidth, int rawHeight) {
  final swapped = sensorOrientationDeg == 90 || sensorOrientationDeg == 270;
  return swapped
      ? Size(rawHeight.toDouble(), rawWidth.toDouble())
      : Size(rawWidth.toDouble(), rawHeight.toDouble());
}

typedef _YuvToChwNative = ffi.Void Function(
    ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Int32,
    ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Int32,
    ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Int32,
    ffi.Int32, ffi.Int32, ffi.Int32,
    ffi.Pointer<ffi.Float>, ffi.Int32, ffi.Int32,
    ffi.Pointer<ffi.Double>);
typedef _YuvToChwDart = void Function(
    ffi.Pointer<ffi.Uint8>, int, int,
    ffi.Pointer<ffi.Uint8>, int, int,
    ffi.Pointer<ffi.Uint8>, int, int,
    int, int, int,
    ffi.Pointer<ffi.Float>, int, int,
    ffi.Pointer<ffi.Double>);

/// native/image_processing/yuv_to_tensor.cpp.
final _yuvToChw = (Platform.isAndroid
        ? ffi.DynamicLibrary.open('libimage_processing.so')
        : ffi.DynamicLibrary.process())
    .lookupFunction<_YuvToChwNative, _YuvToChwDart>('YuvToChwTensor');

/// Converts camera frames into the network's input: a normalised, upright,
/// resized CHW float tensor of 3 * [kModelInputHeight] * [kModelInputWidth].
///
/// The work happens in native/image_processing/yuv_to_tensor.cpp, which walks
/// each output pixel back to its source sample in one pass: output -> upright
/// frame (plain per-axis resize) -> raw sensor buffer (inverse of the sensor's
/// mounting rotation) -> nearest Y/U/V sample, respecting each plane's own
/// row and pixel stride. Doing this in Dart cost ~90 ms a frame.
///
/// The camera's planes are Dart-heap byte arrays, so they have to be copied
/// into native memory for the call. That buffer, and the output one, are
/// allocated once and reused: the frame size does not change during a
/// session, so per frame this is a few hundred KB of memcpy rather than a round
/// of allocations.
///
/// The result stays in native memory, at [output], where ORT can read it in
/// place (see wrapFloat32Tensor) instead of having it copied back into Dart and
/// then out again. Call [dispose] when finished.
class YuvConverter {
  static const _outLength = 3 * kModelInputHeight * kModelInputWidth;

  final ffi.Pointer<ffi.Float> _out = malloc<ffi.Float>(_outLength);
  final ffi.Pointer<ffi.Double> _norm = malloc<ffi.Double>(6);
  final _planes = List<ffi.Pointer<ffi.Uint8>>.filled(3, ffi.nullptr);
  final _capacity = List<int>.filled(3, 0);

  YuvConverter() {
    // Per-channel means then stds: the layout YuvToChwTensor reads `norm` in.
    _norm.asTypedList(6).setAll(0, [...kImagenetMean, ...kImagenetStd]);
  }

  /// Copies plane [i] into its native buffer, growing the buffer if needed.
  ffi.Pointer<ffi.Uint8> _stage(int i, Uint8List bytes) {
    if (bytes.length > _capacity[i]) {
      if (_planes[i] != ffi.nullptr) malloc.free(_planes[i]);
      _planes[i] = malloc<ffi.Uint8>(bytes.length);
      _capacity[i] = bytes.length;
    }
    _planes[i].asTypedList(bytes.length).setAll(0, bytes);
    return _planes[i];
  }

  /// The converted frame, 3 * [kModelInputHeight] * [kModelInputWidth] floats
  /// in CHW order. Overwritten by the next [convert] and freed by [dispose],
  /// so anything reading it -- ORT, during inference -- must finish first.
  ffi.Pointer<ffi.Float> get output => _out;

  /// Converts [image] into [output].
  void convert(CameraImage image, int sensorOrientationDeg) {
    final y = image.planes[0], u = image.planes[1], v = image.planes[2];
    _yuvToChw(
      _stage(0, y.bytes), y.bytesPerRow, y.bytesPerPixel ?? 1,
      _stage(1, u.bytes), u.bytesPerRow, u.bytesPerPixel ?? 1,
      _stage(2, v.bytes), v.bytesPerRow, v.bytesPerPixel ?? 1,
      image.width, image.height, sensorOrientationDeg,
      _out, kModelInputWidth, kModelInputHeight,
      _norm,
    );
  }

  void dispose() {
    malloc.free(_out);
    malloc.free(_norm);
    for (final p in _planes) {
      if (p != ffi.nullptr) malloc.free(p);
    }
  }
}

/// How the camera frame is fitted into the preview. The single source of truth
/// for both the FittedBox that draws the video and [mapCornersToWidget] that
/// places the overlay on it: if those two ever used different fits, the quad
/// would drift off the page it was found on.
///
/// contain, not cover: the preview must show exactly what the model sees. cover
/// filled the screen by cropping the frame's sides -- ~10% each side on a
/// SM-A137F -- so the model could detect corners the user could not see, and
/// the overlay drew them off-screen.
const kPreviewFit = BoxFit.contain;

/// Maps model output corners (normalized [0,1] in the *upright rotated*
/// frame -- that's what was fed to the network) to on-screen widget pixels,
/// reproducing exactly what FittedBox(fit: [kPreviewFit]) does for the
/// preview, so the overlay and the video line up whatever the fit.
List<Offset> mapCornersToWidget({
  required List<Offset> normalizedCorners,
  required Size sourceSize,
  required Size destinationSize,
}) {
  if (sourceSize.isEmpty || destinationSize.isEmpty) return normalizedCorners;

  final fitted = applyBoxFit(kPreviewFit, sourceSize, destinationSize);
  final sourceRect =
      Alignment.center.inscribe(fitted.source, Offset.zero & sourceSize);
  final destRect = Alignment.center
      .inscribe(fitted.destination, Offset.zero & destinationSize);

  return normalizedCorners.map((c) {
    final srcPx = Offset(c.dx * sourceSize.width, c.dy * sourceSize.height);
    final relX = (srcPx.dx - sourceRect.left) / sourceRect.width;
    final relY = (srcPx.dy - sourceRect.top) / sourceRect.height;
    return Offset(
      destRect.left + relX * destRect.width,
      destRect.top + relY * destRect.height,
    );
  }).toList();
}
