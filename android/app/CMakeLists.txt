cmake_minimum_required(VERSION 3.4.1)  

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
    jpge
    STATIC
    ../../native/jpge/jpge.cpp
)
add_library( 
    straighten
    SHARED
    ../../native/straighten/straighten.cpp
)
add_library(
    jpg_encode
    SHARED
    ../../native/jpg_encode/jpg_encode.cpp
)

target_link_libraries(
    straighten
    basic_linear
)
target_link_libraries(
    jpg_encode
    jpge
)