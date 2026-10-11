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

#include "tnn.hpp"

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

    // Free VM resources
    janet_deinit();

    return 0;
}