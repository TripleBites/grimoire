# src/vendor/implot/CMakeLists.txt
#
# ImPlot (2D plotting) and optionally ImPlot3D, built against the `imgui`
# target from src/vendor/imgui. Add that directory first.
#
# Targets produced:
#   implot    - line/scatter/heatmap/histogram/bar plots, real-time scrolling plots
#   implot3d  - (optional) 3D scatter/surface/mesh plots

include(FetchContent)

option(IMPLOT_WITH_IMPLOT3D "Fetch ImPlot3D (3D plots)" ON)

if(NOT TARGET imgui)
    message(FATAL_ERROR "implot: 'imgui' target not found. add_subdirectory(src/vendor/imgui) first.")
endif()

# ---------------------------------------------------------------------------
# implot
#   Loss/accuracy curves, learning-rate schedules, weight/gradient histograms,
#   confusion matrices and weight matrices as heatmaps, embedding scatter plots.
# ---------------------------------------------------------------------------
FetchContent_Declare(implot_src
    GIT_REPOSITORY https://github.com/epezent/implot.git
    # v1.0 (2026-04) predates ImGui 1.92.8's ImDrawList::AddRect/AddPolyline
    # argument reorder and fails to build with IMGUI_DISABLE_OBSOLETE_FUNCTIONS.
    # Pinned master commit (2026-10-10) has the fix; move to v1.1 when tagged.
    GIT_TAG        851cdbdd60d1dfb64c23e987969694de0f547a6b
    SOURCE_SUBDIR  _no_cmake_)   # download only; we define the target ourselves
FetchContent_MakeAvailable(implot_src)

add_library(implot STATIC
    ${implot_src_SOURCE_DIR}/implot.cpp
    ${implot_src_SOURCE_DIR}/implot_items.cpp
    ${implot_src_SOURCE_DIR}/implot_demo.cpp)   # ImPlot::ShowDemoWindow()
add_library(implot::implot ALIAS implot)

target_include_directories(implot PUBLIC ${implot_src_SOURCE_DIR})
target_link_libraries(implot PUBLIC imgui)

# ---------------------------------------------------------------------------
# implot3d
#   3D scatter of embeddings (PCA/t-SNE to 3 dims), loss surfaces over two
#   parameters, state-space trajectories.
# ---------------------------------------------------------------------------
if(IMPLOT_WITH_IMPLOT3D)
    FetchContent_Declare(implot3d_src
        GIT_REPOSITORY https://github.com/brenocq/implot3d.git
        GIT_TAG        v0.4
        GIT_SHALLOW    TRUE
        SOURCE_SUBDIR  _no_cmake_)
    FetchContent_MakeAvailable(implot3d_src)

    add_library(implot3d STATIC
        ${implot3d_src_SOURCE_DIR}/implot3d.cpp
        ${implot3d_src_SOURCE_DIR}/implot3d_items.cpp
        ${implot3d_src_SOURCE_DIR}/implot3d_meshes.cpp
        ${implot3d_src_SOURCE_DIR}/implot3d_demo.cpp)
    add_library(implot::implot3d ALIAS implot3d)

    target_include_directories(implot3d PUBLIC ${implot3d_src_SOURCE_DIR})
    target_link_libraries(implot3d PUBLIC imgui)
endif()