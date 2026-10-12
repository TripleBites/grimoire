cmake_minimum_required(VERSION 3.15)
project(grimoire LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)   # for editor tooling

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

find_package(SDL3 REQUIRED CONFIG)
find_package(Threads REQUIRED)

add_subdirectory(src/vendor/imgui)
add_subdirectory(src/vendor/implot)

# Janet is its own target so our warning flags don't apply to vendored code.
add_library(janet STATIC src/vendor/janet/janet.c)
target_include_directories(janet PUBLIC src/vendor/janet)
target_link_libraries(janet PUBLIC Threads::Threads ${CMAKE_DL_LIBS})
if(UNIX)
  target_link_libraries(janet PUBLIC m)
endif()

add_executable(grimoire
  src/core/main.cpp
)
target_include_directories(grimoire PRIVATE src/core)
target_compile_options(grimoire PRIVATE -Wall -Wextra)
target_link_libraries(grimoire PRIVATE
  janet
  SDL3::SDL3
  imgui
)

# Without a native target, __builtin_popcountll compiles to a slow bit trick
# instead of the POPCNT instruction, and Trits::dot is the hot loop.
include(CheckCXXCompilerFlag)
check_cxx_compiler_flag(-march=native GRIMOIRE_HAS_MARCH_NATIVE)
if(GRIMOIRE_HAS_MARCH_NATIVE AND NOT CMAKE_CROSSCOMPILING)
  target_compile_options(grimoire PRIVATE -march=native)
endif()
