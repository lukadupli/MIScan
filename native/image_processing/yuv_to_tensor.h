#pragma once

#include <cstdint>

extern "C" {
    // Converts one Android YUV_420_888 camera frame into the segmentation
    // network's input: upright, resized, RGB, normalised, channels-first float32.
    //
    // For each output pixel it walks backwards: output pixel -> point in the
    // upright frame (plain per-axis resize) -> point in the raw sensor buffer
    // (inverse of the sensor's mounting rotation) -> nearest Y/U/V sample. So
    // there is no full-resolution intermediate, and the rotation costs nothing
    // extra.
    //
    // y, u, v                  the three planes. U and V are half resolution
    //                          in both directions.
    // *RowStride, *PixelStride bytes between rows / between samples, per plane.
    //                          Do not assume 1: on many devices U and V are
    //                          interleaved in memory, giving a pixel stride of 2.
    // width, height            raw sensor frame size, before rotation
    // sensorOrientation        0, 90, 180 or 270 -- how far the frame must turn
    //                          to be upright
    // out                      3 * outWidth * outHeight floats, written as three
    //                          whole planes: all R, then all G, then all B
    // norm                     6 doubles: per-channel mean then std, applied as
    //                          (value / 255 - mean) / std. Passed in rather than
    //                          hard-coded so lib/debug/frame_math.dart stays the
    //                          one place those constants live on the app side.
    //
    // Pure function: no state, safe to call from any thread.
    void YuvToChwTensor(
        const uint8_t* y, int yRowStride, int yPixelStride,
        const uint8_t* u, int uRowStride, int uPixelStride,
        const uint8_t* v, int vRowStride, int vPixelStride,
        int width, int height, int sensorOrientation,
        float* out, int outWidth, int outHeight,
        const double* norm);
}
