/* SPDX-License-Identifier: GPL-3.0-or-later
 * Stage 14A: Nintendo Switch homebrew hardware probe for the Silent Hill port.
 * No gameplay, ROM, engine or PsyCross sources are compiled into this probe.
 */
#include <switch.h>
#include <SDL.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#define SH_WIDTH 1280
#define SH_HEIGHT 720
#define SH_LOG_PATH "sdmc:/switch/SilentHillSwitch/probe.log"
#define SH_DISC_PATH "sdmc:/switch/SilentHillSwitch/gamedata/Silent Hill (USA).bin"

static FILE* g_log;

static void record(const char* message)
{
    if (g_log != NULL)
    {
        fprintf(g_log, "%s\n", message);
        fflush(g_log);
    }
    SDL_Log("[SH-Switch] %s", message);
}

static void draw_bar(SDL_Renderer* renderer, int index, int passed, int available)
{
    SDL_Rect bar = { 80, 280 + index * 75, 1120, 48 };
    if (!available)
        SDL_SetRenderDrawColor(renderer, 65, 65, 65, 255);
    else if (passed)
        SDL_SetRenderDrawColor(renderer, 70, 180, 125, 255);
    else
        SDL_SetRenderDrawColor(renderer, 186, 92, 70, 255);
    SDL_RenderFillRect(renderer, &bar);
}

static void tone(SDL_AudioDeviceID audio)
{
    int16_t samples[4800 * 2]; /* 100 ms stereo at 48 kHz. */
    unsigned int i;
    if (audio == 0)
        return;
    for (i = 0; i < 4800; ++i)
    {
        int16_t value = (int16_t)(((i / 55u) % 2u) ? 3500 : -3500);
        samples[i * 2u] = value;
        samples[i * 2u + 1u] = value;
    }
    (void)SDL_QueueAudio(audio, samples, (Uint32)sizeof(samples));
}

int main(int argc, char** argv)
{
    SDL_Window* window = NULL;
    SDL_Renderer* renderer = NULL;
    SDL_Joystick* joystick = NULL;
    SDL_AudioDeviceID audio = 0;
    SDL_AudioSpec wanted;
    SDL_AudioSpec obtained;
    int sd_ok = 0;
    int input_ok = 0;
    int audio_ok = 0;
    int disc_present = 0;
    int running = 1;
    int alternate = 0;
    unsigned int frames = 0;
    FILE* disc;
    (void)argc;
    (void)argv;

    sd_ok = R_SUCCEEDED(fsdevMountSdmc());
    if (sd_ok)
    {
        (void)mkdir("sdmc:/switch", 0777);
        (void)mkdir("sdmc:/switch/SilentHillSwitch", 0777);
        g_log = fopen(SH_LOG_PATH, "w");
    }
    record("Silent Hill Switch Stage 14A — hardware preflight, NOT the game");
    record(sd_ok ? "SD: mounted" : "SD: mount failed");

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK) != 0)
    {
        record("SDL_Init(VIDEO/JOYSTICK) failed");
        goto cleanup;
    }
    window = SDL_CreateWindow("SH Switch Hardware Probe", 0, 0,
        SH_WIDTH, SH_HEIGHT, SDL_WINDOW_SHOWN);
    if (window == NULL)
    {
        record("SDL_CreateWindow failed");
        goto cleanup;
    }
    renderer = SDL_CreateRenderer(window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (renderer == NULL)
    {
        record("SDL_CreateRenderer (EGL/GLES2) failed");
        goto cleanup;
    }
    record("Video: SDL2 renderer created (Mesa/EGL backend)");

    if (SDL_NumJoysticks() > 0)
    {
        joystick = SDL_JoystickOpen(0);
        input_ok = joystick != NULL;
    }
    record(input_ok ? "Input: joystick 0 opened" : "Input: no usable joystick");

    if (SDL_InitSubSystem(SDL_INIT_AUDIO) == 0)
    {
        memset(&wanted, 0, sizeof(wanted));
        wanted.freq = 48000;
        wanted.format = AUDIO_S16SYS;
        wanted.channels = 2;
        wanted.samples = 1024;
        wanted.callback = NULL;
        audio = SDL_OpenAudioDevice(NULL, 0, &wanted, &obtained, 0);
        audio_ok = (audio != 0 && obtained.format == AUDIO_S16SYS &&
            obtained.channels == 2 && obtained.freq == 48000);
        if (audio != 0)
            SDL_PauseAudioDevice(audio, 0);
    }
    record(audio_ok ? "Audio: SDL2 48 kHz S16 stereo ready" :
        "Audio: unavailable or negotiated another format");

    disc = sd_ok ? fopen(SH_DISC_PATH, "rb") : NULL;
    if (disc != NULL)
    {
        disc_present = 1;
        fclose(disc);
    }
    record(disc_present ? "Game disc: supplied image visible (NOT loaded)" :
        "Game disc: optional image not present");
    record("Controls: A = toggle palette and sound; PLUS = exit");

    while (running && appletMainLoop())
    {
        SDL_Event event;
        SDL_Rect main_panel = { 80, 70, 1120, 170 };
        while (SDL_PollEvent(&event))
        {
            if (event.type == SDL_QUIT)
                running = 0;
            else if (event.type == SDL_JOYBUTTONDOWN && joystick != NULL &&
                     event.jbutton.which == SDL_JoystickInstanceID(joystick))
            {
                if (event.jbutton.button == 0)
                {
                    alternate = !alternate;
                    if (audio_ok)
                        tone(audio);
                }
                else if (event.jbutton.button == 10)
                    running = 0;
            }
        }
        SDL_SetRenderDrawColor(renderer, alternate ? 24 : 14,
            alternate ? 42 : 19, alternate ? 47 : 31, 255);
        SDL_RenderClear(renderer);
        SDL_SetRenderDrawColor(renderer, alternate ? 136 : 79,
            alternate ? 141 : 92, alternate ? 168 : 119, 255);
        SDL_RenderFillRect(renderer, &main_panel);
        draw_bar(renderer, 0, 1, 1);              /* Video */
        draw_bar(renderer, 1, input_ok, 1);       /* Controller */
        draw_bar(renderer, 2, audio_ok, 1);       /* Audio */
        draw_bar(renderer, 3, sd_ok, 1);          /* SD card */
        draw_bar(renderer, 4, disc_present, 0);   /* Optional disc */
        SDL_RenderPresent(renderer);
        frames++;
    }
    record("Main loop exited normally");

cleanup:
    if (audio != 0)
        SDL_CloseAudioDevice(audio);
    if (joystick != NULL)
        SDL_JoystickClose(joystick);
    if (renderer != NULL)
        SDL_DestroyRenderer(renderer);
    if (window != NULL)
        SDL_DestroyWindow(window);
    SDL_Quit();
    if (g_log != NULL)
    {
        fprintf(g_log, "Rendered frames: %u\n", frames);
        fclose(g_log);
    }
    return (frames > 0) ? 0 : 1;
}
