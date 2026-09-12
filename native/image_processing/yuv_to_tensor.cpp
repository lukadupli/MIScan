#include "yuv_to_tensor.h"

// Not std::clamp: that needs C++17, and android/app/CMakeLists.txt does not pin
// a language standard, so it would quietly depend on the NDK compiler's default.
static inline double clampTo(double x, double lo, double hi) {
    return x < lo ? lo : (x > hi ? hi : x);
}

// A port of the Dart loop that used to do this (yuv420ToChwTensor in
// lib/detection/frame_math.dart), which cost ~90 ms a frame on a SM-A137F. One
// deliberate change: the rotation fix described at the switch below. Apart from
// that the arithmetic is identical -- same operations, same order, doubles
// throughout, rounded to float only on the final store -- which is what allowed
// the port to be checked by exact comparison against the Dart output on real
// camera frames, rather than by eye.
void YuvToChwTensor(
    const uint8_t* y, int yRowStride, int yPixelStride,
    const uint8_t* u, int uRowStride, int uPixelStride,
    const uint8_t* v, int vRowStride, int vPixelStride,
    int width, int height, int sensorOrientation,
    float* out, int outWidth, int outHeight,
    const double* norm)
{
    // Dart evaluates a + b * c as a multiply then an add, each rounded
    // separately. Clang on ARM64 would otherwise fuse the pair into one FMA
    // with a single rounding, and the last bit of the result would no longer
    // match -- harmless to the network, but it would turn the parity check
    // from "equal" into "close", which is a much weaker statement.
    #pragma clang fp contract(off)

    const bool swapped = sensorOrientation == 90 || sensorOrientation == 270;
    const double rotW = swapped ? height : width;
    const double rotH = swapped ? width : height;
    const double maxX = width - 1;
    const double maxY = height - 1;
    const int plane = outWidth * outHeight;

    for (int oy = 0; oy < outHeight; ++oy) {
        const double uy = (oy + 0.5) * rotH / outHeight;
        for (int ox = 0; ox < outWidth; ++ox) {
            const double ux = (ox + 0.5) * rotW / outWidth;

            // ux, uy are continuous coordinates measured at pixel centres, so a
            // flipped axis maps x -> extent - x. The Dart version this replaced
            // used extent - 1 - x, which is the flip for *integer* indices:
            // mixed with centre coordinates it sampled one pixel short on every
            // flipped axis, used the first row or column twice and never read
            // the last. native/test/yuv_to_tensor_test.cpp pins this down.
            double sxD, syD;
            switch (sensorOrientation) {
                case 90:  sxD = uy;         syD = height - ux; break;
                case 270: sxD = width - uy; syD = ux;          break;
                case 180: sxD = width - ux; syD = height - uy; break;
                default:  sxD = ux;         syD = uy;          break;
            }
            // Truncation toward zero, as Dart's toInt() does.
            const int sx = static_cast<int>(clampTo(sxD, 0.0, maxX));
            const int sy = static_cast<int>(clampTo(syD, 0.0, maxY));
            const int cx = sx >> 1;
            const int cy = sy >> 1;

            const double yD = y[sy * yRowStride + sx * yPixelStride];
            const double uD = u[cy * uRowStride + cx * uPixelStride] - 128.0;
            const double vD = v[cy * vRowStride + cx * vPixelStride] - 128.0;

            // Full-range BT.601 (JFIF) coefficients, the same ones the Dart
            // version used.
            const double r = clampTo(yD + 1.402 * vD, 0.0, 255.0);
            const double g = clampTo(yD - 0.344136 * uD - 0.714136 * vD, 0.0, 255.0);
            const double b = clampTo(yD + 1.772 * uD, 0.0, 255.0);

            const int idx = oy * outWidth + ox;
            out[idx]             = static_cast<float>((r / 255.0 - norm[0]) / norm[3]);
            out[plane + idx]     = static_cast<float>((g / 255.0 - norm[1]) / norm[4]);
            out[2 * plane + idx] = static_cast<float>((b / 255.0 - norm[2]) / norm[5]);
        }
    }
}
