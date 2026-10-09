#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <string>
#include <iostream>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <bit>
#include <cstdlib>

extern "C" {
#include "janet/janet.h"
}

#include "top.hpp"

static double run(bool reset, float gamma, float tau, int steps, bool verbose) {
    const size_t IN = 64, OUT = 8, K = 32;
    std::mt19937_64 rng(123);
    std::normal_distribution<float> nd(0.f, 1.f);
 
    TernaryOptimizer teacher(IN * OUT); teacher.init_random(7, 0.4f);
    TopConfig cfg; cfg.gamma = gamma; cfg.tau = tau; cfg.reset_on_move = reset;
    TernaryOptimizer student(IN * OUT, cfg); student.init_random(99, 1.f / 3.f);
 
    std::vector<float> x(K * IN), g(IN * OUT), ys(OUT), yt(OUT);
    for (int t = 0; t <= steps; ++t) {
        std::fill(g.begin(), g.end(), 0.f);
        double loss = 0;
        for (size_t k = 0; k < K; ++k) {
            for (size_t i = 0; i < IN; ++i) x[k * IN + i] = nd(rng);
            ternary_dense_forward(teacher.weights(), &x[k * IN], yt.data(), IN, OUT);
            ternary_dense_forward(student.weights(), &x[k * IN], ys.data(), IN, OUT);
            for (size_t j = 0; j < OUT; ++j) {
                float e = ys[j] - yt[j];
                loss += 0.5 * e * e;
                for (size_t i = 0; i < IN; ++i) g[j * IN + i] += e * x[k * IN + i] / K;
            }
        }
        size_t moved = student.step(g.data());
        if (verbose && t % 500 == 0) {
            size_t wrong = 0;
            for (size_t i = 0; i < IN * OUT; ++i) wrong += student.weights()[i] != teacher.weights()[i];
            std::printf("step %5d  loss %8.3f  wrong %3zu/%zu  moved %zu\n", t, loss / K, wrong, IN * OUT, moved);
        }
    }
    size_t wrong = 0;
    for (size_t i = 0; i < IN * OUT; ++i) wrong += student.weights()[i] != teacher.weights()[i];
    return (double)wrong / (IN * OUT);
}

int main()
{
    SDL_Log( "Hello, Merlin!\n" );

    // Initialize the Janet VM state and garbage collector
    janet_init();

    // Get the core environment table with built-in functions (+, print, def, etc.)
    JanetTable *env = janet_core_env(NULL);

    // Evaluate a Janet code string
    Janet result;
    const char *script = "(+ 10 20 30 40 50 60)";
    int status = janet_dostring(env, script, "main.janet", &result);

    if (status == 0) {
        // janet_description turns any Janet value into a readable C-string
        const uint8_t *output = janet_description(result);
        std::cout << "Janet returned: " << output << std::endl; // Output: 60
    } else {
        std::cerr << "Failed to evaluate script." << std::endl;
    }

    std::printf("--- reset_on_move = true ---\n");
    double a = run(true, 0.05f, 0.5f, 3000, true);
    std::printf("final wrong fraction: %.3f\n\n", a);
    std::printf("--- reset_on_move = false ---\n");
    double b = run(false, 0.05f, 0.5f, 3000, true);
    std::printf("final wrong fraction: %.3f\n", b);

    // Free VM resources
    janet_deinit();

    return 0;
}