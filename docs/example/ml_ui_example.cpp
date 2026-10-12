#include <SDL3/SDL.h>
#include "imgui.h"
#include "imgui_impl_sdl3.h"
#include "imgui_impl_sdlrenderer3.h"
#include "imgui_stdlib.h"
#include "implot.h"
#include "implot3d.h"
#include "imnodes.h"
#include "imgui_memory_editor.h"

#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

int main(int argc, char** argv)
{
    int frames = (argc > 1) ? std::atoi(argv[1]) : -1; // -1 = run until closed
    if (!SDL_Init(SDL_INIT_VIDEO)) { std::printf("SDL_Init: %s\n", SDL_GetError()); return 1; }
    SDL_Window* window = SDL_CreateWindow("vendor test", 1280, 800, 0);
    SDL_Renderer* renderer = SDL_CreateRenderer(window, nullptr);
    if (!window || !renderer) { std::printf("create: %s\n", SDL_GetError()); return 1; }

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImPlot::CreateContext();     // each add-on has its own context
    ImPlot3D::CreateContext();
    ImNodes::CreateContext();
    ImGui::GetIO().ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    ImGui_ImplSDL3_InitForSDLRenderer(window, renderer);
    ImGui_ImplSDLRenderer3_Init(renderer);

    // fake training data
    std::vector<float> step, loss, weights(4096);
    for (int i = 0; i < 500; ++i) { step.push_back((float)i); loss.push_back(2.3f * std::exp(-i / 120.0f) + 0.05f * std::sin(i * 0.3f)); }
    for (size_t i = 0; i < weights.size(); ++i) weights[i] = std::sin(i * 0.37f) * std::cos(i * 0.011f);
    std::vector<float> ex(300), ey(300), ez(300);
    for (int i = 0; i < 300; ++i) { float t = i * 0.1f; ex[i] = std::cos(t) * t; ey[i] = std::sin(t) * t; ez[i] = t; }
    std::string run_name = "ternary-mnist-01";
    static MemoryEditor mem_edit;

    bool running = true;
    for (int f = 0; running && f != frames; ++f) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) { ImGui_ImplSDL3_ProcessEvent(&e); if (e.type == SDL_EVENT_QUIT) running = false; }

        ImGui_ImplSDLRenderer3_NewFrame();
        ImGui_ImplSDL3_NewFrame();
        ImGui::NewFrame();

        ImGui::SetNextWindowPos(ImVec2(10, 10)); ImGui::SetNextWindowSize(ImVec2(620, 380));
        ImGui::Begin("Training");
        ImGui::InputText("run", &run_name);            // std::string overload from imgui_stdlib
        if (ImPlot::BeginPlot("Loss")) {
            ImPlot::SetupAxes("step", "loss");
            ImPlot::PlotLine("train", step.data(), loss.data(), (int)step.size());
            ImPlot::EndPlot();
        }
        ImGui::End();

        ImGui::SetNextWindowPos(ImVec2(640, 10)); ImGui::SetNextWindowSize(ImVec2(620, 380));
        ImGui::Begin("Weights");
        // Diverging colormap: red = negative, white = 0, blue = positive.
        // The default map is categorical and makes signed data look like noise.
        ImPlot::PushColormap(ImPlotColormap_RdBu);
        if (ImPlot::BeginPlot("W[64x64]", ImVec2(-80, -1))) {
            ImPlot::PlotHeatmap("w", weights.data(), 64, 64, -1.0, 1.0, nullptr);
            ImPlot::EndPlot();
        }
        ImGui::SameLine();
        ImPlot::ColormapScale("##scale", -1.0, 1.0, ImVec2(70, -1));
        ImPlot::PopColormap();
        ImGui::End();

        ImGui::SetNextWindowPos(ImVec2(10, 400)); ImGui::SetNextWindowSize(ImVec2(400, 390));
        ImGui::Begin("Embeddings");
        if (ImPlot3D::BeginPlot("emb", ImVec2(-1, -1))) {
            ImPlot3D::PlotScatter("pts", ex.data(), ey.data(), ez.data(), (int)ex.size());
            ImPlot3D::EndPlot();
        }
        ImGui::End();

        ImGui::SetNextWindowPos(ImVec2(420, 400)); ImGui::SetNextWindowSize(ImVec2(400, 390));
        ImGui::Begin("Architecture");
        ImNodes::BeginNodeEditor();
        ImNodes::BeginNode(1); ImNodes::BeginNodeTitleBar(); ImGui::TextUnformatted("input 784"); ImNodes::EndNodeTitleBar();
        ImNodes::BeginOutputAttribute(2); ImGui::Text("x"); ImNodes::EndOutputAttribute(); ImNodes::EndNode();
        ImNodes::BeginNode(3); ImNodes::BeginNodeTitleBar(); ImGui::TextUnformatted("ternary 256"); ImNodes::EndNodeTitleBar();
        ImNodes::BeginInputAttribute(4); ImGui::Text("in"); ImNodes::EndInputAttribute(); ImNodes::EndNode();
        if (f == 0) ImNodes::SetNodeGridSpacePos(3, ImVec2(180, 80));
        ImNodes::Link(5, 2, 4);
        ImNodes::EndNodeEditor();
        ImGui::End();

        ImGui::SetNextWindowPos(ImVec2(830, 400)); ImGui::SetNextWindowSize(ImVec2(440, 390));
        mem_edit.DrawWindow("Raw weights", weights.data(), weights.size() * sizeof(float));

        ImGui::Render();
        SDL_SetRenderDrawColor(renderer, 20, 20, 24, 255);
        SDL_RenderClear(renderer);
        ImGui_ImplSDLRenderer3_RenderDrawData(ImGui::GetDrawData(), renderer);

        if (f == frames - 1) { // headless test: dump last frame
            SDL_Surface* s = SDL_RenderReadPixels(renderer, nullptr);
            if (s) { SDL_SaveBMP(s, "frame.bmp"); SDL_DestroySurface(s); }
        }
        SDL_RenderPresent(renderer);
    }

    ImGui_ImplSDLRenderer3_Shutdown();
    ImGui_ImplSDL3_Shutdown();
    ImNodes::DestroyContext();
    ImPlot3D::DestroyContext();
    ImPlot::DestroyContext();
    ImGui::DestroyContext();
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    std::printf("ok\n");
    return 0;
}
