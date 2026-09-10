#include "../image_processing/yuv_to_tensor.h"
#include "test_util.h"

#include <string>
#include <vector>

// YuvToChwTensor turns a camera frame into the network's input. These tests pin
// down the three things it has to get right -- which source pixel each output
// pixel samples (rotation), how it reads the planes (strides), and the maths it
// applies (colour conversion, normalisation, layout) -- on frames small enough
// that every expected value can be written down by hand.

namespace {

	constexpr double IDENTITY_NORM[6] = { 0.0, 0.0, 0.0, 1.0, 1.0, 1.0 }; // out = channel / 255

	struct Frame {
		int w, h;
		int yRow, yPix, uRow, uPix, vRow, vPix;
		std::vector<uint8_t> y, u, v;
	};

	// A frame with neutral chroma (U = V = 128), so R = G = B = Y exactly, and a
	// distinct Y per pixel: the output then says which source pixel was sampled.
	Frame labelledGreyFrame(int w, int h) {
		Frame f{ w, h, w, 1, (w + 1) / 2, 1, (w + 1) / 2, 1, {}, {}, {} };
		f.y.resize(w * h);
		for (int i = 0; i < w * h; i++) f.y[i] = (uint8_t)(10 * (i + 1));
		const int chroma = ((w + 1) / 2) * ((h + 1) / 2);
		f.u.assign(chroma, 128);
		f.v.assign(chroma, 128);
		return f;
	}

	std::vector<float> convert(const Frame& f, int orientation, int outW, int outH,
		const double* norm = IDENTITY_NORM) {
		std::vector<float> out(3 * outW * outH, -1.0f);
		YuvToChwTensor(f.y.data(), f.yRow, f.yPix, f.u.data(), f.uRow, f.uPix,
			f.v.data(), f.vRow, f.vPix, f.w, f.h, orientation, out.data(), outW, outH, norm);
		return out;
	}

	// Checks every output pixel samples the source pixel `expect` names.
	template <typename Expect>
	void checkMapping(const Frame& f, int orientation, int outW, int outH, Expect expect) {
		const auto out = convert(f, orientation, outW, outH);
		for (int oy = 0; oy < outH; oy++) {
			for (int ox = 0; ox < outW; ox++) {
				int sx, sy;
				expect(ox, oy, sx, sy);
				const double want = f.y[sy * f.w + sx] / 255.0;
				const double got = out[oy * outW + ox];
				CHECK_MSG(std::fabs(got - want) < 1e-6,
					"orientation " + std::to_string(orientation) + ": output (" + std::to_string(ox) + "," +
					std::to_string(oy) + ") should sample source (" + std::to_string(sx) + "," +
					std::to_string(sy) + ") = " + std::to_string(f.y[sy * f.w + sx]) + ", got " +
					std::to_string(got * 255.0));
			}
		}
	}

} // namespace

// At 1:1 scale each output pixel must land on exactly one source pixel, and a
// rotation must be a permutation: every source pixel used once, none twice.

TEST(yuv_orientation_0_is_identity) {
	const Frame f = labelledGreyFrame(4, 2);
	checkMapping(f, 0, 4, 2, [](int ox, int oy, int& sx, int& sy) { sx = ox; sy = oy; });
}

TEST(yuv_orientation_90_rotates_clockwise) {
	// A 4x2 landscape sensor frame, upright as 2 wide by 4 tall.
	const Frame f = labelledGreyFrame(4, 2);
	checkMapping(f, 90, 2, 4, [&](int ox, int oy, int& sx, int& sy) { sx = oy; sy = f.h - 1 - ox; });
}

TEST(yuv_orientation_270_rotates_anticlockwise) {
	const Frame f = labelledGreyFrame(4, 2);
	checkMapping(f, 270, 2, 4, [&](int ox, int oy, int& sx, int& sy) { sx = f.w - 1 - oy; sy = ox; });
}

TEST(yuv_orientation_180_flips_both_axes) {
	const Frame f = labelledGreyFrame(4, 2);
	checkMapping(f, 180, 4, 2, [&](int ox, int oy, int& sx, int& sy) { sx = f.w - 1 - ox; sy = f.h - 1 - oy; });
}

TEST(yuv_honours_row_padding_and_chroma_pixel_stride) {
	// Rows padded past the image width, and U/V samples two bytes apart -- the
	// layout of an interleaved-chroma device. The gaps hold junk that must never
	// be read.
	const int w = 4, h = 2;
	Frame f{ w, h, w + 3, 1, 8, 2, 8, 2, {}, {}, {} };
	f.y.assign(f.yRow * h, 255);            // junk fill, including the padding
	for (int y = 0; y < h; y++)
		for (int x = 0; x < w; x++) f.y[y * f.yRow + x] = 128;
	f.u.assign(f.uRow * 1, 7);              // chroma is 2x1 here; junk elsewhere
	f.v.assign(f.vRow * 1, 7);
	const uint8_t us[2] = { 100, 150 }, vs[2] = { 140, 110 };
	for (int cx = 0; cx < 2; cx++) {
		f.u[cx * f.uPix] = us[cx];
		f.v[cx * f.vPix] = vs[cx];
	}

	const auto out = convert(f, 0, w, h);
	const int plane = w * h;
	for (int oy = 0; oy < h; oy++) {
		for (int ox = 0; ox < w; ox++) {
			const int cx = ox >> 1;
			const double uD = us[cx] - 128.0, vD = vs[cx] - 128.0;
			const int idx = oy * w + ox;
			CHECK_NEAR(out[idx], (128.0 + 1.402 * vD) / 255.0, 1e-6);
			CHECK_NEAR(out[plane + idx], (128.0 - 0.344136 * uD - 0.714136 * vD) / 255.0, 1e-6);
			CHECK_NEAR(out[2 * plane + idx], (128.0 + 1.772 * uD) / 255.0, 1e-6);
		}
	}
}

TEST(yuv_colour_conversion_clamps_to_0_255) {
	// Chosen so red overflows (200 + 1.402*127 = 378) and blue underflows
	// (200 - 1.772*128 = -26.8), with green in range.
	Frame f{ 2, 2, 2, 1, 1, 1, 1, 1, { 200, 200, 200, 200 }, { 0 }, { 255 } };
	const auto out = convert(f, 0, 2, 2);
	const double g = 200.0 - 0.344136 * -128.0 - 0.714136 * 127.0;
	for (int i = 0; i < 4; i++) {
		CHECK_NEAR(out[i], 1.0, 1e-6);
		CHECK_NEAR(out[4 + i], g / 255.0, 1e-6);
		CHECK_NEAR(out[8 + i], 0.0, 1e-6);
	}
}

TEST(yuv_normalises_each_channel_into_its_own_plane) {
	// The real ImageNet constants the app passes, on uniform mid-grey.
	const double norm[6] = { 0.485, 0.456, 0.406, 0.229, 0.224, 0.225 };
	Frame f{ 2, 2, 2, 1, 1, 1, 1, 1, { 128, 128, 128, 128 }, { 128 }, { 128 } };
	const auto out = convert(f, 0, 2, 2, norm);
	for (int c = 0; c < 3; c++) {
		const double want = (128.0 / 255.0 - norm[c]) / norm[3 + c];
		for (int i = 0; i < 4; i++) CHECK_NEAR(out[c * 4 + i], want, 1e-6);
	}
}
