cmake_minimum_required(VERSION 3.4.1)  
 
add_library(
    basic_linear
    STATIC
    ../../native/basic_linear/helpers.cpp
    ../../native/basic_linear/line.cpp
    ../../native/basic_linear/plane.cpp
    ../../native/basic_linear/vector.cpp
)
add_library( 
            straighten
            SHARED
            ../../native/straighten/straighten.cpp
)

target_link_libraries(
    straighten
    basic_linear
)