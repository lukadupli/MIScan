#include "quad_transform.h"

Vector3 QuadTransform::putOnFloor(const Vector3& point, const Plane& fplane, double height) {
    Line l{ {0., 0., height}, point };

    if (eq(fplane.v * l.dir, 0.)) return point;
    return fplane.Intersection(l);
}

// transformation of floor (x, y) coordinates to source (x, y, 0) coordinates based on fplane origin and fplane unit vectors 
Vector3 QuadTransform::correspondingSrcCoors(int floorx, int floory, const Vector3& origin, const Vector3& unitx, const Vector3& unity, double height) {
    Vector3 real = floorx * unitx + floory * unity + origin;
    Line l{ {0., 0., height}, real };

    // intersection with picture xy plane
    // l.dir.z is never 0
    return l.base - (l.base.z / l.dir.z) * l.dir;
}

Vector3 QuadTransform::referentOrigin() const {
    return S;
}

Plane QuadTransform::floorPlane() const {
    return fplane;
}

Vector3 QuadTransform::floorPlaneOrigin() const {
    return newOrigin;
}
Vector3 QuadTransform::floorPlaneUnitX() const {
    return unitX;
}
Vector3 QuadTransform::floorPlaneUnitY() const {
    return unitY;
}
double QuadTransform::cameraHeight() const {
    return h;
}

bool QuadTransform::canTransform(Point2D p1, Point2D p2, Point2D p3, Point2D p4) {
    Vector3 A{ p1.x, p1.y, 0. };
    Vector3 D{ p2.x, p2.y, 0. };
    Vector3 C{ p3.x, p3.y, 0. };
    Vector3 B{ p4.x, p4.y, 0. };

    S = Intersection(Line(A, C), Line(B, D));
    A = A - S; B = B - S; C = C - S; D = D - S;

    double a = A.Abs(), b = B.Abs(), c = C.Abs(), d = D.Abs();

    // the points already form a rectangle
    if (eq(a, c) && eq(b, d) && eq(a, b)) return true;

    return !(eq(a * b, c * d) || eq(b * c, a * d));
}

int QuadTransform::newWidth() { return neww; }
int QuadTransform::newHeight() { return newh; }

bool QuadTransform::loadCoordinates(Point2D p1, Point2D p2, Point2D p3, Point2D p4) {
    Vector3 A{ p1.x, p1.y, 0. };
    Vector3 D{ p2.x, p2.y, 0. };
    Vector3 C{ p3.x, p3.y, 0. };
    Vector3 B{ p4.x, p4.y, 0. };

    // centering around diagonal intersection
    S = Intersection(Line(A, C), Line(B, D));
    A = A - S; B = B - S; C = C - S; D = D - S;

    // calculating the distance l between projected corners and origin
    double a = A.Abs(), b = B.Abs(), c = C.Abs(), d = D.Abs();

    if (eq(a, c) && eq(b, d) && eq(a, b)) {
        // the points already form a rectangle
        newOrigin = A;
        Vector3 xedge = D - A;
        Vector3 yedge = B - A;
        h = 100.0; // when points already form a rectangle, this can be anything

        unitX = xedge.Unit(); unitY = yedge.Unit();

        neww = xedge.Abs(); newh = yedge.Abs();

        return true;
    }

    // these points can't be transformed to make a rectangle, or they cannot be uniquely transformed
    if (eq(a * b, c * d) || eq(b * c, a * d)) return false;
    double l = sqrt(abs((sq(a * c * (b - d)) - sq(b * d * (a - c))) / ((a * b - c * d) * (b * c - a * d))));

    // calculating pitches of projected diagonals relative to pictured diagonals
    double pitch1 = sqrt(abs(sq((a + c) * l / (2 * a * c)) - 1));
    if (a > c) pitch1 = -pitch1;

    Line d1{ A, C };
    // we know d1 is passing through the origin
    d1.base = Vector3{ 0., 0., 0. };
    d1.dir.z = pitch1; // since origin is the base, and dir iz unit vector, this makes d1 a line between points A2 and C2
    d1.dir = d1.dir.Unit(); // keeping dir unit

    double pitch2 = sqrt(abs(sq((b + d) * l / (2 * b * d)) - 1));
    if (b > d) pitch2 = -pitch2;

    Line d2{ B, D };
    // we know d2 is passing through the origin
    d2.base = Vector3{ 0., 0., 0. };
    d2.dir.z = pitch2; // since origin is the base, and dir iz unit vector, this makes d2 a line between points B2 and D2
    d2.dir = d2.dir.Unit(); // keeping dir unit

    // plane of the floor
    fplane = Plane{ d1, d2 };

    // height of the camera
    h = sqrt(abs(sq((a + c) * l / (2 * a * c)) - 1)) * 2 * a * c / abs(a - c);

    Vector3 A2 = putOnFloor(A, fplane, h), B2 = putOnFloor(B, fplane, h), D2 = putOnFloor(D, fplane, h);

    Vector3 yedge = B2 - A2, xedge = D2 - A2;

    newOrigin = A2;
    unitX = xedge.Unit(); unitY = yedge.Unit();

    neww = xedge.Abs(); newh = yedge.Abs();

    return true;
}

void QuadTransform::process(BitmapSegment& src, BitmapSegment& dst) {
    parallel_for(dst.width, [&](int start, int end) {
        for (int x = start; x < end; x++) {
            for (int y = 0; y < dst.height; y++) {
                Vector3 v = correspondingSrcCoors(x, y, newOrigin, unitX, unitY, h) + S;
                int xr = std::round(v.x);
                int yr = std::round(v.y);
                for (int z = 0; z < src.bitmap.channels; z++) {
                    if (src.inRange(xr, yr, z)) dst(x, y, z) = src(xr, yr, z);
                    else dst(x, y, z) = 0;
                }
            }
        }
    });
}