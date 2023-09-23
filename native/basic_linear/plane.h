#pragma once

#include "helpers.h"
#include "vector.h"
#include "line.h"

struct Plane {
	Vector3 v;
	double b;

	Plane() = default;
	Plane(const Line& l1, const Line& l2);

	Vector3 Intersection(const Line& l) const;
};