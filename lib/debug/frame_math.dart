import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Contract enforced here has to match ml/common.py exactly, or the model
/// sees input unlike anything it was trained on and returns garbage.
const int kModelInputSize = 224;
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

/// Converts one YUV420 [image] straight into a normalized, rotated, resized
/// CHW Float32 tensor of length 3*224*224 -- one pass, no intermediate
/// full-resolution buffer.
///
/// For each of the 224x224 output pixels: walk backwards through output ->
/// point in the upright rotated frame (plain per-axis resize; the aspect
/// distortion this causes on a non-square source is expected, see
/// ml/dataset.py) -> point in the raw sensor buffer (inverse of the
/// sensorOrientation rotation) -> nearest Y/U/V sample, respecting each
/// plane's own bytesPerRow/bytesPerPixel stride.
Float32List yuv420ToChwTensor(CameraImage image, int sensorOrientationDeg) {
  final w = image.width, h = image.height;
  final rot = rotatedFrameSize(sensorOrientationDeg, w, h);
  final rotW = rot.width, rotH = rot.height;

  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];
  final yPixelStride = yPlane.bytesPerPixel ?? 1;
  final uPixelStride = uPlane.bytesPerPixel ?? 1;
  final vPixelStride = vPlane.bytesPerPixel ?? 1;

  const n = kModelInputSize;
  final out = Float32List(3 * n * n);

  for (int oy = 0; oy < n; oy++) {
    final uy = (oy + 0.5) * rotH / n;
    for (int ox = 0; ox < n; ox++) {
      final ux = (ox + 0.5) * rotW / n;

      // Inverse-rotate (ux, uy) in the upright frame back into raw sensor
      // coordinates (sx, sy).
      double sxD, syD;
      switch (sensorOrientationDeg) {
        case 90:
          sxD = uy;
          syD = h - 1 - ux;
          break;
        case 270:
          sxD = w - 1 - uy;
          syD = ux;
          break;
        case 180:
          sxD = w - 1 - ux;
          syD = h - 1 - uy;
          break;
        default: // 0
          sxD = ux;
          syD = uy;
      }
      final sx = sxD.clamp(0, w - 1).toInt();
      final sy = syD.clamp(0, h - 1).toInt();

      final yVal = yPlane.bytes[sy * yPlane.bytesPerRow + sx * yPixelStride];
      final cx = sx >> 1, cy = sy >> 1;
      final uVal = uPlane.bytes[cy * uPlane.bytesPerRow + cx * uPixelStride];
      final vVal = vPlane.bytes[cy * vPlane.bytesPerRow + cx * vPixelStride];

      final yD = yVal.toDouble();
      final uD = uVal.toDouble() - 128.0;
      final vD = vVal.toDouble() - 128.0;

      final r = (yD + 1.402 * vD).clamp(0, 255);
      final g = (yD - 0.344136 * uD - 0.714136 * vD).clamp(0, 255);
      final b = (yD + 1.772 * uD).clamp(0, 255);

      final idx = oy * n + ox;
      out[0 * n * n + idx] = (r / 255.0 - kImagenetMean[0]) / kImagenetStd[0];
      out[1 * n * n + idx] = (g / 255.0 - kImagenetMean[1]) / kImagenetStd[1];
      out[2 * n * n + idx] = (b / 255.0 - kImagenetMean[2]) / kImagenetStd[2];
    }
  }
  return out;
}

/// Maps model output corners (normalized [0,1] in the *upright rotated*
/// frame -- that's what was fed to the network) to on-screen widget pixels,
/// reproducing exactly what FittedBox(fit: BoxFit.cover) does for the
/// preview, so the overlay and the video can never drift apart even when
/// cover crops part of the frame.
List<Offset> mapCornersToWidget({
  required List<Offset> normalizedCorners,
  required Size sourceSize,
  required Size destinationSize,
}) {
  if (sourceSize.isEmpty || destinationSize.isEmpty) return normalizedCorners;

  final fitted = applyBoxFit(BoxFit.cover, sourceSize, destinationSize);
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
