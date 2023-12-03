#include "jpg_encode.h"
#include "../jpge/jpge.h"

extern "C"{
    bool JpgEncodeToFile(const char* filename, unsigned char* src, int src_width, int src_height, int src_channels){
        return jpge::compress_image_to_jpeg_file(filename, src_width, src_height, src_channels, src);
    }
}