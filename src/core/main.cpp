// Entry point: `grimoire <script.janet>` starts SDL and Janet and runs the
// script. Janet's module root is set to src/lib so `(import grimoire/x)` finds
// src/lib/grimoire/x.janet. Run from the repo root.

#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include "janet.h"

// Calls Janet's own dofile, rather than reading the file ourselves, so the
// script gets :current-file and its relative imports work.
static int grimoire_run_script(JanetTable *env, const char *path)
{
    Janet dofile;
    janet_resolve(env, janet_csymbol("dofile"), &dofile);
    Janet arg = janet_cstringv(path);
    JanetFiber *fiber = NULL;
    Janet out;
    JanetSignal sig = janet_pcall(janet_unwrap_function(dofile), 1, &arg, &out, &fiber);
    if (sig != JANET_SIGNAL_OK) {
        janet_stacktrace(fiber, out);
        return 1;
    }
    return 0;
}

int main(int argc, char *argv[])
{
    if (argc != 2) {
        SDL_Log("usage: grimoire <script.janet>");
        return 1;
    }
    if (!SDL_Init(0)) {
        SDL_Log("SDL_Init failed: %s", SDL_GetError());
        return 1;
    }
    janet_init();
    JanetTable *env = janet_core_env(NULL);
    janet_table_put(env, janet_ckeywordv("syspath"), janet_cstringv("src/lib"));

    int rc = grimoire_run_script(env, argv[1]);

    janet_deinit();
    SDL_Quit();
    return rc;
}
