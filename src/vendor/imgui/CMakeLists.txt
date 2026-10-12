# src/vendor/imgui/CMakeLists.txt
#
# Dear ImGui + SDL3 backends + optional add-ons, built as plain static/interface
# targets. Dear ImGui ships no CMake build of its own on purpose: it is a pile of
# .cpp files you compile into your program. This file is that "pile" declared
# as targets so the rest of the project can just `target_link_libraries(... imgui)`.
#
# Targets produced:
#   imgui                - core + imgui_stdlib + SDL3 platform backend + one renderer backend
#   imgui_memory_editor  - (optional) header-only hex/memory viewer from imgui_club
#   imnodes              - (optional) node-graph editor
#
# Requires: an SDL3::SDL3 target to exist before this directory is added.

include(FetchContent)

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
option(IMGUI_DOCKING            "Use the docking branch (dockable windows, multi-viewport)" ON)
option(IMGUI_WITH_MEMORY_EDITOR "Fetch imgui_club's memory editor"                         ON)
option(IMGUI_WITH_IMNODES       "Fetch imnodes (node graph editor)"                         ON)

# Which renderer backend to compile. Exactly one is needed alongside the SDL3
# platform backend.
#   sdlrenderer3 : SDL_Renderer (simplest; fine for tools/dashboards)
#   sdlgpu3      : SDL3 GPU API (Vulkan/Metal/D3D12 underneath)
#   opengl3      : OpenGL 3 / GLES 3
set(IMGUI_RENDERER "sdlrenderer3" CACHE STRING "ImGui renderer backend")
set_property(CACHE IMGUI_RENDERER PROPERTY STRINGS sdlrenderer3 sdlgpu3 opengl3)

if(NOT TARGET SDL3::SDL3)
    message(FATAL_ERROR "imgui: SDL3::SDL3 target not found. Add SDL3 before src/vendor/imgui.")
endif()

# ---------------------------------------------------------------------------
# Fetch sources
# ---------------------------------------------------------------------------
# Pin exact tags so a rebuild in six months produces the same thing.
# implot 1.0 and imnodes track recent ImGui, so bump these together.
if(IMGUI_DOCKING)
    set(_imgui_tag v1.92.9b-docking)
else()
    set(_imgui_tag v1.92.9b)
endif()

# SOURCE_SUBDIR points at a directory that doesn't exist. FetchContent_MakeAvailable
# then downloads the repo but does NOT add_subdirectory() it. Some of these repos
# carry their own CMakeLists that expect find_package(imgui) or vcpkg, which would
# fight with the targets we define here.
FetchContent_Declare(imgui_src
    GIT_REPOSITORY https://github.com/ocornut/imgui.git
    GIT_TAG        ${_imgui_tag}
    GIT_SHALLOW    TRUE
    SOURCE_SUBDIR  _no_cmake_)
FetchContent_MakeAvailable(imgui_src)
set(IMGUI_DIR ${imgui_src_SOURCE_DIR} CACHE INTERNAL "Dear ImGui source dir")

# ---------------------------------------------------------------------------
# imgui
# ---------------------------------------------------------------------------
add_library(imgui STATIC
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
    ${IMGUI_DIR}/imgui_demo.cpp                 # ImGui::ShowDemoWindow(); the best API reference
    ${IMGUI_DIR}/misc/cpp/imgui_stdlib.cpp      # InputText() overloads taking std::string
    ${IMGUI_DIR}/backends/imgui_impl_sdl3.cpp   # platform: SDL3 events/input/clipboard -> ImGui
)
add_library(imgui::imgui ALIAS imgui)

target_include_directories(imgui PUBLIC
    ${IMGUI_DIR}
    ${IMGUI_DIR}/backends
    ${IMGUI_DIR}/misc/cpp)

# PUBLIC: the backend headers include SDL headers, so consumers need SDL's
# include paths too.
target_link_libraries(imgui PUBLIC SDL3::SDL3)
target_compile_features(imgui PUBLIC cxx_std_11)

# Renderer backend
if(IMGUI_RENDERER STREQUAL "sdlrenderer3")
    target_sources(imgui PRIVATE ${IMGUI_DIR}/backends/imgui_impl_sdlrenderer3.cpp)
elseif(IMGUI_RENDERER STREQUAL "sdlgpu3")
    target_sources(imgui PRIVATE ${IMGUI_DIR}/backends/imgui_impl_sdlgpu3.cpp)
elseif(IMGUI_RENDERER STREQUAL "opengl3")
    find_package(OpenGL REQUIRED)
    target_sources(imgui PRIVATE ${IMGUI_DIR}/backends/imgui_impl_opengl3.cpp)
    target_link_libraries(imgui PUBLIC OpenGL::GL)
else()
    message(FATAL_ERROR "imgui: unknown IMGUI_RENDERER '${IMGUI_RENDERER}'")
endif()

# Project-wide ImGui config goes here rather than editing imconfig.h, so the
# fetched tree stays pristine. PUBLIC so every TU that includes imgui.h agrees;
# an ImGui compiled with different defines than its users is an ODR violation.
target_compile_definitions(imgui PUBLIC
    IMGUI_DISABLE_OBSOLETE_FUNCTIONS   # fail loudly on deprecated API instead of silently shimming
)

# ---------------------------------------------------------------------------
# imgui_memory_editor (header-only)
#   Hex view of any raw buffer. Point it at a weight tensor, an activation
#   buffer or a packed ternary array and watch bytes change during training.
# ---------------------------------------------------------------------------
if(IMGUI_WITH_MEMORY_EDITOR)
    FetchContent_Declare(imgui_club_src
        GIT_REPOSITORY https://github.com/ocornut/imgui_club.git
        GIT_TAG        b083116866e05e0d4bccb2c7f28d94a76ee4965e  # no release tags; pinned commit
        SOURCE_SUBDIR  _no_cmake_)
    FetchContent_MakeAvailable(imgui_club_src)

    add_library(imgui_memory_editor INTERFACE)
    target_include_directories(imgui_memory_editor INTERFACE
        ${imgui_club_src_SOURCE_DIR}/imgui_memory_editor)
    target_link_libraries(imgui_memory_editor INTERFACE imgui)
endif()

# ---------------------------------------------------------------------------
# imnodes
#   Node-graph editor: draw network architectures, module wiring, dataflow
#   pipelines; let the user connect pins with the mouse.
# ---------------------------------------------------------------------------
if(IMGUI_WITH_IMNODES)
    FetchContent_Declare(imnodes_src
        GIT_REPOSITORY https://github.com/Nelarius/imnodes.git
        # The last tag (v0.5, 2021) doesn't compile against ImGui 1.92's texture
        # API; master has the fix. Pinned commit from 2026-05-13.
        GIT_TAG        eb36902c892548ef94f88f51ad7e7c9c7058a71c
        SOURCE_SUBDIR  _no_cmake_)
    FetchContent_MakeAvailable(imnodes_src)

    add_library(imnodes STATIC ${imnodes_src_SOURCE_DIR}/imnodes.cpp)
    target_include_directories(imnodes PUBLIC ${imnodes_src_SOURCE_DIR})
    target_link_libraries(imnodes PUBLIC imgui)
endif()