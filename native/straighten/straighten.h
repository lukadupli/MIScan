#pragma once

extern "C" {
	bool LoadCornerCoordinates(double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3);
	unsigned int GetWidth();
	unsigned int GetHeight();
	void ProcessBitmapData(unsigned char* src, unsigned int src_width, unsigned int src_height, unsigned int src_channels, unsigned char* dst, bool assure_stride_is_divisible_by_4);
}