import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

import 'frame_math.dart';

/// Debug-only: times the shipped segmentation model on this actual device.
///
/// The resolution sweep this page originally ran is done -- 4:3 sizes cost
/// almost exactly in proportion to pixel count on real hardware (190ms at
/// 256x192 up to 1156ms at 640x480), which settled the input size at 320x240.
/// Those figures came from a dynamic-axis export, which ORT optimises less
/// aggressively, so they were an upper bound.
///
/// What it measures now is the real thing: the static model the app loads, at
/// the size it actually runs, so the number is the one the live preview is
/// living with rather than a proxy for it.
class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key});

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

/// The one size the shipped graph accepts, from ml/common.py's INPUT_SIZE.
const _sizes = <List<int>>[
  [kModelInputHeight, kModelInputWidth],
];

const _warmupRuns = 3; // first runs pay one-off allocation and page-in costs
const _timedRuns = 20;

class _BenchmarkPageState extends State<BenchmarkPage> {
  final _results = <String, double>{};
  final _stopwatch = Stopwatch();
  String _status = 'loading model...';
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    OrtSession? session;
    try {
      OrtEnv.instance.init();
      final raw = await rootBundle.load('assets/models/segmentation.onnx');
      session = OrtSession.fromBuffer(
        raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
        OrtSessionOptions(),
      );

      for (final size in _sizes) {
        final h = size[0], w = size[1];
        final label = '$w x $h';
        if (mounted) setState(() => _status = 'timing $label...');

        final data = Float32List(1 * 3 * h * w); // zeros: timing only
        final shape = [1, 3, h, w];

        for (int i = 0; i < _warmupRuns + _timedRuns; i++) {
          if (i == _warmupRuns) _stopwatch.reset();
          _stopwatch.start();
          final input = OrtValueTensor.createTensorWithDataList(data, shape);
          final runOptions = OrtRunOptions();
          List<OrtValue?>? outputs;
          try {
            outputs = await session.runAsync(runOptions, {'image': input});
          } finally {
            input.release();
            runOptions.release();
            outputs?.forEach((o) => o?.release());
          }
          _stopwatch.stop();
        }

        if (!mounted) return;
        setState(() {
          _results[label] = _stopwatch.elapsedMicroseconds / 1000.0 / _timedRuns;
        });
      }

      if (mounted) setState(() { _status = 'done'; _done = true; });
    } catch (e) {
      if (mounted) setState(() { _status = 'failed: $e'; _done = true; });
    } finally {
      session?.release();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The size the current corner model runs at, for reference.
    const baseline = 150.0;
    return Scaffold(
      appBar: AppBar(title: const Text('Model latency (debug)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_status, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          const Text(
            'LR-ASPP MobileNetV3, the shipped static model.\n'
            'This is the real per-frame inference cost, preprocessing excluded.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const Divider(height: 24),
          for (final entry in _results.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(entry.key, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                  Text(
                    '${entry.value.toStringAsFixed(0)} ms',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: entry.value > baseline * 3 ? Colors.redAccent : null,
                    ),
                  ),
                ],
              ),
            ),
          if (!_done) const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}
