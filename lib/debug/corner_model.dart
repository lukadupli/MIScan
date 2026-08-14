import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

import 'frame_math.dart';

/// Wraps the corners.onnx session (see ml/export.py). Created once per debug
/// screen visit and reused across frames -- session creation is expensive,
/// inference is not.
class CornerModel {
  static bool _envInitialized = false;
  final OrtSession _session;

  CornerModel._(this._session);

  static Future<CornerModel> load({
    String assetPath = 'assets/models/corners.onnx',
  }) async {
    if (!_envInitialized) {
      OrtEnv.instance.init();
      _envInitialized = true;
    }
    final raw = await rootBundle.load(assetPath);
    final bytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    final session = OrtSession.fromBuffer(bytes, OrtSessionOptions());
    return CornerModel._(session);
  }

  /// Runs one camera frame through the model. Returns 4 normalized (x,y)
  /// corners, in TL, TR, BR, BL order -- ml/synth.py's canonicalize_corners
  /// produces exactly the order FrameController uses by default, so no
  /// reordering is needed here.
  Future<List<Offset>> predict(
    CameraImage image,
    int sensorOrientationDeg,
  ) async {
    final tensorData = yuv420ToChwTensor(image, sensorOrientationDeg);
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      tensorData,
      [1, 3, kModelInputSize, kModelInputSize],
    );
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = await _session.runAsync(runOptions, {'image': inputTensor});
      final flat = _flatten(outputs![0]!.value)
          .map((e) => (e as num).toDouble())
          .toList();
      assert(flat.length == 8, 'expected 8 floats, got ${flat.length}');
      return [
        Offset(flat[0], flat[1]), // TL
        Offset(flat[2], flat[3]), // TR
        Offset(flat[4], flat[5]), // BR
        Offset(flat[6], flat[7]), // BL
      ];
    } finally {
      inputTensor.release();
      runOptions.release();
      outputs?.forEach((o) => o?.release());
    }
  }

  List<dynamic> _flatten(dynamic v) {
    if (v is! List) return [v];
    if (v.isNotEmpty && v.first is List) return _flatten(v.first);
    return v;
  }

  void dispose() => _session.release();
}
