#include "straighten.h"

#include "../basic_linear/helpers.h"
#include "../basic_linear/line.h"
#include "../basic_linear/plane.h"
#include "../basic_linear/vector.h"

#include <assert.h>
#include <cmath>

#include <algorithm>
#include <thread>
#include <functional>
#include <vector>

/// @param[in] nb_elements : size of your for loop
/// @param[in] functor(start, end) :
/// your function processing a sub chunk of the for loop.
/// "start" is the first index to process (included) until the index "end"
/// (excluded)
/// @code
///     for(int i = start; i < end; ++i)
///         computation(i);
/// @endcode
/// @param use_threads : enable / disable threads.
///
///
static
void parallel_for(unsigned nb_elements,
                  std::function<void (int start, int end)> functor,
                  bool use_threads = true)
{
    // -------
    unsigned nb_threads_hint = std::thread::hardware_concurrency();
    unsigned nb_threads = nb_threads_hint == 0 ? 8 : (nb_threads_hint);

    unsigned batch_size = nb_elements / nb_threads;
    unsigned batch_remainder = nb_elements % nb_threads;

    std::vector< std::thread > my_threads(nb_threads);

    if( use_threads )
    {
        // Multithread execution
        for(unsigned i = 0; i < nb_threads; ++i)
        {
            int start = i * batch_size;
            my_threads[i] = std::thread(functor, start, start+batch_size);
        }
    }
    else
    {
        // Single thread execution (for easy debugging)
        for(unsigned i = 0; i < nb_threads; ++i){
            int start = i * batch_size;
            functor( start, start+batch_size );
        }
    }

    // Deform the elements left
    int start = nb_threads * batch_size;
    functor( start, start+batch_remainder);

    // Wait for the other thread to finish their task
    if( use_threads )
        std::for_each(my_threads.begin(), my_threads.end(), std::mem_fn(&std::thread::join));
}

struct Bitmap {
	unsigned int stride, width, height, channels;
	unsigned char* data;

	Bitmap(unsigned char* data, unsigned int width, unsigned int height, unsigned int channels, bool stride4) : width(width), height(height), channels(channels), data(data) {
        stride = width * channels;
        if (stride4 && stride % 4) stride += 4 - (stride % 4);
    }
    bool in_range(unsigned int x, unsigned int y, unsigned int channel) {
        return x < width && y < height && channel < channels;
    }
	unsigned char& operator()(unsigned int x, unsigned int y, unsigned int channel) {
		return data[y * stride + x * channels + channel];
	}
};

Vector3 S, newOrigin, unitX, unitY;
double h;
unsigned int neww, newh;

Vector3 PutOnFloor(const Vector3& point, const Plane& fplane, double height) {
    Line l{ {0., 0., height}, point };

    if (eq(fplane.v * l.dir, 0.)) return point;
    return fplane.Intersection(l);
}

// transformation of floor (x, y) coordinates to source (x, y, 0) coordinates based on fplane origin and fplane unit vectors 
Vector3 CorrespondingSrcCoors(unsigned int floorx, unsigned int floory, const Vector3& origin, const Vector3& unitx, const Vector3& unity, double height) {
    Vector3 real = floorx * unitx + floory * unity + origin;
    Line l{ {0., 0., height}, real };

    // edge case when paper on picture is already on the right plane
    if (eq(l.dir.z, 0.)) {
        assert(eq(real.z, 0.));
        return real;
    }

    // intersection with picture xy plane
    return l.base - (l.base.z / l.dir.z) * l.dir;
}

extern "C" {
    bool CanTransform(double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3){
        Vector3 A{ x0, y0, 0. };
        Vector3 B{ x1, y1, 0. };
        Vector3 C{ x2, y2, 0. };
        Vector3 D{ x3, y3, 0. };

        S = Intersection(Line(A, C), Line(B, D));
        A = A - S; B = B - S; C = C - S; D = D - S;

        double a = A.Abs(), b = B.Abs(), c = C.Abs(), d = D.Abs();

        // the points already form a rectangle
        if(eq(a, c) && eq(b, d) && eq(a, b)) return true;

        return !(eq(a * b, c * d) || eq(b * c, a * d));
    }
    
    bool LoadCornerCoordinates(double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3)
    {
        Vector3 A{ x0, y0, 0. };
        Vector3 B{ x1, y1, 0. };
        Vector3 C{ x2, y2, 0. };
        Vector3 D{ x3, y3, 0. };

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
            h = 0.;
            
            newOrigin = A;
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
        d1.base = Vector3{ 0., 0., 0. };
        d1.dir.z = pitch1; // dir is unit vector
        d1.dir = d1.dir.Unit();

        double pitch2 = sqrt(abs(sq((b + d) * l / (2 * b * d)) - 1));
        if (b > d) pitch2 = -pitch2;

        Line d2{ B, D };
        d2.base = Vector3{ 0., 0., 0. };
        d2.dir.z = pitch2; // dir is unit vector
        d2.dir = d2.dir.Unit();

        // plane of the floor
        Plane fplane{ d1, d2 };

        // height of the observer
        h = sqrt(abs(sq((a + c) * l / (2 * a * c)) - 1)) * 2 * a * c / abs(a - c);

        Vector3 A2 = PutOnFloor(A, fplane, h), B2 = PutOnFloor(B, fplane, h), D2 = PutOnFloor(D, fplane, h);

        Vector3 yedge = B2 - A2, xedge = D2 - A2;

        newOrigin = A2;
        unitX = xedge.Unit(); unitY = yedge.Unit();

        neww = xedge.Abs(); newh = yedge.Abs();

        return true;
    }

    unsigned int GetWidth() {
        return neww;
    }
    unsigned int GetHeight() {
        return newh;
    }

	void ProcessBitmapData(unsigned char* src, unsigned int src_width, unsigned int src_height, unsigned int src_chan, unsigned char* dst, bool assure_stride_is_divisible_by_4) {
        Bitmap srcbmp{ src, src_width, src_height, src_chan, assure_stride_is_divisible_by_4 };
        Bitmap dstbmp{ dst, neww, newh, src_chan, assure_stride_is_divisible_by_4 };
        
        parallel_for(dstbmp.width, [&](int start, int end){
            for(int x = start; x < end; x++){
                for (int y = 0; y < dstbmp.height; y++) {
                    Vector3 v = CorrespondingSrcCoors(x, y, newOrigin, unitX, unitY, h) + S;
                    for (int z = 0; z < src_chan; z++) {
                        if (srcbmp.in_range((unsigned int)v.x, (unsigned int)v.y, z)) dstbmp(x, y, z) = srcbmp((unsigned int)v.x, (unsigned int)v.y, z);
                        else dstbmp(x, y, z) = 0;
                    }
                }
		}
        });
	}
}
