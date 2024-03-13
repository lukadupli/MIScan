#include "bitmap.h"

#include "parallel_for.h"

#include <cmath>

Bitmap::Bitmap(unsigned char* data, int width, int height, int channels, bool stride4) :
    width(width), height(height), channels(channels), data(data)
{
    setPadding(stride4);
}
void Bitmap::setPadding(bool padded) {
    stride = width * channels;
    if (padded && stride % 4) stride += 4 - (stride % 4);
}
bool Bitmap::inRange(int x, int y, int channel) {
    return x < width && y < height && channel < channels;
}
unsigned char& Bitmap::operator()(int x, int y, int channel) {
    return data[y * stride + x * channels + channel];
}

BitmapSegment::BitmapSegment(Bitmap& bitmap, int x0, int y0, int width, int height) : bitmap(bitmap), x0(x0), y0(y0), width(width), height(height){
}

BitmapSegment::BitmapSegment(BitmapSegment& old, int x0, int y0, int width, int height) : bitmap(old.bitmap), x0(old.x0 + x0), y0(old.y0 + y0), width(width), height(height){
}

bool BitmapSegment::inRange(int x, int y, int channel) {
    return bitmap.inRange(x + x0, y + y0, channel);
}
unsigned char& BitmapSegment::operator()(int x, int y, int channel) {
    return bitmap(x + x0, y + y0, channel);
}

double scale(double x, double oldMin, double oldMax, double newMin, double newMax) {
    return (x - oldMin) * (newMax - newMin) / (oldMax - oldMin) + newMin;
}
void BitmapSegment::pasteWithResize(BitmapSegment& source) {
    parallel_for(width, [&](int start, int end) {
        for (int x = start; x < end; x++) {
            for (int y = 0; y < height; y++) {
                for (int z = 0; z < bitmap.channels; z++) {
                    if (!inRange(x, y, z)) continue;

                    int nx = std::round(scale(x, 0, width, 0, source.width));
                    int ny = std::round(scale(y, 0, height, 0, source.height));

                    if (!source.inRange(nx, ny, z)) continue;

                    operator()(x, y, z) = source(nx, ny, z);
                }
            }
        }
    });
}
