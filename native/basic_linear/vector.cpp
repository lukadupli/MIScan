#include "vector.h"
#include <cmath>
#include <assert.h>

bool Vector3::IsNull() const { return x == 0 && y == 0 && z == 0; }
double Vector3::Abs() const { return sqrt(x * x + y * y + z * z); }
Vector3 Vector3::Unit() const { return *this / Abs(); }

Vector3 operator+(const Vector3& a, const Vector3& b) {
	return { a.x + b.x, a.y + b.y, a.z + b.z };
}
Vector3 operator-(const Vector3& v) {
	return { -v.x, -v.y, -v.z };
}
Vector3 operator-(const Vector3& a, const Vector3& b) {
	return a + -b;
}

Vector3 operator*(double scalar, const Vector3& v) {
	return { scalar * v.x, scalar * v.y, scalar * v.z };
}
Vector3 operator*(const Vector3& v, double scalar) {
	return scalar * v;
}
Vector3 operator/(const Vector3& v, double scalar) {
	return { v.x / scalar, v.y / scalar, v.z / scalar };
}

double operator*(const Vector3& a, const Vector3& b) {
	return a.x * b.x + a.y * b.y + a.z * b.z;
}

Vector3 Cross(const Vector3& a, const Vector3& b) {
	return
	{
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x
	};
}