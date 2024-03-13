#pragma once

#ifdef _WIN32
#define API __declspec(dllexport)
#else
#define API
#endif

extern "C" {
	API void Prepare(bool input_padded, bool output_padded);

	API bool CanTransform(double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3);
	API bool BookCanTransform(double* cornerXs, double* cornerYs, int curveLength, double* curveXs, double* curveYs, bool curvePos);

	API bool LoadCoordinates(double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3);
	// cornerXs - 4 elements: x0, x1, x2, x3, cornerYs - 4 elements: y0, y1, y2, y3
	// curvePos - false if curve is from A to B, true if curve is from D to C
	// CURVE HAS TO CONTAIN ITS ENDPOINTS
	API bool BookLoadCoordinates(double* cornerXs, double* cornerYs, int curveLength, double* curveXs, double* curveYs, bool curvePos);

	API int GetWidth();
	API int GetHeight();
	API int GetRequiredDstSize(int bytes_per_pixel);

	API void Process(unsigned char* src, int src_width, int src_height, int src_channels, unsigned char* dst);
	API void BookProcess(unsigned char* src, int src_width, int src_height, int src_channels, unsigned char* dst);
}