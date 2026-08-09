cmake_minimum_required(VERSION 3.13)
project(miscan_native_tests CXX)

# Standalone from the Android build: these run on the host so the transform maths can be
# checked without a device. android/app/CMakeLists.txt still owns the shipped libraries.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(MSVC)
    add_compile_options(/W4)
else()
    add_compile_options(-Wall -Wextra)
endif()

set(NATIVE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/..)

add_executable(native_tests
    test_main.cpp
    quad_transform_test.cpp

    ${NATIVE_DIR}/basic_linear/helpers.cpp
    ${NATIVE_DIR}/basic_linear/line.cpp
    ${NATIVE_DIR}/basic_linear/plane.cpp
    ${NATIVE_DIR}/basic_linear/vector.cpp

    ${NATIVE_DIR}/transform/bitmap.cpp
    ${NATIVE_DIR}/transform/parallel_for.cpp
    ${NATIVE_DIR}/transform/quad_transform.cpp
    ${NATIVE_DIR}/transform/book_transform.cpp
)

find_package(Threads REQUIRED)
target_link_libraries(native_tests PRIVATE Threads::Threads)

enable_testing()
add_test(NAME native_tests COMMAND native_tests)
