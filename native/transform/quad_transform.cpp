#include "quad_transform.h"

#include <algorithm>

namespace {
    // A vanishing point further from the principal point than this many scene scales is
    // treated as being at infinity: its edge pair is parallel in the picture to within
    // the accuracy the corners were placed with.
    const double VANISHING_POINT_REACH = 40.;

    // Plausible range for the camera height, which is really the focal length in pixels.
    const double MIN_HEIGHT_FACTOR = 0.2;
    const double MAX_HEIGHT_FACTOR = 20.;
    // Assumed when the picture cannot pin the height down at all. Roughly the focal
    // length of a phone camera, given the principal point is the centre of the picture.
    const double DEFAULT_HEIGHT_FACTOR = 1.8;

    // A document plane whose normal is this close to horizontal is edge-on to the camera,
    // which also puts the camera itself on the plane everything gets projected onto.
    const double MIN_PLANE_TILT = 1e-3;

    // Well past any real scan, but far below the runaway sizes the geometry produces when
    // it is asked to rectify something it cannot.
    const double MAX_OUTPUT_SIDE = 20000.;

    // Ceiling on the destination buffer the caller allocates from newWidth * newHeight.
    // 25 MP is 100 MB of RGBA, matching the guard the book path already applies in
    // lib/transform.dart, and leaves GetRequiredDstSize well clear of overflowing its int.
    const double MAX_OUTPUT_PIXELS = 25e6;

    // Sh and Th are homogenous, so their raw magnitudes carry an arbitrary scale factor
    // and mean nothing compared against zero. The vanishing point they stand for sits
    // |(x, y)| / |z| pixels from the principal point, which is what can be judged.
    bool vanishesAtInfinity(const Vector3& v, double reach) {
        return std::hypot(v.x, v.y) > std::fabs(v.z) * reach;
    }
}

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

Vector3 QuadTransform::principalPoint() const {
    return PP;
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

int QuadTransform::newWidth() { return neww; }
int QuadTransform::newHeight() { return newh; }

bool QuadTransform::loadCoordinates(Point2D pp, Point2D p1, Point2D p2, Point2D p3, Point2D p4) {
    try{
    PP = {pp.x, pp.y, 0.};
    Vector3 A{ p1.x, p1.y, 0. };
    Vector3 B{ p2.x, p2.y, 0. };
    Vector3 C{ p3.x, p3.y, 0. };
    Vector3 D{ p4.x, p4.y, 0. };

    // centering around the principal point
    A = A - PP; B = B - PP; C = C - PP; D = D - PP;

    // homogenous coordinates
    Vector3 Ah = {A.x, A.y, 1.};
    Vector3 Bh = {B.x, B.y, 1.};
    Vector3 Ch = {C.x, C.y, 1.};
    Vector3 Dh = {D.x, D.y, 1.};

    // x and y infinity points, homogenous coordinates
    Vector3 Sh = Cross(Cross(Ah, Bh), Cross(Ch, Dh));
    Vector3 Th = Cross(Cross(Ah, Dh), Cross(Bh, Ch));

    // length scale everything below is judged against. The principal point is the centre
    // of the picture, so it gives the picture's half diagonal; fall back to the selection
    // itself for callers that do not set it.
    double quadScale = std::max((C - A).Abs(), (D - B).Abs());
    if (quadScale < 1.) return false; // the four corners sit on top of each other
    double sceneScale = std::max(std::hypot(PP.x, PP.y), quadScale);

    // camera height. Orthogonal edge directions put their vanishing points either side of
    // the principal point:  Sh.x*Th.x + Sh.y*Th.y + h*h * Sh.z*Th.z = 0.  That equation
    // stops mentioning h entirely once a vanishing point reaches infinity, and goes ill
    // conditioned well before it gets there - both terms shrink together, so for corners
    // placed by hand it degrades into noise divided by noise. Only solve it while both
    // vanishing points are close enough to still say something.
    double reach = VANISHING_POINT_REACH * sceneScale;
    double hsq = -1.;
    if (!vanishesAtInfinity(Sh, reach) && !vanishesAtInfinity(Th, reach))
        hsq = -(Sh.x*Th.x + Sh.y*Th.y) / (Sh.z*Th.z);

    // a negative solution means the corners missed by more than any perspective could
    // account for, so the picture does not say how far away the camera was either
    if (hsq > 0.) h = std::min(std::max(sqrt(hsq), MIN_HEIGHT_FACTOR*sceneScale), MAX_HEIGHT_FACTOR*sceneScale);
    else h = DEFAULT_HEIGHT_FACTOR * sceneScale;

    // a direction d has its vanishing point at (-h*d.x/d.z, -h*d.y/d.z), so
    // (Sh.x/Sh.z, Sh.y/Sh.z) = (-h*d.x/d.z, -h*d.y/d.z)  =>  d ~ (Sh.x, Sh.y, -h*Sh.z)
    // A vanishing point at infinity leaves Sh.z at zero, which correctly gives back a
    // direction lying parallel to the picture plane.
    Vector3 xdir{Sh.x, Sh.y, -h*Sh.z};
    Vector3 ydir{Th.x, Th.y, -h*Th.z};

    Vector3 normal = Cross(xdir, ydir);
    if (normal.IsNull()) return false; // both edge pairs vanish in the same direction
    fplane.v = normal.Unit();
    fplane.b = 0.0; // this just scales the image, could be adjusted

    // fplane passes through the origin, so the camera at (0, 0, h) lies on it exactly when
    // the normal is horizontal. Every viewing ray would then run parallel to the plane and
    // putOnFloor would throw the corners off towards infinity.
    if (std::fabs(fplane.v.z) < MIN_PLANE_TILT) return false;

    Vector3 A2 = putOnFloor(A, fplane, h), B2 = putOnFloor(B, fplane, h), D2 = putOnFloor(D, fplane, h);

    Vector3 xedge = B2 - A2, yedge = D2 - A2;

    // corners close to the plane's horizon still project arbitrarily far away, and the
    // caller turns these straight into an allocation
    double outWidth = xedge.Abs(), outHeight = yedge.Abs();
    if (!std::isfinite(outWidth) || !std::isfinite(outHeight)) return false;
    if (outWidth < 1. || outHeight < 1.) return false;

    // Move the plane instead so one output pixel covers at most one source pixel. The
    // longest edge on each axis is what the camera resolved along it; one uniform factor
    // for both axes keeps the recovered aspect ratio intact.
    double srcWidth = std::max((B - A).Abs(), (C - D).Abs());
    double srcHeight = std::max((D - A).Abs(), (C - B).Abs());
    double scale = std::max(srcWidth / outWidth, srcHeight / outHeight);

    // never at the cost of an allocation the device cannot make - clamp the scale down and
    // accept the lost detail rather than refusing a scan that is otherwise perfectly good
    scale = std::min(scale, MAX_OUTPUT_SIDE / std::max(outWidth, outHeight));
    scale = std::min(scale, sqrt(MAX_OUTPUT_PIXELS / (outWidth * outHeight)));
    if (!std::isfinite(scale) || scale <= 0.) return false;

    outWidth *= scale; outHeight *= scale;
    if (outWidth < 1. || outHeight < 1.) return false;
    if (outWidth > MAX_OUTPUT_SIDE || outHeight > MAX_OUTPUT_SIDE) return false;

    // scaling the plane about the camera leaves its normal, and so unitX and unitY, alone
    Vector3 camera{ 0., 0., h };
    fplane.b = (1. - scale) * h * fplane.v.z;

    newOrigin = camera + scale * (A2 - camera);
    unitX = xedge.Unit(); unitY = yedge.Unit();

    neww = (int)outWidth; newh = (int)outHeight;

    return true;
    } 
    catch(const BasicLinearException&) {return false;}  
}

void QuadTransform::process(BitmapSegment& src, BitmapSegment& dst) {
    parallel_for(dst.width, [&](int start, int end) {
        for (int x = start; x < end; x++) {
            for (int y = 0; y < dst.height; y++) {
                Vector3 v = correspondingSrcCoors(x, y, newOrigin, unitX, unitY, h) + PP;
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