import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miscan/book_frame.dart';

void main() {
  group('splineHandleDelta', () {
    const boundaryHeight = 500.0;
    const nominalDelta = 150.0;

    test('the full nominal delta when there is room', () {
      expect(splineHandleDelta(100, boundaryHeight, nominalDelta), nominalDelta);
    });

    test('exactly enough room: still the full nominal delta (boundary case)', () {
      expect(splineHandleDelta(350, boundaryHeight, nominalDelta), nominalDelta);
    });

    test('shrinks to whatever room is left, never flips negative', () {
      // A detected top edge sitting near the bottom of the frame, e.g. a
      // landscape photo: 400 + 150 = 550 would overshoot a 500-tall frame,
      // so the handle sits only 100px below instead of the full 150.
      expect(splineHandleDelta(400, boundaryHeight, nominalDelta), 100);
    });

    test('shrinks to zero rather than go negative when there is no room at all', () {
      expect(splineHandleDelta(boundaryHeight, boundaryHeight, nominalDelta), 0);
      expect(splineHandleDelta(boundaryHeight + 50, boundaryHeight, nominalDelta), 0);
    });

    test('the smaller (odd-index) delta shrinks later than the larger one', () {
      const smallDelta = 75.0; // splineSelectorUpDownMul * splineSelectorDelta, by default
      // At curveY = 400 the large delta (150) has already been shrunk to
      // 100 (500 - 400), but the small one (75) still fits in full -- this
      // is what keeps the zig-zag pattern from collapsing as the curve
      // nears the bottom.
      expect(splineHandleDelta(400, boundaryHeight, nominalDelta), 100);
      expect(splineHandleDelta(400, boundaryHeight, smallDelta), smallDelta);
    });

    test('never lands the handle outside the frame', () {
      for (var curveY = 0.0; curveY <= boundaryHeight; curveY += 10) {
        final delta = splineHandleDelta(curveY, boundaryHeight, nominalDelta);
        expect(delta, greaterThanOrEqualTo(0), reason: 'curveY=$curveY');
        expect(curveY + delta, lessThanOrEqualTo(boundaryHeight), reason: 'curveY=$curveY');
      }
    });
  });

  group('BookFrame, a handle with no room for the full nominal delta', () {
    // A single curve point at y = 400 in a 500-tall boundary: splineHandleDelta
    // shrinks its offset to 100 (400 + 150 would overshoot), same as a
    // detected top edge sitting low in the frame, or the curve dragged
    // down toward the bottom.
    Future<BookFrameController> pumpShrunkHandle(WidgetTester tester) async {
      final controller = BookFrameController(
        splinePoints: 1,
        corners: const [Offset(0, 400), Offset(300, 400), Offset(300, 410), Offset(0, 410)],
        boundary: const Rect.fromLTWH(0, 0, 300, 500),
      );
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          // A bottom margin so the shrunk handle -- its centre lands right
          // at boundary.bottom by construction -- isn't also right at the
          // widget's own edge, which is unrelated to what's under test here
          // and can make a simulated drag miss the hit-test region.
          child: BookFrame(
            controller: controller,
            margin: const EdgeInsets.only(bottom: 40),
            child: const SizedBox(width: 300, height: 500),
          ),
        ),
      ));
      await tester.pump(); // layout is applied in a post-frame callback
      return controller;
    }

    Finder findHandle() => find.byWidgetPredicate(
        (w) => w is Container && (w.decoration as BoxDecoration?)?.shape == BoxShape.circle);

    testWidgets('is drawn where BookFramePainter actually puts it', (tester) async {
      await pumpShrunkHandle(tester);

      // BookFramePainter draws this handle's centre at curveY + delta =
      // 400 + 100 = 500.
      final center = tester.getCenter(findHandle());
      expect(center.dx, closeTo(150, 0.5));
      expect(center.dy, closeTo(500, 0.5));
    });

    testWidgets('can actually be dragged, tracking the finger 1:1', (tester) async {
      final controller = await pumpShrunkHandle(tester);
      final center = tester.getCenter(findHandle());

      // Drag up, toward where the full nominal delta would fit again.
      await tester.dragFrom(center, const Offset(0, -50));
      await tester.pump();

      expect(controller.curvePointsUp[0].dy, closeTo(350, 0.5));
    });
  });
}
