#include "test_util.h"
#include "synthetic_scene.h"

#include "../transform/quad_transform.h"

#include <algorithm>
#include <random>
#include <vector>

namespace {

	// neww / newh are rounded to whole pixels, so anything derived from them carries
	// up to a pixel of quantisation error
	const double PIXEL_TOLERANCE = 2.0;
	const double ASPECT_TOLERANCE = 0.02;

	// must stay in step with quad_transform.cpp
	const double MAX_OUTPUT_SIDE = 20000.;
	const double MAX_OUTPUT_PIXELS = 25e6;

	// A view that is near-parallel about one axis carries no information about how far
	// away the camera was, so loadCoordinates has to assume a height. The result stays
	// stable and usable but its aspect ratio is only approximate.
	const double DEGENERATE_ASPECT_TOLERANCE = 0.15;

	bool load(QuadTransform& q, const SyntheticScene& s) {
		return q.loadCoordinates(
			{ s.principalPoint.x, s.principalPoint.y },
			{ s.A.x, s.A.y }, { s.B.x, s.B.y }, { s.C.x, s.C.y }, { s.D.x, s.D.y });
	}

	// Same mapping process() uses to pull a destination pixel from the source picture.
	Vector3 sourceCoordinatesFor(const QuadTransform& q, int x, int y) {
		return QuadTransform::correspondingSrcCoors(x, y,
			q.floorPlaneOrigin(), q.floorPlaneUnitX(), q.floorPlaneUnitY(), q.cameraHeight())
			+ q.principalPoint();
	}

} // namespace

// The camera height is what everything else is derived from. Bug history: taking a
// diagonal instead of an edge for the second vanishing point made hsq meaningless,
// which either returned false outright or produced a wildly wrong h.
//
// These poses are all tilted enough about both axes for the height to actually be
// recoverable. A view that is near-parallel about one axis cannot pin it down at all;
// single_parallel_edge_pair_degrades_gracefully covers that regime instead.
TEST(recovers_camera_height) {
	struct { double tiltX, tiltY, distance; } poses[] = {
		{  0.30, -0.20, -300. },
		{ -0.45,  0.10, -500. },
		{  0.15,  0.12, -900. },
		{  0.55,  0.55, -400. },
		{ -0.20, -0.50, -700. },
	};

	for (const auto& pose : poses) {
		SyntheticScene s = makeScene(800., pose.tiltX, pose.tiltY,
			Vector3{ 40., -30., pose.distance }, 300., 200.);

		QuadTransform q;
		CHECK_MSG(load(q, s), "loadCoordinates rejected a valid perspective view");
		CHECK_NEAR_REL(q.cameraHeight(), s.height, 1e-6);
	}
}

// The floor plane has to come out parallel to the real document plane. Bug history:
// the vanishing point directions used +h*Sh.z instead of -h*Sh.z, which mirrors the
// normal to (-n.x, -n.y, n.z) — a different plane, not a parallel one, so h came out
// exactly right while the rectified image stayed warped.
TEST(recovers_document_plane_normal) {
	struct { double tiltX, tiltY; } tilts[] = {
		{  0.30, -0.20 }, { -0.45, 0.10 }, { 0.05, 0.05 }, { 0.55, 0.55 }, { -0.20, -0.50 },
	};

	for (const auto& tilt : tilts) {
		SyntheticScene s = makeScene(800., tilt.tiltX, tilt.tiltY,
			Vector3{ 40., -30., -300. }, 300., 200.);

		QuadTransform q;
		CHECK_MSG(load(q, s), "loadCoordinates rejected a valid perspective view");

		Vector3 got = orientUpward(q.floorPlane().v);
		CHECK_NEAR((got - s.normal).Abs(), 0., 1e-9);
	}
}

// The plane the result is projected onto is chosen for convenience, so absolute output
// size is arbitrary — but the shape is not. A correct rectification reproduces the
// document's aspect ratio whatever the viewing angle was.
TEST(recovers_aspect_ratio) {
	struct { double halfWidth, halfHeight; } shapes[] = {
		{ 300., 200. },		// 3:2
		{ 210., 297. },		// portrait A4
		{ 250., 250. },		// square
		{ 400., 100. },		// wide
	};

	for (const auto& shape : shapes) {
		SyntheticScene s = makeScene(800., 0.35, -0.25,
			Vector3{ 40., -30., -300. }, shape.halfWidth, shape.halfHeight);

		QuadTransform q;
		CHECK_MSG(load(q, s), "loadCoordinates rejected a valid perspective view");
		CHECK(q.newHeight() > 0);
		if (q.newHeight() <= 0) continue;

		double aspect = (double)q.newWidth() / (double)q.newHeight();
		CHECK_NEAR_REL(aspect, s.trueAspect(), ASPECT_TOLERANCE);
	}
}

// How far the rectification plane sits from the camera decides how many pixels the page
// gets. Leaving it at the principal point tied that to the camera height and tilt, which
// says nothing about how finely the photo resolved the page, so detail was dropped for
// free — and for a square-on shot the height is only assumed, which made the output
// resolution follow a guessed constant. It has to track the source instead.
TEST(output_keeps_source_edge_resolution) {
	struct { double tiltX, tiltY, distance; } poses[] = {
		{  0.30, -0.20, -300. },
		{ -0.45,  0.10, -500. },
		{  0.15,  0.12, -900. },
		{  0.55,  0.55, -400. },
		{  0.00,  0.40, -300. },	// square-on about one axis: height is assumed
	};

	for (const auto& pose : poses) {
		SyntheticScene s = makeScene(800., pose.tiltX, pose.tiltY,
			Vector3{ 40., -30., pose.distance }, 300., 200., Vector3{ 500., 400., 0. });

		QuadTransform q;
		std::string where = "tilt (" + std::to_string(pose.tiltX) + ", " + std::to_string(pose.tiltY) + ")";
		CHECK_MSG(load(q, s), where + ": loadCoordinates rejected a valid perspective view");

		double srcWidth = std::max((s.B - s.A).Abs(), (s.C - s.D).Abs());
		double srcHeight = std::max((s.D - s.A).Abs(), (s.C - s.B).Abs());

		// no axis may be sampled more coarsely than the camera resolved it
		CHECK_MSG(q.newWidth() >= srcWidth - PIXEL_TOLERANCE, where + ": output width "
			+ std::to_string(q.newWidth()) + " is below the longest source edge "
			+ std::to_string(srcWidth));
		CHECK_MSG(q.newHeight() >= srcHeight - PIXEL_TOLERANCE, where + ": output height "
			+ std::to_string(q.newHeight()) + " is below the longest source edge "
			+ std::to_string(srcHeight));

		// and the binding axis must land on its source length rather than overshoot, so
		// the scale is the smallest one that preserves the detail
		bool widthBinds = std::fabs(q.newWidth() - srcWidth) <= PIXEL_TOLERANCE;
		bool heightBinds = std::fabs(q.newHeight() - srcHeight) <= PIXEL_TOLERANCE;
		CHECK_MSG(widthBinds || heightBinds, where + ": neither axis binds - output "
			+ std::to_string(q.newWidth()) + "x" + std::to_string(q.newHeight())
			+ " against source edges " + std::to_string(srcWidth) + " and " + std::to_string(srcHeight));
	}
}

// Scaling the plane is a uniform scaling about the camera, so it must not disturb the
// shape that the rest of the transform works to recover. Guards against the two axes ever
// being scaled independently, which would rectify to the wrong rectangle.
TEST(aspect_ratio_survives_rescaling) {
	struct { double halfWidth, halfHeight; } shapes[] = {
		{ 300., 200. }, { 210., 297. }, { 250., 250. }, { 400., 100. },
	};

	for (const auto& shape : shapes) {
		SyntheticScene s = makeScene(800., 0.35, -0.25,
			Vector3{ 40., -30., -300. }, shape.halfWidth, shape.halfHeight, Vector3{ 500., 400., 0. });

		QuadTransform q;
		CHECK_MSG(load(q, s), "loadCoordinates rejected a valid perspective view");
		if (q.newHeight() <= 0) { CHECK(false); continue; }

		double aspect = (double)q.newWidth() / (double)q.newHeight();
		CHECK_NEAR_REL(aspect, s.trueAspect(), ASPECT_TOLERANCE);
	}
}

// Preserving resolution makes the output bigger, and a steeply angled page can ask for
// more than the device can allocate. The cap has to clamp the scale, not refuse the scan.
TEST(resolution_scale_is_capped) {
	// a long page seen at a sharp angle: the near edge is resolved far better than the far
	// one, so matching it demands a large output
	struct { const char* name; double tiltX, tiltY, distance; double halfWidth, halfHeight; } cases[] = {
		{ "steeply angled page",   0.95,  0.10, -260., 900., 120. },
		{ "sharp angle, long page", 0.10, 0.95, -260., 120., 900. },
		{ "grazing view",          1.20,  1.20, -220., 800., 800. },
	};

	for (const auto& c : cases) {
		SyntheticScene s = makeScene(800., c.tiltX, c.tiltY,
			Vector3{ 0., 0., c.distance }, c.halfWidth, c.halfHeight, Vector3{ 500., 400., 0. });

		QuadTransform q;
		std::string where = c.name;
		CHECK_MSG(load(q, s), where + ": loadCoordinates refused a scan instead of clamping the scale");
		if (!load(q, s)) continue;

		CHECK_MSG(q.newWidth() > 0 && q.newHeight() > 0, where + ": empty output");
		CHECK_MSG(q.newWidth() <= MAX_OUTPUT_SIDE && q.newHeight() <= MAX_OUTPUT_SIDE,
			where + ": output side out of range at " + std::to_string(q.newWidth())
			+ "x" + std::to_string(q.newHeight()));
		CHECK_MSG((double)q.newWidth() * q.newHeight() <= MAX_OUTPUT_PIXELS,
			where + ": output is " + std::to_string((double)q.newWidth() * q.newHeight() / 1e6)
			+ " MP, over the cap");
	}
}

// End to end on the mapping process() applies: every corner of the output rectangle has
// to pull from the matching corner the user picked. C is the sharpest of the four — it
// never enters the basis construction, so it only lands correctly if the recovered
// geometry is right rather than merely self-consistent.
TEST(output_corners_map_back_to_input_corners) {
	SyntheticScene s = makeScene(800., 0.30, -0.20,
		Vector3{ 40., -30., -300. }, 300., 200., Vector3{ 500., 400., 0. });

	QuadTransform q;
	CHECK_MSG(load(q, s), "loadCoordinates rejected a valid perspective view");

	int w = q.newWidth(), h = q.newHeight();
	struct { const char* name; int x, y; const Vector3* expected; } corners[] = {
		{ "A -> (0, 0)", 0, 0, &s.A },
		{ "B -> (w, 0)", w, 0, &s.B },
		{ "C -> (w, h)", w, h, &s.C },
		{ "D -> (0, h)", 0, h, &s.D },
	};

	for (const auto& corner : corners) {
		Vector3 got = sourceCoordinatesFor(q, corner.x, corner.y);
		CHECK_MSG((got - *corner.expected).Abs() <= PIXEL_TOLERANCE, std::string(corner.name)
			+ " landed at (" + std::to_string(got.x) + ", " + std::to_string(got.y)
			+ "), expected (" + std::to_string(corner.expected->x) + ", " + std::to_string(corner.expected->y) + ")");
	}
}

// A quadrilateral that is already an axis-aligned rectangle has nothing to correct, so
// it must come back out at its own size.
TEST(frontal_rectangle_is_passed_through) {
	QuadTransform q;
	bool ok = q.loadCoordinates({ 500., 400. },
		{ 300., 600. }, { 700., 600. }, { 700., 200. }, { 300., 200. });

	CHECK_MSG(ok, "loadCoordinates rejected an axis-aligned rectangle");
	CHECK_NEAR(q.newWidth(), 400., PIXEL_TOLERANCE);
	CHECK_NEAR(q.newHeight(), 400., PIXEL_TOLERANCE);
}

// Both vanishing points sit at infinity here, which used to be tested for with an
// absolute epsilon against Sh.z * Th.z. That product scales like the sixth power of the
// picture coordinates, so at photo resolutions the test only ever fired on an exactly
// axis-aligned rectangle and put a cliff right next to the most common input there is.
// Nudging one corner by a fraction of a pixel must not change the answer.
//
// The nudge has to move B diagonally to tip both Sh.z and Th.z away from zero. Sliding it
// along either edge leaves that edge pair parallel, and the vanishing point stays exactly
// at infinity no matter how large the slide.
TEST(near_rectangle_is_continuous_with_exact_rectangle) {
	QuadTransform exact;
	CHECK_MSG(exact.loadCoordinates({ 500., 400. },
		{ 300., 600. }, { 700., 600. }, { 700., 200. }, { 300., 200. }),
		"loadCoordinates rejected an axis-aligned rectangle");

	for (double nudge : { 1e-9, 1e-6, 1e-3, 0.1, 1.0 }) {
		QuadTransform q;
		bool ok = q.loadCoordinates({ 500., 400. },
			{ 300., 600. }, { 700. + nudge, 600. + nudge }, { 700., 200. }, { 300., 200. });

		std::string where = "nudged by " + std::to_string(nudge) + " px";
		CHECK_MSG(ok, where + ": loadCoordinates rejected a near-rectangle");
		if (!ok) continue;

		CHECK_MSG(std::fabs(q.newWidth() - exact.newWidth()) <= PIXEL_TOLERANCE
			&& std::fabs(q.newHeight() - exact.newHeight()) <= PIXEL_TOLERANCE,
			where + ": output size jumped to " + std::to_string(q.newWidth()) + "x"
			+ std::to_string(q.newHeight()) + " from " + std::to_string(exact.newWidth())
			+ "x" + std::to_string(exact.newHeight()));
		CHECK_MSG(std::fabs(q.cameraHeight() - exact.cameraHeight()) <= 1.,
			where + ": camera height jumped to " + std::to_string(q.cameraHeight())
			+ " from " + std::to_string(exact.cameraHeight()));
	}
}

// With both edge pairs parallel in the picture the document plane is parallel to the
// picture plane, whatever the camera height turns out to be, so the selection is already
// rectified and only needs passing through at its own size.
TEST(parallelogram_is_left_fronto_parallel) {
	struct { const char* name; double ax, ay, bx, by, cx, cy, dx, dy, width, height; } cases[] = {
		{ "40px shear",        300., 600., 700., 600., 740., 200., 340., 200., 400., 402. },
		{ "rotated 45 deg",    500., 600., 641., 459., 500., 318., 359., 459., 199., 199. },
	};

	for (const auto& c : cases) {
		QuadTransform q;
		bool ok = q.loadCoordinates({ 500., 400. },
			{ c.ax, c.ay }, { c.bx, c.by }, { c.cx, c.cy }, { c.dx, c.dy });

		CHECK_MSG(ok, std::string(c.name) + ": loadCoordinates rejected a parallelogram");
		if (!ok) continue;

		Vector3 n = orientUpward(q.floorPlane().v);
		CHECK_MSG(std::fabs(n.z - 1.) < 1e-6, std::string(c.name)
			+ ": expected a fronto-parallel plane, got normal z = " + std::to_string(n.z));
		CHECK_NEAR(q.newWidth(), c.width, PIXEL_TOLERANCE);
		CHECK_NEAR(q.newHeight(), c.height, PIXEL_TOLERANCE);
	}
}

// Holding the phone tilted forward but square to the page leaves one edge pair parallel
// in the picture. Its vanishing point runs off to infinity and the orthogonality
// constraint stops mentioning the camera height, so the height has to be assumed. That
// used to make hsq a small number divided by a small number: on hand-placed corners it
// came out negative a third of the time and the scan was refused outright. It must now
// always produce a stable, roughly correct result instead.
TEST(single_parallel_edge_pair_degrades_gracefully) {
	for (double tiltX : { 0.05, 0.02, 0.005, 0.0 }) {
		SyntheticScene s = makeScene(800., tiltX, 0.4,
			Vector3{ 40., -30., -300. }, 300., 200., Vector3{ 500., 400., 0. });

		QuadTransform q;
		std::string where = "tiltX = " + std::to_string(tiltX);
		CHECK_MSG(load(q, s), where + ": loadCoordinates refused a document photographed square-on");
		if (!load(q, s)) continue;

		CHECK_MSG(q.newWidth() > 0 && q.newHeight() > 0
			&& q.newWidth() < MAX_OUTPUT_SIDE && q.newHeight() < MAX_OUTPUT_SIDE,
			where + ": output size " + std::to_string(q.newWidth()) + "x" + std::to_string(q.newHeight()));
		if (q.newHeight() <= 0) continue;

		double aspect = (double)q.newWidth() / q.newHeight();
		CHECK_MSG(std::fabs(aspect - s.trueAspect()) <= DEGENERATE_ASPECT_TOLERANCE * s.trueAspect(),
			where + ": aspect " + std::to_string(aspect) + " is too far from " + std::to_string(s.trueAspect()));
	}
}

// Corners are dragged with a fingertip, so they never satisfy the projected-rectangle
// constraint exactly. Combined with a near-parallel edge pair that used to reject one
// scan in three; nothing here may be refused or come back an absurd size.
TEST(hand_placed_corners_are_not_rejected) {
	std::mt19937 rng(31337);
	std::normal_distribution<double> jitter(0., 2.5);	// px of corner placement error
	std::uniform_real_distribution<double> tilt(-0.6, 0.6);
	std::uniform_real_distribution<double> distance(-1200., -250.);

	const int SAMPLES = 2000;
	int rejected = 0, oversized = 0;
	std::vector<double> aspectErrors;

	for (int i = 0; i < SAMPLES; i++) {
		// bias hard towards the near-parallel regime that used to fail
		double tiltX = 0.03 * tilt(rng);
		SyntheticScene s = makeScene(900., tiltX, tilt(rng),
			Vector3{ 0., 0., distance(rng) }, 300., 200., Vector3{ 500., 400., 0. });

		Point2D corners[4] = {
			{ s.A.x + jitter(rng), s.A.y + jitter(rng) }, { s.B.x + jitter(rng), s.B.y + jitter(rng) },
			{ s.C.x + jitter(rng), s.C.y + jitter(rng) }, { s.D.x + jitter(rng), s.D.y + jitter(rng) },
		};

		QuadTransform q;
		if (!q.loadCoordinates({ s.principalPoint.x, s.principalPoint.y },
			corners[0], corners[1], corners[2], corners[3])) { rejected++; continue; }

		if (q.newWidth() <= 0 || q.newHeight() <= 0
			|| q.newWidth() >= MAX_OUTPUT_SIDE || q.newHeight() >= MAX_OUTPUT_SIDE) { oversized++; continue; }

		double aspect = (double)q.newWidth() / q.newHeight();
		aspectErrors.push_back(std::fabs(aspect - s.trueAspect()) / s.trueAspect());
	}

	CHECK_MSG(rejected == 0, std::to_string(rejected) + "/" + std::to_string(SAMPLES)
		+ " hand-placed selections were refused");
	CHECK_MSG(oversized == 0, std::to_string(oversized) + "/" + std::to_string(SAMPLES)
		+ " hand-placed selections produced an out-of-range output size");

	// the height is assumed in this regime, so individual scans are only roughly right;
	// what matters is that the typical one still is
	std::sort(aspectErrors.begin(), aspectErrors.end());
	CHECK(!aspectErrors.empty());
	if (aspectErrors.empty()) return;
	double median = aspectErrors[aspectErrors.size() / 2];
	CHECK_MSG(median < 0.10, "median aspect error across noisy near-parallel views was "
		+ std::to_string(100. * median) + "%");
}

// Selections with no area at all cannot produce a document plane and have to be refused
// rather than turned into a nonsense allocation.
TEST(degenerate_selections_are_rejected) {
	QuadTransform q;
	CHECK_MSG(!q.loadCoordinates({ 500., 400. },
		{ 400., 400. }, { 400., 400. }, { 400., 400. }, { 400., 400. }),
		"a selection collapsed to a single point was accepted");

	CHECK_MSG(!q.loadCoordinates({ 500., 400. },
		{ 300., 400. }, { 500., 400. }, { 700., 400. }, { 350., 400. }),
		"a selection with all four corners on one line was accepted");
}

// The symptom that started this: a wrong floor plane can put its horizon inside the
// selected quadrilateral, which throws the projected corners off towards infinity and
// asks Dart for an allocation of many gigabytes. Sweep a wide range of plausible photos
// and assert the output stays a believable size.
TEST(output_size_stays_bounded_across_poses) {
	std::mt19937 rng(20240817);
	std::uniform_real_distribution<double> tilt(-0.6, 0.6);
	std::uniform_real_distribution<double> offset(-150., 150.);
	std::uniform_real_distribution<double> distance(-1200., -250.);

	const int SAMPLES = 2000;

	int rejected = 0, oversized = 0, badAspect = 0;
	double worstArea = 0.;

	for (int i = 0; i < SAMPLES; i++) {
		// every third sample is nearly parallel about one axis, the regime where the
		// camera height cannot be recovered at all
		double tiltX = (i % 3 == 0) ? 0.02 * tilt(rng) : tilt(rng);
		double tiltY = tilt(rng);
		SyntheticScene s = makeScene(900., tiltX, tiltY,
			Vector3{ offset(rng), offset(rng), distance(rng) }, 300., 200.);

		QuadTransform q;
		if (!load(q, s)) { rejected++; continue; }

		double w = q.newWidth(), h = q.newHeight();
		worstArea = std::max(worstArea, w * h);

		if (!(w > 0. && h > 0. && w < MAX_OUTPUT_SIDE && h < MAX_OUTPUT_SIDE)) { oversized++; continue; }
		// an ill-conditioned view has to assume a camera height, so only the shape of a
		// well-conditioned one is pinned down exactly. Both axes have to be tilted: a
		// pair of edges parallel in the picture puts its vanishing point at infinity
		// whichever axis it belongs to.
		if (std::fabs(tiltX) > 0.15 && std::fabs(tiltY) > 0.15
			&& std::fabs(w / h - s.trueAspect()) > ASPECT_TOLERANCE * s.trueAspect()) badAspect++;
	}

	CHECK_MSG(rejected == 0, std::to_string(rejected) + "/" + std::to_string(SAMPLES)
		+ " valid perspective views were rejected by loadCoordinates");
	CHECK_MSG(oversized == 0, std::to_string(oversized) + "/" + std::to_string(SAMPLES)
		+ " views produced an out-of-range output size (worst area " + std::to_string(worstArea) + " px)");
	CHECK_MSG(badAspect == 0, std::to_string(badAspect) + "/" + std::to_string(SAMPLES)
		+ " well-conditioned views produced the wrong aspect ratio");
}

// Full pipeline including process(): paint the document with four coloured quadrants,
// render the picture the camera would have captured, rectify it, and check each quadrant
// came back where it belongs. Catches sign flips and axis swaps that the numeric checks
// above can miss because they only look at magnitudes.
TEST(process_rectifies_a_rendered_picture) {
	const int SRC_W = 1000, SRC_H = 800, CHANNELS = 4;
	SyntheticScene s = makeScene(800., 0.30, -0.20,
		Vector3{ 40., -30., -300. }, 300., 200., Vector3{ SRC_W / 2., SRC_H / 2., 0. });

	// quadrant colours, indexed by [u > 0][v > 0]
	const unsigned char QUADRANT[2][2][3] = {
		{ { 220,  40,  40 }, {  40,  60, 220 } },
		{ {  40, 200,  40 }, { 230, 220,  60 } },
	};

	std::vector<unsigned char> srcData((size_t)SRC_W * SRC_H * CHANNELS, 0);
	Bitmap src(srcData.data(), SRC_W, SRC_H, CHANNELS, false);

	for (int y = 0; y < SRC_H; y++) {
		for (int x = 0; x < SRC_W; x++) {
			double u, v;
			if (!unprojectOntoDocument(s, x, y, u, v)) continue;
			if (std::fabs(u) > s.halfWidth || std::fabs(v) > s.halfHeight) continue;

			const unsigned char* color = QUADRANT[u > 0.][v > 0.];
			for (int ch = 0; ch < 3; ch++) src(x, y, ch) = color[ch];
			src(x, y, 3) = 255;
		}
	}

	QuadTransform q;
	CHECK_MSG(load(q, s), "loadCoordinates rejected a valid perspective view");

	int w = q.newWidth(), h = q.newHeight();
	CHECK(w > 0 && h > 0 && (double)w * h < 1e7);
	if (!(w > 0 && h > 0 && (double)w * h < 1e7)) return;

	std::vector<unsigned char> dstData((size_t)w * h * CHANNELS, 0);
	Bitmap dst(dstData.data(), w, h, CHANNELS, false);

	BitmapSegment srcSeg = bitmapAsSegment(src);
	BitmapSegment dstSeg = bitmapAsSegment(dst);
	q.process(srcSeg, dstSeg);

	// output x runs along +u and output y along +v, so the destination quadrants line up
	// with the source ones; sample a patch well inside each to stay clear of the seams
	const int PATCH = 15;
	for (int qx = 0; qx < 2; qx++) {
		for (int qy = 0; qy < 2; qy++) {
			int cx = (int)((qx ? 0.75 : 0.25) * w);
			int cy = (int)((qy ? 0.75 : 0.25) * h);
			const unsigned char* expected = QUADRANT[qx][qy];

			int matched = 0, total = 0;
			for (int dy = -PATCH; dy <= PATCH; dy++) {
				for (int dx = -PATCH; dx <= PATCH; dx++) {
					total++;
					if (dst(cx + dx, cy + dy, 0) == expected[0]
						&& dst(cx + dx, cy + dy, 1) == expected[1]
						&& dst(cx + dx, cy + dy, 2) == expected[2]) matched++;
				}
			}

			CHECK_MSG(matched == total, "quadrant (" + std::to_string(qx) + ", " + std::to_string(qy)
				+ ") only matched " + std::to_string(matched) + "/" + std::to_string(total)
				+ " pixels; sampled colour was (" + std::to_string(dst(cx, cy, 0)) + ", "
				+ std::to_string(dst(cx, cy, 1)) + ", " + std::to_string(dst(cx, cy, 2)) + ")");
		}
	}
}
