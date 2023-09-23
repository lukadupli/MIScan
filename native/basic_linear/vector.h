#pragma once

struct Vector3 {
	double x, y, z;

	bool IsNull() const;
	double Abs() const;
	Vector3 Unit() const;
};

Vector3 operator+(const Vector3& a, const Vector3& b);
Vector3 operator-(const Vector3& v);
Vector3 operator-(const Vector3& a, const Vector3& b);

Vector3 operator*(double scalar, const Vector3& v);
Vector3 operator*(const Vector3& v, double scalar);
Vector3 operator/(const Vector3& v, double scalar);

double operator*(const Vector3& a, const Vector3& b);

Vector3 Cross(const Vector3& a, const Vector3& b);