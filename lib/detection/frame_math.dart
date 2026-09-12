import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:ffi/ffi.dart' show malloc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

/// Contract enforced here has to match ml/common.py's INPUT_SIZE exactly, or
/// the model sees input unlike anything it was trained on and returns garbage.
/// Landscape 4:3, like the camera sensor's own frame -- which is why the model
/// is fed that frame unrotated (see DocumentModel): rotated upright, a phone
/// held in portrait gives a 3:4 frame, and squashing that into 4:3 cost
/// accuracy on SmartDoc (ml/eval.py --view portrait).
const int kModelInputHeight = 240;
const int kModelInputWidth = 320;
const List<double> kImagenetMean = [0.485, 0.456, 0.406];
const List<double> kImagenetStd = [0.229, 0.224, 0.225];

/// Floats in one network input: 3 channels of [kModelInputHeight] x
/// [kModelInputWidth].
const int kModelInputLength = 3 * kModelInputHeight * kModelInputWidth;

/// [rgba] -- [kModelInputWidth] x [kModelInputHeight] pixels, 4 bytes each,
/// alpha ignored -- into [out] as the network's input: [kModelInputLength]
/// floats, channel-major (all R, then all G, then all B), each normalised as
/// (value / 255 - mean) / std. The same layout and arithmetic as
/// yuv_to_tensor.cpp, and as ml/dataset.py does in training.
void rgbaToChw(Uint8List rgba, ffi.Pointer<ffi.Float> out) {
  const plane = kModelInputHeight * kModelInputWidth;
  if (rgba.length != plane * 4) {
    throw ArgumentError.value(
        rgba.length, 'rgba', 'expected ${plane * 4} bytes (${kModelInputWidth}x$kModelInputHeight RGBA)');
  }
  final dst = out.asTypedList(kModelInputLength);
  final r0 = kImagenetMean[0], g0 = kImagenetMean[1], b0 = kImagenetMean[2];
  final rs = kImagenetStd[0], gs = kImagenetStd[1], bs = kImagenetStd[2];
  for (var i = 0, p = 0; i < plane; i++, p += 4) {
    dst[i] = (rgba[p] / 255.0 - r0) / rs;
    dst[plane + i] = (rgba[p + 1] / 255.0 - g0) / gs;
    dst[2 * plane + i] = (rgba[p + 2] / 255.0 - b0) / bs;
  }
}

/// Size of the camera frame once rotated upright, given the sensor's
/// mounting angle. Width/height swap for a 90/270 sensor orientation.
Size rotatedFrameSize(int sensorOrientationDeg, int rawWidth, int rawHeight) {
  final swapped = sensorOrientationDeg == 90 || sensorOrientationDeg == 270;
  return swapped
      ? Size(rawHeight.toDouble(), rawWidth.toDouble())
      : Size(rawWidth.toDouble(), rawHeight.toDouble());
}

/// Corners normalised to the sensor's own (unrotated) frame -> the same
/// corners normalised to the upright frame the user sees, in the same TL, TR,
/// BR, BL order.
///
/// A rotation keeps the corners' winding but changes which one is top-left,
/// so the cycle is restarted at the corner nearest the upright origin -- what
/// maskToQuad's canonicalisation does in the frame it was given.
List<Offset> sensorToUpright(List<Offset> corners, int sensorOrientationDeg) {
  // Inverse of the sampling in yuv_to_tensor.cpp: e.g. at 90 degrees the
  // upright frame's x runs against the sensor's y.
  Offset map(Offset p) => switch (sensorOrientationDeg) {
        90 => Offset(1 - p.dy, p.dx),
        180 => Offset(1 - p.dx, 1 - p.dy),
        270 => Offset(p.dy, 1 - p.dx),
        _ => p,
      };
  final upright = corners.map(map).toList();

  // Distances in pixels, not normalised units, so "nearest" means the same as
  // it did to maskToQuad.
  final size = rotatedFrameSize(
      sensorOrientationDeg, kModelInputWidth, kModelInputHeight);
  var start = 0;
  var best = double.infinity;
  for (var i = 0; i < upright.length; i++) {
    final dx = upright[i].dx * size.width, dy = upright[i].dy * size.height;
    if (dx * dx + dy * dy < best) {
      best = dx * dx + dy * dy;
      start = i;
    }
  }
  return [
    for (var i = 0; i < upright.length; i++)
      upright[(start + i) % upright.length],
  ];
}

/// EXIF Orientation tag (1/3/6/8: 0/180/90CW/270CW correction needed --
/// EditPage's own turns<->Orientation convention, see its _turnsToOrient)
/// for a photo from a camera whose sensor is mounted at
/// [sensorOrientationDeg], taken while the phone was actually held at
/// [orientation].
///
/// Standard Android camera formula: the file needs rotating
/// (sensorOrientationDeg - targetRotationDeg) degrees clockwise to display
/// correctly, where targetRotationDeg is how far the display is presumed
/// already rotated for that device orientation -- the same mapping
/// camera_android_camerax's lockCaptureOrientation uses internally
/// (_getRotationConstantFromDeviceOrientation). ScanCameraPage locks
/// capture orientation to portraitUp once, at camera start, to keep the
/// live preview stable (re-locking per photo visibly rotates it instead),
/// which freezes what every photo is tagged with; this recovers the
/// correct tag from the live sensor reading afterwards, without touching
/// the camera controller at all.
int exifOrientationFor(int sensorOrientationDeg, DeviceOrientation orientation) {
  final targetRotationDeg = switch (orientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  return switch ((sensorOrientationDeg - targetRotationDeg + 360) % 360) {
    90 => 6,
    180 => 3,
    270 => 8,
    _ => 1,
  };
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

/// Converts camera frames into the network's input: a normalised, resized CHW
/// float tensor of 3 * [kModelInputHeight] * [kModelInputWidth].
///
/// The work happens in native/image_processing/yuv_to_tensor.cpp, which walks
/// each output pixel back to its source sample in one pass: output -> rotated
/// frame (plain per-axis resize) -> raw sensor buffer (inverse of the
/// rotation) -> nearest Y/U/V sample, respecting each plane's own row and
/// pixel stride. Doing this in Dart cost ~90 ms a frame. DocumentModel asks
/// for no rotation; the native code supports it all the same.
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
  final ffi.Pointer<ffi.Float> _out = malloc<ffi.Float>(kModelInputLength);
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

  /// Converts [image] into [output], rotated clockwise by
  /// [sensorOrientationDeg] (0, 90, 180 or 270).
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

/// Maps corners normalized [0,1] to the upright frame -- what DocumentModel
/// returns -- to on-screen widget pixels, reproducing exactly what
/// FittedBox(fit: [kPreviewFit]) does for the preview, so the overlay and the
/// video line up whatever the fit.
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

/// The inverse of [mapCornersToWidget] for one point: a position on the
/// preview widget -> normalized [0,1] coordinates in the upright frame. Null
/// when the point is on the bars [kPreviewFit] leaves around the picture, which
/// show nothing the camera can focus on.
Offset? mapWidgetToNormalized({
  required Offset point,
  required Size sourceSize,
  required Size destinationSize,
}) {
  if (sourceSize.isEmpty || destinationSize.isEmpty) return null;

  final fitted = applyBoxFit(kPreviewFit, sourceSize, destinationSize);
  final sourceRect =
      Alignment.center.inscribe(fitted.source, Offset.zero & sourceSize);
  final destRect = Alignment.center
      .inscribe(fitted.destination, Offset.zero & destinationSize);
  if (point.dx < destRect.left ||
      point.dx > destRect.right ||
      point.dy < destRect.top ||
      point.dy > destRect.bottom) {
    return null;
  }

  final relX = (point.dx - destRect.left) / destRect.width;
  final relY = (point.dy - destRect.top) / destRect.height;
  return Offset(
    (sourceRect.left + relX * sourceRect.width) / sourceSize.width,
    (sourceRect.top + relY * sourceRect.height) / sourceSize.height,
  );
}
