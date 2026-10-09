cmake_minimum_required(VERSION 3.15)
set(APP_TARGET merlin)
project(${APP_TARGET} VERSION 1.0 LANGUAGES C CXX)

# Enforce a global C++ standard for all experiments
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Generates compile_commands.json for VS Code intellisense
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Locate SDL3 package configuration
find_package(SDL3 REQUIRED CONFIG)
find_package(Threads REQUIRED)

file(GLOB_RECURSE MERLIN_CPP_FILES
    ./src/*.hpp
    ./src/*.cpp
    ./src/janet/*.h
    ./src/janet/*.c
)

# Create the executable
add_executable(${APP_TARGET}
    ${MERLIN_CPP_FILES}
)

# Target-scoped include directories
target_include_directories(${APP_TARGET} PRIVATE 
    src
    src/janet
)

# Linked required dependencies for Janet (-ldl, -lm, -pthread) and SDL3
target_link_libraries(${APP_TARGET} PRIVATE 
    SDL3::SDL3
    Threads::Threads
    ${CMAKE_DL_LIBS}
    m
)