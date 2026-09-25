cmake_minimum_required(VERSION 3.15)
project(merlin VERSION 1.0 LANGUAGES CXX)

# Enforce a global C++ standard for all experiments
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED True)

# Generates compile_commands.json for VS Code intellisense
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

file(GLOB_RECURSE MERLIN_CPP_FILES
    ./src/*.hpp
    ./src/*.cpp
)

# Create the executable
add_executable(merlin
    ${MERLIN_CPP_FILES}
)

# Optional: Scope includes, compiler flags, or libraries specifically to this target
# target_include_directories(${TARGET_NAME} PRIVATE src)
# target_compile_options(${TARGET_NAME} PRIVATE -Wall -Wextra)
# target_link_libraries(${TARGET_NAME} PRIVATE pthread)