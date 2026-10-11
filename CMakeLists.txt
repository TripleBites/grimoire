cmake_minimum_required(VERSION 3.15)
set(APP_TARGET merlin)
project(${APP_TARGET} VERSION 1.0 LANGUAGES C CXX)

# Enforce a global C++ standard for all experiments
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Generates compile_commands.json for VS Code intellisense
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Default to an optimized build (Release = -O3 on GCC/Clang).
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# Tune for the build machine. Off by default when cross-compiling,
# because "native" would then mean the build host, not the target.
if(CMAKE_CROSSCOMPILING)
  option(MERLINNATIVE "Tune for the build machine's CPU" OFF)
else()
  option(MERLINNATIVE "Tune for the build machine's CPU" ON)
endif()
option(MERLINAVX2 "x86 only: require AVX2 when MERLINNATIVE is off" ON)

include(CheckCXXCompilerFlag)

function(set_arch_flags target)
  string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" arch)
  set(flags "")

  if(MSVC)
    if(arch MATCHES "amd64|x86_64" AND MERLINAVX2)
      list(APPEND flags /arch:AVX2)          # also enables POPCNT codegen
    endif()

  elseif(arch MATCHES "x86_64|amd64")
    if(MERLINNATIVE)
      list(APPEND flags -march=native)
    else()
      list(APPEND flags -mpopcnt)            # minimum: real POPCNT instruction
      if(MERLINAVX2)
        list(APPEND flags -mavx2)
      endif()
    endif()

  elseif(arch MATCHES "aarch64|arm64")
    # NEON is part of the AArch64 baseline, so no flag is needed for it.
    if(MERLINNATIVE)
      list(APPEND flags -mcpu=native)
    endif()

  elseif(arch MATCHES "^arm")
    # 32-bit ARM: NEON is optional and must be requested.
    if(MERLINNATIVE)
      list(APPEND flags -mcpu=native)
    endif()
    list(APPEND flags -mfpu=neon)
  endif()

  # Only keep flags this compiler actually accepts.
  foreach(f ${flags})
    string(MAKE_C_IDENTIFIER "HAVE${f}" var)
    check_cxx_compiler_flag("${f}" ${var})
    if(${var})
      target_compile_options(${target} PRIVATE ${f})
    endif()
  endforeach()

  message(STATUS "merlin: arch=${arch} native=${MERLINNATIVE} flags=${flags}")
endfunction()


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

set_arch_flags(merlin)

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