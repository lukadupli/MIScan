#pragma once

extern "C"{
    bool JpgEncodeToFile(const char* filename, unsigned char* src, int src_width, int src_height, int src_channels);
}