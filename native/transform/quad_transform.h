#pragma once

#include "../basic_linear/helpers.h"
#include "../basic_linear/line.h"
#include "../basic_linear/plane.h"
#include "../basic_linear/vector.h"

#include "parallel_for.h"
#include "bitmap.h"

#include <assert.h>
#include <cmath>

struct Point2D {
	double x, y;
};
class QuadTransform {
private:
	Vector3 S, newOrigin, unitX, unitY;
	Plane fplane;
	double h;
	int neww, newh;

public:
	static Vector3 putOnFloor(const Vector3& point, const Plane& fplane, double height);
	static Vector3 correspondingSrcCoors(int floorx, int floory, const Vector3& origin, const Vector3& unitx, const Vector3& unity, double height);

	// origin of the coordinate system used given in reference to picture's upper-left corner
	Vector3 referentOrigin() const;

	Plane floorPlane() const;
	// referent coordinate system's origin is AT THE DIAGONAL INTERSECTION of points given in loadCoordinates!!!
	Vector3 floorPlaneOrigin() const;
	Vector3 floorPlaneUnitX() const;
	Vector3 floorPlaneUnitY() const;
	double cameraHeight() const;

	bool canTransform(Point2D p1, Point2D p2, Point2D p3, Point2D p4);
	bool loadCoordinates(Point2D p1, Point2D p2, Point2D p3, Point2D p4);
	int newWidth();
	int newHeight();
	void process(BitmapSegment& src, BitmapSegment& dst);
};