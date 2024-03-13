#pragma once

struct Bitmap {
	int stride, width, height, channels;
	unsigned char* data;

	Bitmap(unsigned char* data, int width, int height, int channels, bool stride4);
	void setPadding(bool padded);
	bool inRange(int x, int y, int channel);
	unsigned char& operator()(int x, int y, int channel);
};

struct BitmapSegment {
	Bitmap& bitmap;
	int x0, y0, width, height;

	BitmapSegment(Bitmap& bitmap, int x0, int y0, int width, int height);
	BitmapSegment(BitmapSegment& old, int x0, int y0, int width, int height);
	bool inRange(int x, int y, int channel);
	unsigned char& operator()(int x, int y, int channel);

	void pasteWithResize(BitmapSegment& source);
};

inline BitmapSegment bitmapAsSegment(Bitmap& bitmap) {
	return BitmapSegment{ bitmap, 0, 0, bitmap.width, bitmap.height };
}