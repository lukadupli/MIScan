#include "plane.h"
#include <assert.h>
#include <iostream>

Plane::Plane(const Line& l1, const Line& l2) {
	v = Cross(l1.dir, l2.dir).Unit();
	b = v * l1.base;
	assert(eq(v * l2.base, b));
}
Vector3 Plane::Intersection(const Line& l) const {
	assert(!eq(v * l.dir, 0.));

	double lambda = (b - v * l.base) / (v * l.dir);
	return l.base + lambda * l.dir;
}
