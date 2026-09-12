import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miscan/frame.dart';

void main() {
  group('FrameController.startingCorners', () {
    const size = Size(200, 100);
    const imageCorners = [Offset(0, 0), Offset(200, 0), Offset(200, 100), Offset(0, 100)];

    test('no initial corners: the child\'s own corners', () {
      expect(FrameController().startingCorners(size), imageCorners);
    });

    test('initial corners are scaled to the child', () {
      final c = FrameController(initialCorners: const [
        Offset(0.1, 0.2), Offset(0.9, 0.2), Offset(0.9, 0.8), Offset(0.1, 0.8),
      ]);
      expect(c.startingCorners(size), const [
        Offset(20, 20), Offset(180, 20), Offset(180, 80), Offset(20, 80),
      ]);
    });

    test('points slightly outside are clamped onto the child', () {
      final c = FrameController(initialCorners: const [
        Offset(-0.01, 0.2), Offset(1.02, 0.2), Offset(0.9, 1.5), Offset(0.1, 0.8),
      ]);
      expect(c.startingCorners(size), const [
        Offset(0, 20), Offset(200, 20), Offset(180, 100), Offset(20, 80),
      ]);
    });

    test('unusable initial corners fall back to the child\'s corners', () {
      final three = FrameController(initialCorners: const [Offset(0.1, 0.1), Offset(0.9, 0.1), Offset(0.5, 0.9)]);
      final nan = FrameController(initialCorners: const [
        Offset(double.nan, 0.2), Offset(0.9, 0.2), Offset(0.9, 0.8), Offset(0.1, 0.8),
      ]);
      expect(three.startingCorners(size), imageCorners);
      expect(nan.startingCorners(size), imageCorners);
    });

    test('from() keeps the initial corners', () {
      final original = FrameController(initialCorners: const [
        Offset(0.1, 0.2), Offset(0.9, 0.2), Offset(0.9, 0.8), Offset(0.1, 0.8),
      ]);
      expect(FrameController.from(original).initialCorners, original.initialCorners);
    });
  });

  group('Frame', () {
    Widget frame(FrameController controller, Size child, {Key? key}) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Frame(key: key, controller: controller, child: SizedBox.fromSize(size: child)),
          ),
        );

    testWidgets('first layout places the corners from initialCorners', (tester) async {
      final controller = FrameController(initialCorners: const [
        Offset(0.25, 0.5), Offset(0.75, 0.5), Offset(0.75, 1), Offset(0.25, 1),
      ]);
      await tester.pumpWidget(frame(controller, const Size(200, 100)));
      await tester.pump(); // corners are placed in a post-frame callback

      expect(controller.initialized, isTrue);
      expect(controller.corners, const [
        Offset(50, 50), Offset(150, 50), Offset(150, 100), Offset(50, 100),
      ]);
    });

    testWidgets('a laid-out controller copied into a new Frame rescales, not NaN', (tester) async {
      final original = FrameController();
      await tester.pumpWidget(frame(original, const Size(200, 100)));
      await tester.pump();
      original.corners[0] = const Offset(20, 10);

      // A fresh Frame at double the size, as when another page takes a copy.
      // The new key forces a new State, whose own boundary starts empty --
      // the case that used to scale from zero.
      final copy = FrameController.from(original);
      await tester.pumpWidget(frame(copy, const Size(400, 200), key: const ValueKey('copy')));
      await tester.pump();

      expect(copy.corners[0], const Offset(40, 20));
      expect(copy.corners[2], const Offset(400, 200));
      expect(copy.corners.every((p) => p.dx.isFinite && p.dy.isFinite), isTrue);
    });
  });
}
