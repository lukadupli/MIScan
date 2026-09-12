import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

import '../detection/document_model.dart';
import '../detection/frame_math.dart';
import '../detection/ort_tensor_io.dart';

/// Debug-only: times the shipped segmentation model on this device under
/// different ONNX Runtime execution providers, and checks they agree.
///
/// Inference is most of a live-preview frame, so how ORT executes the graph is
/// the main lever left. Configs run round-robin in a rotating order within
/// one session, because inference time drifts ~20% between sessions with the
/// phone's thermal and battery state -- comparisons across separate runs are
/// not trustworthy, comparisons within one are.
class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key});

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _Config {
  final String label;
  final OrtSessionOptions Function() build;
  const _Config(this.label, this.build);
}

// The first config is the reference the others are compared against.
final _configs = [
  _Config('cpu (default)', OrtSessionOptions.new),
  _Config('xnnpack x4', () => DocumentModel.xnnpackOptions(4)),
  _Config('xnnpack x8', () => DocumentModel.xnnpackOptions(8)),
];

const _warmupRounds = 3;
const _timedRounds = 15;

class _Result {
  double? meanMs;
  double? maxAbsDiff; // logits vs the cpu config
  double? maskFlipPct; // % of pixels landing on the other side of the threshold
  String? error;
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  final _results = {for (final c in _configs) c.label: _Result()};
  String _status = 'loading model...';
  String _providers = '';
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final sessions = <String, OrtSession>{};
    OrtValueTensor? input;
    try {
      OrtEnv.instance.init();
      _providers = OrtEnv.instance.availableProviders().map((p) => p.value).join(', ');
      final raw = await rootBundle.load('assets/models/segmentation.onnx');
      final bytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);

      for (final c in _configs) {
        try {
          final options = c.build();
          sessions[c.label] = OrtSession.fromBuffer(bytes, options);
          options.release();
        } catch (e) {
          _results[c.label]!.error = '$e';
        }
      }

      // One fixed input for every config and every run. Values spread over
      // roughly the range ImageNet-normalised pixels occupy.
      const plane = kModelInputHeight * kModelInputWidth;
      final rng = math.Random(42);
      final data = Float32List(3 * plane);
      for (var i = 0; i < data.length; i++) {
        data[i] = rng.nextDouble() * 4 - 2;
      }
      input = OrtValueTensor.createTensorWithDataList(
        data,
        [1, 3, kModelInputHeight, kModelInputWidth],
      );

      // Agreement: every config against cpu, on the same input.
      final outputs = <String, Float32List>{};
      for (final entry in sessions.entries) {
        outputs[entry.key] = await _infer(entry.value, input, plane);
      }
      final reference = outputs[_configs.first.label];
      if (reference != null) {
        for (final entry in outputs.entries) {
          var maxDiff = 0.0;
          var flips = 0;
          for (var i = 0; i < plane; i++) {
            final a = reference[i], b = entry.value[i];
            maxDiff = math.max(maxDiff, (a - b).abs());
            if ((a >= 0) != (b >= 0)) flips++;
          }
          _results[entry.key]!
            ..maxAbsDiff = maxDiff
            ..maskFlipPct = 100.0 * flips / plane;
        }
      }

      // Timing, round-robin with the order rotated each round.
      final labels = sessions.keys.toList();
      final totals = {for (final l in labels) l: 0};
      for (var round = 0; round < _warmupRounds + _timedRounds; round++) {
        if (mounted) {
          setState(() => _status = round < _warmupRounds
              ? 'warming up...'
              : 'timing round ${round - _warmupRounds + 1}/$_timedRounds');
        }
        for (var k = 0; k < labels.length; k++) {
          final label = labels[(round + k) % labels.length];
          final sw = Stopwatch()..start();
          await _infer(sessions[label]!, input, null);
          if (round >= _warmupRounds) totals[label] = totals[label]! + sw.elapsedMicroseconds;
        }
      }
      for (final l in labels) {
        _results[l]!.meanMs = totals[l]! / _timedRounds / 1000.0;
      }

      debugPrint('EP_BENCHMARK providers=[$_providers] ${[
        for (final c in _configs)
          '${c.label}: ${_results[c.label]!.meanMs?.toStringAsFixed(1) ?? "-"}ms '
              'diff=${_results[c.label]!.maxAbsDiff?.toStringAsExponential(2) ?? "-"} '
              'flip=${_results[c.label]!.maskFlipPct?.toStringAsFixed(3) ?? "-"}% '
              '${_results[c.label]!.error ?? ""}'
      ].join(' | ')}');
      if (mounted) setState(() { _status = 'done'; _done = true; });
    } catch (e) {
      if (mounted) setState(() { _status = 'failed: $e'; _done = true; });
    } finally {
      input?.release();
      for (final s in sessions.values) {
        s.release();
      }
    }
  }

  /// One inference. Returns the mask when [count] is given, otherwise just
  /// runs and releases.
  Future<Float32List> _infer(OrtSession session, OrtValueTensor input, int? count) async {
    final ro = OrtRunOptions();
    List<OrtValue?>? outs;
    try {
      outs = await session.runAsync(ro, {'image': input});
      return count == null ? Float32List(0) : readFloat32Output(outs![0]!, count);
    } finally {
      ro.release();
      outs?.forEach((o) => o?.release());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cpuMs = _results[_configs.first.label]!.meanMs;
    return Scaffold(
      appBar: AppBar(title: const Text('Execution providers (debug)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_status),
          const SizedBox(height: 4),
          Text('available: $_providers',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const Divider(height: 24),
          for (final c in _configs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _row(c.label, _results[c.label]!, cpuMs),
            ),
          if (!_done)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, _Result r, double? cpuMs) {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13);
    if (r.error != null) {
      return Text('$label\n  failed: ${r.error}', style: mono.copyWith(color: Colors.redAccent));
    }
    final speed = (r.meanMs != null && cpuMs != null) ? ' (${(cpuMs / r.meanMs!).toStringAsFixed(2)}x)' : '';
    return Text(
      '$label\n'
      '  ${r.meanMs?.toStringAsFixed(1) ?? '...'} ms$speed\n'
      '  vs cpu: max|diff| ${r.maxAbsDiff?.toStringAsExponential(2) ?? '...'}, '
      'mask pixels flipped ${r.maskFlipPct?.toStringAsFixed(3) ?? '...'}%',
      style: mono,
    );
  }
}
