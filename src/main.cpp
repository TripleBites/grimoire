#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <string>
#include <iostream>
#include <cstdint>
#include <vector>
#include <bit>
#include <cstdlib>

class Display {
public:
    int screen_width{ 640 };
    int screen_height{ 480 };
    SDL_Window* window{ nullptr };
    SDL_Surface* screen_surface{ nullptr };

    bool init()
    {
        //Initialization flag
        bool success{ true };

        //Initialize SDL
        if( SDL_Init( SDL_INIT_VIDEO ) == false )
        {
            SDL_Log( "SDL could not initialize! SDL error: %s\n", SDL_GetError() );
            success = false;
        }
        else
        {
            //Create window
            if( window = SDL_CreateWindow( "SDL3 Tutorial: Hello SDL3", screen_width, screen_height, 0 ); window == nullptr )
            {
                SDL_Log( "Window could not be created! SDL error: %s\n", SDL_GetError() );
                success = false;
            }
            else
            {
                //Get window surface
                screen_surface = SDL_GetWindowSurface( window );
            }
        }

        return success;
    }

    void close()
    {

    }
};

int main() {
    int exit_code{ 0 };
    Display* display = new Display();
    if( display->init() == false )
    {
        SDL_Log( "Unable to initialize program!\n" );
        exit_code = 1;
    }
    SDL_Log( "Hello, Merlin!\n" );
    display->close();

    return 0;
}