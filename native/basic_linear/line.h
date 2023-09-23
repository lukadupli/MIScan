#pragma once

#include "vector.h"
#include "helpers.h"

struct Line {
	Vector3 base, dir;

	Line(const Vector3& point1, const Vector3& point2);
	double Distance(const Vector3& point) const;
};

Vector3 Intersection(const Line& l1, const Line& l2);