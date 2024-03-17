#include "book_transform.h"

#include <cmath>

bool BookTransform::canTransform(Point2D p1, Point2D p2, Point2D p3, Point2D p4) {
    return quad.canTransform(p1, p2, p3, p4);
}

bool BookTransform::loadCoordinates(Point2D p1, Point2D p2, Point2D p3, Point2D p4, const std::vector<Point2D> curve, bool curvePosition) {
    if (!quad.loadCoordinates(p1, p2, p3, p4)) return false;

    Plane fplane = quad.floorPlane();
    Vector3 floorOrigin = quad.floorPlaneOrigin();
    Vector3 unitX = quad.floorPlaneUnitX();
    Vector3 unitY = quad.floorPlaneUnitY();
    Vector3 unitZ = Cross(unitX, unitY);
    double h = quad.cameraHeight();

    Plane perpPlane; // plane perpendicular to floor plane passing through edge selected by curvePosition
    perpPlane.v = unitY;
    if (!curvePosition) {
        perpPlane.b = perpPlane.v * floorOrigin;
    }
    else {
        Vector3 D = Vector3{ p4.x, p4.y, 0 } - quad.referentOrigin();
        Vector3 floorD = QuadTransform::putOnFloor(D, fplane, h);
        perpPlane.b = perpPlane.v * floorD;
    }

    std::vector<std::pair<double, double>> xzPairs; // (x, z) pairs for points on floor plane
    for (auto& point : curve) {
        Vector3 pnt = Vector3{ point.x, point.y, 0 } - quad.referentOrigin();

        Vector3 proj = perpPlane.Intersection(Line{ Vector3{0, 0, h}, pnt }) - floorOrigin; // coordinates relative to floor plane
        double x = proj * unitX;
        double z = proj * unitZ;

        xzPairs.push_back({ x, z });
    }
    xzPairs.push_back({quad.newWidth(), 0});
    std::sort(xzPairs.begin(), xzPairs.end());

    // Code below assumes (quad.newWidth(), 0) is in xzPairs

    newh = quad.newHeight();
    double length = 0;
    xzValues.clear();
    for (int i = 0; i < xzPairs.size() - 1; i++) {
        double x1 = xzPairs[i].first, z1 = xzPairs[i].second;
        double x2 = xzPairs[i + 1].first, z2 = xzPairs[i + 1].second;

        // how many curve length is between (x1, z1) and (x2, z2)
        double increment = sqrt((x2 - x1) * (x2 - x1) + (z2 - z1) * (z2 - z1));

        // filling up xzValues for integer values of length
        while ((double)xzValues.size() <= length + increment) {
            double l = (double)xzValues.size() - length;
            double deltaX = l * (x2 - x1) / increment;
            double deltaZ = l * (z2 - z1) / increment;

            xzValues.push_back({ x1 + deltaX, z1 + deltaZ });
        }
        length += increment;
    }
    neww = xzValues.size();
    return true;
}

int BookTransform::newWidth() { return neww; }
int BookTransform::newHeight() { return newh; }

void BookTransform::process(BitmapSegment& src, BitmapSegment& dst) {
    Vector3 floorOrigin = quad.floorPlaneOrigin();
    Vector3 unitX = quad.floorPlaneUnitX();
    Vector3 unitY = quad.floorPlaneUnitY();
    Vector3 unitZ = Cross(unitX, unitY);

    parallel_for(dst.width, [&](int start, int end) {
        for (int x = start; x < end; x++) {
            double modelX = xzValues[x].first;
            double modelZ = xzValues[x].second;
            for (int y = 0; y < dst.height; y++) {
                Vector3 globalPosition = modelX * unitX + y * unitY + modelZ * unitZ + floorOrigin;
                Line lightRay = Line{ globalPosition, Vector3{0, 0, quad.cameraHeight() } };

                // lightRay.dir.z is never 0
                Vector3 sourceCoors = lightRay.base - (lightRay.base.z / lightRay.dir.z) * lightRay.dir; // intersection with xy plane
                sourceCoors = sourceCoors + quad.referentOrigin(); // (0, 0) is now not diagonal intersection, but upper-left corner of src

                int srcX = sourceCoors.x, srcY = sourceCoors.y;
                for (int z = 0; z < dst.bitmap.channels; z++) {
                    if (src.inRange(srcX, srcY, z)) dst(x, y, z) = src(srcX, srcY, z);
                    else dst(x, y, z) = 0;
                }
            }
        }
        }
    );
}