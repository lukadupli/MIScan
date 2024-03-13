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
    jpge
    STATIC
    ../../native/jpge/jpge.cpp
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
    jpge
)