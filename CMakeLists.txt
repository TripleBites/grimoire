cmake_minimum_required(VERSION 3.15)
project(merlin LANGUAGES CXX)

# Require C++20
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)

# Create the executable from main.cpp
add_executable(merlin src/merlin.cpp)
