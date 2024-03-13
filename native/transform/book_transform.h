#pragma once

#include "quad_transform.h"

class BookTransform {
private:
	QuadTransform quad{};

	int neww = 0, newh = 0;
	std::vector<std::pair<double, double>> xzValues; // (x, z) value in book model for each horizontal position in range [0, neww>
public:
	bool canTransform(Point2D p1, Point2D p2, Point2D p3, Point2D p4);
	// curvePosition false -> curve is between p1 and p2, curvePosition true -> curve is between p4 and p3
	// CURVE HAS TO CONTAIN ITS ENDPOINTS
	bool loadCoordinates(Point2D p1, Point2D p2, Point2D p3, Point2D p4, 
		const std::vector<Point2D> curve, bool curvePosition);
	int newWidth();
	int newHeight();
	void process(BitmapSegment& srcbmp, BitmapSegment& dstbmp);
};