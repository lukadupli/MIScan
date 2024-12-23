cmake_minimum_required(VERSION 3.4.1)  
project(MIScan)

set(CMAKE_CXX_FLAGS "-Wall -Wextra -O3")

add_library(
    basic_linear
    STATIC
    ../../native/basic_linear/helpers.cpp
    ../../native/basic_linear/line.cpp
    ../../native/basic_linear/plane.cpp
    ../../native/basic_linear/vector.cpp
)
add_library(
    transform
    STATIC
    ../../native/transform/bitmap.cpp
    ../../native/transform/parallel_for.cpp
    ../../native/transform/quad_transform.cpp
    ../../native/transform/book_transform.cpp
)
add_library(
    jpeg_compressor
    STATIC
    ../../native/jpeg_compressor/jpgd.cpp
    ../../native/jpeg_compressor/jpge.cpp
)
add_library( 
    straighten
    SHARED
    ../../native/straighten/exports.cpp
)
add_library(
    jpg_encode
    SHARED
    ../../native/jpg_encode/jpg_encode.cpp
)
add_library(
    image_processing
    SHARED
    ../../native/image_processing/image_processing.cpp
)

target_link_libraries(
    transform
    basic_linear
)
target_link_libraries(
    straighten
    transform
)
target_link_libraries(
    jpg_encode
    jpeg_compressor
)
target_link_libraries(
    image_processing
    jpeg_compressor
)