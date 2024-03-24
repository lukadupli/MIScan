#include <functional>
#include <thread>
#include <algorithm>
#include <vector>
#include <cmath>

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
void parallel_for(unsigned nb_elements,
    std::function<void(int start, int end)> functor,
    bool use_threads = true)
{
    // -------
    unsigned nb_threads_hint = std::thread::hardware_concurrency();
    unsigned nb_threads = nb_threads_hint == 0 ? 8 : (nb_threads_hint);

    unsigned batch_size = nb_elements / nb_threads;
    unsigned batch_remainder = nb_elements % nb_threads;

    std::vector< std::thread > my_threads(nb_threads);

    if (use_threads)
    {
        // Multithread execution
        for (unsigned i = 0; i < nb_threads; ++i)
        {
            int start = i * batch_size;
            my_threads[i] = std::thread(functor, start, start + batch_size);
        }
    }
    else
    {
        // Single thread execution (for easy debugging)
        for (unsigned i = 0; i < nb_threads; ++i) {
            int start = i * batch_size;
            functor(start, start + batch_size);
        }
    }

    // Deform the elements left
    int start = nb_threads * batch_size;
    functor(start, start + batch_remainder);

    // Wait for the other thread to finish their task
    if (use_threads)
        std::for_each(my_threads.begin(), my_threads.end(), std::mem_fn(&std::thread::join));
}

#include "image_processing.h"
#include "../jpeg_compressor/jpgd.h"
#include "../jpeg_compressor/jpge.h"

int adjust(int value, double contrast, double brightness){
    value = std::round(contrast * ((double)value - 128) + 128 + brightness);
    if(value < 0) value = 0;
    if(value > 255) value = 255;
    return value;
}

extern "C"{
    void processImage(unsigned char* img, int width, int height, int channels, double contrast, double brightness){
        parallel_for(width, [&](int start, int end){
            for(int i = start; i < end; i++){
                for(int j = 0; j < height; j++){
                    for(int k = 0; k < channels; k++) 
                        img[i * height * channels + j * channels + k] = adjust(img[i * height * channels + j * channels + k], contrast, brightness);
                }
            }
        });
    }
    bool processJpg(const char* srcPath, const char* dstPath, double contrast, double brightness){
        int width, height, channels;
        auto img = jpgd::decompress_jpeg_image_from_file(srcPath, &width, &height, &channels, 3); // RGB

        processImage(img, width, height, channels, contrast, brightness);

        return jpge::compress_image_to_jpeg_file(dstPath, width, height, channels, img);
    }
}