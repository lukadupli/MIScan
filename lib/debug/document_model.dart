import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

import 'frame_math.dart';
import 'mask_to_quad.dart';

/// Wraps the corners.onnx session (see ml/export.py). Created once per debug
/// screen visit and reused across frames -- session creation is expensive,
/// inference is not.
class DocumentModel {
  static bool _envInitialized = false;
  final OrtSession _session;

  DocumentModel._(this._session);

  static Future<DocumentModel> load({
    String assetPath = 'assets/models/segmentation.onnx',
  }) async {
    if (!_envInitialized) {
      OrtEnv.instance.init();
      _envInitialized = true;
    }
    final raw = await rootBundle.load(assetPath);
    final bytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    final session = OrtSession.fromBuffer(bytes, OrtSessionOptions());
    return DocumentModel._(session);
  }

  /// Runs one camera frame through the model. Returns 4 corners normalised to
  /// [0,1] of the upright frame, in TL, TR, BR, BL order -- the order
  /// FrameController uses by default, so no reordering is needed here -- or
  /// null when no document was found.
  ///
  /// The model emits a per-pixel mask; maskToQuad turns it into the quad. That
  /// second step is ordinary geometry rather than anything learned, which is
  /// what lets the network stop caring which corner is "corner 0" and so
  /// handle a page at any rotation.
  Future<List<Offset>?> predict(
    CameraImage image,
    int sensorOrientationDeg,
  ) async {
    final tensorData = yuv420ToChwTensor(image, sensorOrientationDeg);
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      tensorData,
      [1, 3, kModelInputHeight, kModelInputWidth],
    );
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = await _session.runAsync(runOptions, {'image': inputTensor});
      final logits = _flatten(outputs![0]!.value);
      final quad = maskToQuad(logits, kModelInputWidth, kModelInputHeight);
      if (quad == null) return null;
      return [
        for (final p in quad)
          Offset(p.dx / kModelInputWidth, p.dy / kModelInputHeight),
      ];
    } finally {
      inputTensor.release();
      runOptions.release();
      outputs?.forEach((o) => o?.release());
    }
  }

  /// ORT hands back the [1,1,H,W] output as nested lists. Walk down to the
  /// innermost row dimension and copy the whole plane out flat.
  Float32List _flatten(dynamic value) {
    final out = Float32List(kModelInputHeight * kModelInputWidth);
    var written = 0;
    void walk(dynamic v) {
      if (v is List) {
        if (v.isNotEmpty && v.first is! List) {
          for (final e in v) {
            if (written < out.length) out[written++] = (e as num).toDouble();
          }
        } else {
          for (final e in v) {
            walk(e);
          }
        }
      } else if (written < out.length) {
        out[written++] = (v as num).toDouble();
      }
    }

    walk(value);
    assert(
      written == out.length,
      'expected ${out.length} mask values, got $written -- model output shape '
      'does not match kModelInputHeight/Width',
    );
    return out;
  }

  void dispose() => _session.release();
}
