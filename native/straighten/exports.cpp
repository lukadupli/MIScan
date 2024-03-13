#include "exports.h"

#include "../transform/quad_transform.h"
#include "../transform/book_transform.h"

bool input4, output4;
int neww, newh;
QuadTransform engine;
BookTransform bookEngine;

extern "C" {
    API void Prepare(bool input_padded, bool output_padded){
        input4 = input_padded;
        output4 = output_padded;
    }

    API bool CanTransform(double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3) {
        return engine.canTransform({ x0, y0 }, { x1, y1 }, { x2, y2 }, { x3, y3 });
    }

    API bool BookCanTransform(double* cornerXs, double* cornerYs, int curveLength, double* curveXs, double* curveYs, bool curvePos) {
        return bookEngine.canTransform({ cornerXs[0], cornerYs[0] }, { cornerXs[1], cornerYs[1] }, { cornerXs[2], cornerYs[2] }, {cornerXs[3], cornerYs[3]});
    }
    
    API bool LoadCoordinates(double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3) {
        bool ret = engine.loadCoordinates({ x0, y0 }, { x1, y1 }, { x2, y2 }, { x3, y3 });
        neww = engine.newWidth();
        newh = engine.newHeight();
        return ret;
    }
    API bool BookLoadCoordinates(double* cornerXs, double* cornerYs, int curveLength, double* curveXs, double* curveYs, bool curvePos) {
        std::vector<Point2D> curveV;
        for (int i = 0; i < curveLength; i++) curveV.push_back({ curveXs[i], curveYs[i] });
        bool ret = bookEngine.loadCoordinates(
            { cornerXs[0], cornerYs[0] }, { cornerXs[1], cornerYs[1] }, { cornerXs[2], cornerYs[2] }, { cornerXs[3], cornerYs[3] },
            curveV,
            curvePos
        );
        neww = bookEngine.newWidth();
        newh = bookEngine.newHeight();
        return ret;
    }

    API int GetWidth() {
        return neww;
    }

    API int GetHeight() {
        return newh;
    }

    API int GetRequiredDstSize(int bytes_per_pixel) {
        int stride = neww * bytes_per_pixel;
        if(stride % 4 && output4) stride += 4 - (stride % 4);

        return stride * newh;
    }

    API void Process(unsigned char* src, int src_width, int src_height, int src_chan, unsigned char* dst) {
        Bitmap srcbmp{ src, src_width, src_height, src_chan, input4 };
        Bitmap dstbmp{ dst, neww, newh, src_chan, output4};

        BitmapSegment srcseg{ srcbmp, 0, 0, srcbmp.width, srcbmp.height };
        BitmapSegment dstseg{ dstbmp, 0, 0, dstbmp.width, dstbmp.height };

        engine.process(srcseg, dstseg);
	}
    API void BookProcess(unsigned char* src, int src_width, int src_height, int src_chan, unsigned char* dst) {
        Bitmap srcbmp{ src, src_width, src_height, src_chan, input4 };
        Bitmap dstbmp{ dst, neww, newh, src_chan, output4 };

        BitmapSegment srcseg{ srcbmp, 0, 0, srcbmp.width, srcbmp.height };
        BitmapSegment dstseg{ dstbmp, 0, 0, dstbmp.width, dstbmp.height };

        bookEngine.process(srcseg, dstseg);
    }
}
