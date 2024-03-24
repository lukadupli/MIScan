extern "C"{
    void processImage(unsigned char* img, int width, int height, int channels, double contrast, double brightness);
    bool processJpg(const char* srcPath, const char* dstPath, double contrast, double brightness);
}