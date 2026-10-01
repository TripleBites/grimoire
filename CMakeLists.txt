cmake_minimum_required(VERSION 3.15)
set(APP_TARGET merlin)
project(APP_TARGET VERSION 1.0 LANGUAGES CXX)

# Enforce a global C++ standard for all experiments
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED True)

# Generates compile_commands.json for VS Code intellisense
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Locate SDL3 package configuration
find_package(SDL3 REQUIRED CONFIG)

file(GLOB_RECURSE MERLIN_CPP_FILES
    ./src/*.hpp
    ./src/*.cpp
)

# Create the executable
add_executable(APP_TARGET
    ${MERLIN_CPP_FILES}
)

target_link_libraries(APP_TARGET PRIVATE SDL3::SDL3)

# Optional: Scope includes, compiler flags, or libraries specifically to this target
# target_include_directories(${TARGET_NAME} PRIVATE src)
# target_compile_options(${TARGET_NAME} PRIVATE -Wall -Wextra)
# target_link_libraries(${TARGET_NAME} PRIVATE pthread)