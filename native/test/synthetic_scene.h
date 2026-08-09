#pragma once

#include "../basic_linear/line.h"
#include "../basic_linear/plane.h"
#include "../basic_linear/vector.h"

#include <cmath>

// Ground truth for the transform tests.
//
// The transforms model a pinhole camera at (0, 0, h) looking at the xy plane, which
// holds the picture. A SyntheticScene goes the other way: it starts from a rectangle
// that really is flat and rectangular in 3D, projects its corners through that same
// camera, and hands back the quadrilateral a photo would have contained. Feeding that
// quadrilateral to QuadTransform must recover the numbers the scene was built from.

struct SyntheticScene {
	double height;			// camera height, the h the transform has to recover
	Vector3 normal;			// unit normal of the document plane, sign-normalised to normal.z > 0
	Vector3 center;			// document centre in 3D
	Vector3 axisU, axisV;	// unit vectors spanning the document plane
	double halfWidth, halfHeight;
	Vector3 principalPoint;	// where the picture's (0, 0) sits relative to the camera axis

	// projected corners in picture coordinates, counterclockwise from bottom left,
	// matching the order QuadTransform::loadCoordinates expects
	Vector3 A, B, C, D;

	double trueAspect() const { return halfWidth / halfHeight; }
};

// Projects a 3D point through the camera at (0, 0, height) onto the picture plane z = 0.
inline Vector3 projectThroughCamera(const Vector3& point, double height) {
	Vector3 dir = point - Vector3{ 0., 0., height };
	double t = -height / dir.z;	// solve height + t * dir.z == 0
	return Vector3{ t * dir.x, t * dir.y, 0. };
}

// tiltX / tiltY select how strongly the document is tilted away from facing the camera,
// distance is its (negative) z, and principalPoint offsets the picture's coordinate origin
// the way a real image does by measuring from its top-left corner.
inline SyntheticScene makeScene(double cameraHeight, double tiltX, double tiltY,
	Vector3 documentCenter, double halfWidth, double halfHeight,
	Vector3 principalPoint = Vector3{ 0., 0., 0. })
{
	SyntheticScene scene;
	scene.height = cameraHeight;
	scene.normal = Vector3{ tiltX, tiltY, 1. }.Unit();
	scene.center = documentCenter;
	scene.halfWidth = halfWidth;
	scene.halfHeight = halfHeight;
	scene.principalPoint = principalPoint;

	scene.axisU = Cross(scene.normal, Vector3{ 0., 1., 0. }).Unit();
	scene.axisV = Cross(scene.normal, scene.axisU).Unit();

	const Vector3& u = scene.axisU;
	const Vector3& v = scene.axisV;
	scene.A = projectThroughCamera(documentCenter - halfWidth * u - halfHeight * v, cameraHeight) + principalPoint;
	scene.B = projectThroughCamera(documentCenter + halfWidth * u - halfHeight * v, cameraHeight) + principalPoint;
	scene.C = projectThroughCamera(documentCenter + halfWidth * u + halfHeight * v, cameraHeight) + principalPoint;
	scene.D = projectThroughCamera(documentCenter - halfWidth * u + halfHeight * v, cameraHeight) + principalPoint;

	return scene;
}

// Where a picture pixel lands on the document, in (u, v) coordinates relative to the
// document centre. Returns false when the viewing ray never reaches the document, which
// happens for pixels on or past the plane's horizon.
inline bool unprojectOntoDocument(const SyntheticScene& scene, double px, double py, double& u, double& v) {
	Vector3 picturePoint = Vector3{ px, py, 0. } - scene.principalPoint;
	Vector3 camera{ 0., 0., scene.height };
	Vector3 dir = picturePoint - camera;

	double denom = scene.normal * dir;
	if (std::fabs(denom) < 1e-12) return false;

	double t = (scene.normal * (scene.center - camera)) / denom;
	if (t <= 0.) return false;	// document is behind the camera along this ray

	Vector3 hit = camera + t * dir;
	Vector3 offset = hit - scene.center;
	u = offset * scene.axisU;
	v = offset * scene.axisV;
	return true;
}

// Normal direction is only defined up to sign; compare the two consistently.
inline Vector3 orientUpward(Vector3 n) {
	return n.z < 0. ? -n : n;
}
