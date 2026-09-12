import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:ffi/ffi.dart' show malloc;
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:miscan/detection/frame_math.dart';

void main() {
  group('mapWidgetToNormalized', () {
    // An upright 3:4 preview in a taller widget: contain leaves bars of
    // (800 - 400 * 4 / 3) / 2 = 133.3 px above and below.
    const source = Size(1080, 1440);
    const widget = Size(400, 800);

    test('inverts mapCornersToWidget', () {
      const points = [Offset(0.2, 0.3), Offset(0.95, 0.05), Offset(0, 1)];
      final onScreen = mapCornersToWidget(
        normalizedCorners: points,
        sourceSize: source,
        destinationSize: widget,
      );
      for (var i = 0; i < points.length; i++) {
        final back = mapWidgetToNormalized(
          point: onScreen[i],
          sourceSize: source,
          destinationSize: widget,
        )!;
        expect(back.dx, closeTo(points[i].dx, 1e-9));
        expect(back.dy, closeTo(points[i].dy, 1e-9));
      }
    });

    test('the centre of the widget is the centre of the frame', () {
      final p = mapWidgetToNormalized(
        point: const Offset(200, 400),
        sourceSize: source,
        destinationSize: widget,
      )!;
      expect(p.dx, closeTo(0.5, 1e-9));
      expect(p.dy, closeTo(0.5, 1e-9));
    });

    test('points on the letterbox bars map to null', () {
      for (final y in [0.0, 50.0, 133.0, 667.0, 799.0]) {
        expect(
          mapWidgetToNormalized(
            point: Offset(200, y),
            sourceSize: source,
            destinationSize: widget,
          ),
          isNull,
          reason: 'y = $y',
        );
      }
    });
  });

  group('rgbaToChw', () {
    const plane = kModelInputWidth * kModelInputHeight;

    test('normalises each channel into its own plane', () {
      final rgba = Uint8List(plane * 4);
      rgba.setAll(0, [255, 0, 128, 7]); // first pixel; alpha is ignored
      rgba.setAll((plane - 1) * 4, [0, 255, 255, 0]); // last pixel
      final out = malloc<ffi.Float>(kModelInputLength);
      try {
        rgbaToChw(rgba, out);
        final f = out.asTypedList(kModelInputLength);
        double norm(int v, int c) => (v / 255 - kImagenetMean[c]) / kImagenetStd[c];
        expect(f[0], closeTo(norm(255, 0), 1e-6));
        expect(f[plane], closeTo(norm(0, 1), 1e-6));
        expect(f[2 * plane], closeTo(norm(128, 2), 1e-6));
        expect(f[plane - 1], closeTo(norm(0, 0), 1e-6));
        expect(f[2 * plane - 1], closeTo(norm(255, 1), 1e-6));
        expect(f[3 * plane - 1], closeTo(norm(255, 2), 1e-6));
      } finally {
        malloc.free(out);
      }
    });

    test('rejects a buffer of the wrong size', () {
      final out = malloc<ffi.Float>(kModelInputLength);
      try {
        expect(() => rgbaToChw(Uint8List(100), out), throwsArgumentError);
      } finally {
        malloc.free(out);
      }
    });
  });

  group('sensorToUpright', () {
    // A page as the model reports it in the sensor's own frame: TL, TR, BR, BL.
    const sensorQuad = [
      Offset(0.1, 0.2),
      Offset(0.6, 0.2),
      Offset(0.6, 0.7),
      Offset(0.1, 0.7),
    ];

    void expectQuad(List<Offset> actual, List<Offset> expected) {
      expect(actual.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        expect(actual[i].dx, closeTo(expected[i].dx, 1e-9), reason: 'corner $i x');
        expect(actual[i].dy, closeTo(expected[i].dy, 1e-9), reason: 'corner $i y');
      }
    }

    test('0 degrees leaves the corners alone', () {
      expectQuad(sensorToUpright(sensorQuad, 0), sensorQuad);
    });

    test('90 degrees: the sensor frame turned clockwise, TL restarted', () {
      // The sensor's top-left lands top-right once upright, so what the model
      // called corner 3 (BL) is the upright top-left.
      expectQuad(sensorToUpright(sensorQuad, 90), const [
        Offset(0.3, 0.1),
        Offset(0.8, 0.1),
        Offset(0.8, 0.6),
        Offset(0.3, 0.6),
      ]);
    });

    test('180 degrees', () {
      expectQuad(sensorToUpright(sensorQuad, 180), const [
        Offset(0.4, 0.3),
        Offset(0.9, 0.3),
        Offset(0.9, 0.8),
        Offset(0.4, 0.8),
      ]);
    });

    test('270 degrees', () {
      expectQuad(sensorToUpright(sensorQuad, 270), const [
        Offset(0.2, 0.4),
        Offset(0.7, 0.4),
        Offset(0.7, 0.9),
        Offset(0.2, 0.9),
      ]);
    });

    test('sensor corner (0, 0) is upright top-right at 90 degrees', () {
      // The Android convention the native sampler follows: sensor orientation
      // is the clockwise turn that makes the frame upright.
      final p = sensorToUpright(const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, 1),
        Offset(0, 1),
      ], 90);
      expect(p, contains(const Offset(1, 0)));
      expect(p.first, const Offset(0, 0)); // restarted at upright top-left
    });
  });

  group('exifOrientationFor', () {
    test('this app\'s known baseline: sensor 90, portraitUp -> EXIF 6', () {
      // Measured and documented in CLAUDE.md: a portrait capture on this
      // phone class (sensorOrientation 90) stores 4080x3060 with EXIF 6.
      expect(exifOrientationFor(90, DeviceOrientation.portraitUp), 6);
    });

    test('sensor 90: the other three device orientations', () {
      expect(exifOrientationFor(90, DeviceOrientation.landscapeLeft), 1);
      expect(exifOrientationFor(90, DeviceOrientation.portraitDown), 8);
      expect(exifOrientationFor(90, DeviceOrientation.landscapeRight), 3);
    });

    test('only ever returns a value EditPage\'s own convention understands', () {
      // EditPage._orientToTurns only recognises 1, 3, 6 and 8.
      for (final sensorDeg in [0, 90, 180, 270]) {
        for (final orientation in DeviceOrientation.values) {
          expect(
            [1, 3, 6, 8],
            contains(exifOrientationFor(sensorDeg, orientation)),
            reason: 'sensor $sensorDeg, $orientation',
          );
        }
      }
    });

    test('a full device rotation cycles through all four values once', () {
      const cycle = [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeRight,
      ];
      final seen = cycle.map((o) => exifOrientationFor(90, o)).toSet();
      expect(seen, {6, 1, 8, 3});
    });
  });
}
