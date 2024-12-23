#include "line.h"

Line::Line(const Vector3& point1, const Vector3& point2) {
	base = point1;
	dir = point2 - point1;
	basicLinearAssert(!dir.IsNull());

	dir = dir.Unit();
}

double Line::Distance(const Vector3& point) const{
	return Cross(dir, base - point).Abs(); // dir is unit vector
}

Vector3 Intersection(const Line& l1, const Line& l2) {
	double num, denom;

	double lambda1;
	num = (l2.base.x - l1.base.x) * l2.dir.y - (l2.base.y - l1.base.y) * l2.dir.x;
	denom = l1.dir.x * l2.dir.y - l1.dir.y * l2.dir.x;

	if (eq(denom, 0.)) {
		basicLinearAssert(eq(num, 0.));
		lambda1 = SIGNAL;
	}
	else lambda1 = num / denom;

	double lambda2;
	num = (l2.base.y - l1.base.y) * l2.dir.z - (l2.base.z - l1.base.z) * l2.dir.y;
	denom = l1.dir.y * l2.dir.z - l1.dir.z * l2.dir.y;

	if (eq(denom, 0.)) {
		basicLinearAssert(eq(num, 0.));
		lambda2 = SIGNAL;
	}
	else lambda2 = num / denom;

	basicLinearAssert(lambda1 != SIGNAL || lambda2 != SIGNAL);
	double lambda;
	if (lambda1 == SIGNAL) lambda = lambda2;
	else if (lambda2 == SIGNAL) lambda = lambda1;
	else {
		basicLinearAssert(eq(lambda1, lambda2));
		lambda = lambda1;
	}

	// check if l1.base + lambda * l1.dir is on l2
	Vector3 v = (l1.base + lambda * l1.dir - l2.base);
	if (!v.IsNull()) {
		v = v.Unit();
		Vector3 u = l2.dir.Unit();
		basicLinearAssert((eq(v.x, u.x) && eq(v.y, u.y) && eq(v.z, u.z)) || (eq(-v.x, u.x) && eq(-v.y, u.y) && eq(-v.z, u.z)));
	}

	return l1.base + lambda1 * l1.dir;
}