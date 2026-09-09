import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miscan/debug/mask_to_quad.dart';

/// Pins lib/debug/mask_to_quad.dart to ml/postprocess.py.
///
/// The same mask->quad geometry exists in both, because eval.py has to score
/// models in Python and the phone has to act on them in Dart with no OpenCV
/// available. Two copies drift. When they do, the SmartDoc number stops
/// predicting what the app actually does, which is the only reason that number
/// is worth measuring.
///
/// Regenerate the fixture after touching either side:
///   python ml/make_postprocess_fixture.py
void main() {
  final file = File('test/mask_to_quad_fixture.json');
  final fixture = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
  final height = fixture['height'] as int;
  final width = fixture['width'] as int;
  final cases = fixture['cases'] as List<dynamic>;

  /// Runs alternate, starting with a run of zeros. Rebuilds the mask as
  /// logits, since that is what the model emits and what maskToQuad expects:
  /// well clear of the 0.5 decision boundary on both sides.
  Float32List decode(List<dynamic> runs) {
    final out = Float32List(height * width)..fillRange(0, height * width, -10.0);
    var index = 0;
    var value = 0;
    for (final run in runs) {
      final length = run as int;
      if (value == 1) {
        for (int i = 0; i < length; i++) {
          out[index + i] = 10.0;
        }
      }
      index += length;
      value = 1 - value;
    }
    expect(index, height * width, reason: 'run lengths do not fill the mask');
    return out;
  }

  for (final entry in cases) {
    final data = entry as Map<String, dynamic>;
    final name = data['name'] as String;

    test('matches postprocess.py on "$name"', () {
      final logits = decode(data['runs'] as List<dynamic>);
      final actual = maskToQuad(logits, width, height);
      final expected = data['expected'] as List<dynamic>?;

      if (expected == null) {
        expect(actual, isNull, reason: 'Python found no document here');
        return;
      }

      expect(actual, isNotNull, reason: 'Python found a quad, Dart did not');
      expect(actual!.length, 4);

      for (int i = 0; i < 4; i++) {
        final want = expected[i] as List<dynamic>;
        final wantX = (want[0] as num).toDouble();
        final wantY = (want[1] as num).toDouble();
        final distance = math.sqrt(
          math.pow(actual[i].dx - wantX, 2) + math.pow(actual[i].dy - wantY, 2),
        );
        // A pixel of slack absorbs tie-breaking differences in the
        // simplification step; anything larger means the two implementations
        // genuinely disagree about where the corner is.
        expect(
          distance,
          lessThan(1.5),
          reason: 'corner $i: Dart got ${actual[i]}, Python got ($wantX, $wantY)',
        );
      }
    });
  }
}
