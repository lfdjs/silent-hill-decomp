/* SPDX-License-Identifier: GPL-3.0-or-later
 * Stage 14A.7: Ryubing presentation isolation, derived from working 14A v0.1.0.
 * Diagnostic only: no Silent Hill gameplay or proprietary game files loaded.
 */
#define SDL_MAIN_HANDLED
#include <SDL.h>
#include <switch.h>

#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#define SH_WIDTH 1280
#define SH_HEIGHT 720
#define SH_LOG_PATH "sdmc:/switch/SilentHillSwitch/probe.log"
#define SH_DISC_PATH "sdmc:/switch/SilentHillSwitch/gamedata/Silent Hill (USA).bin"

/* Test-only guard for the host mock; default build NEVER auto-exits. */
#ifndef SH_TEST_EXIT_AFTER_FRAMES
#define SH_TEST_EXIT_AFTER_FRAMES 0u
#endif

static FILE *s_log = NULL;

static void sh_log(const char *format, ...)
{
    char line[512];
    va_list args;
    va_start(args, format);
    vsnprintf(line, sizeof(line), format, args);
    va_end(args);
    SDL_Log("[SH-Switch-14A7] %s", line);
    if (s_log != NULL) {
        fprintf(s_log, "%s\n", line);
        fflush(s_log);
    }
}

static void sh_tone(SDL_AudioDeviceID audio)
{
    int16_t samples[4800 * 2];
    unsigned int i;
    if (audio == 0) return;
    for (i = 0; i < 4800; ++i) {
        int16_t value = ((i / 55u) % 2u) != 0u ? 2500 : -2500;
        samples[i * 2u] = value;
        samples[i * 2u + 1u] = value;
    }
    if (SDL_QueueAudio(audio, samples, (Uint32)sizeof(samples)) != 0)
        sh_log("AUDIO queue error: %s", SDL_GetError());
}

/* Keep the SAME five-bar drawing structure as the confirmed working v0.1.0.
 * No bitmap text, batching, shaders, streaming or extra render API calls. */
static void sh_bar(SDL_Renderer *renderer, int index, int passed, int applicable)
{
    SDL_Rect bar = { 80, 280 + index * 75, 1120, 48 };
    if (!applicable)
        SDL_SetRenderDrawColor(renderer, 65, 65, 65, 255);
    else if (passed)
        SDL_SetRenderDrawColor(renderer, 70, 180, 125, 255);
    else
        SDL_SetRenderDrawColor(renderer, 186, 92, 70, 255);
    SDL_RenderFillRect(renderer, &bar);
}

int main(int argc, char **argv)
{
    SDL_Window *window = NULL;
    SDL_Renderer *renderer = NULL;
    SDL_Joystick *joystick = NULL;
    SDL_AudioDeviceID audio = 0;
    SDL_AudioSpec requested, negotiated;
    SDL_RendererInfo renderer_info;
    Result mount_result;
    FILE *disc = NULL;
    int sd_write = 0, input_ok = 0, audio_ok = 0, disc_found = 0;
    int running = 1, alternate = 0, result = 1;
    unsigned int frames = 0, buttons = 0;
    uint32_t start = 0, next_log = 5000;
    (void)argc; (void)argv;

    SDL_LogSetAllPriority(SDL_LOG_PRIORITY_INFO);
    mount_result = fsdevMountSdmc();
    (void)mkdir("sdmc:/switch", 0777);
    (void)mkdir("sdmc:/switch/SilentHillSwitch", 0777);
    s_log = fopen(SH_LOG_PATH, "w");
    sd_write = s_log != NULL;
    sh_log("BEGIN 14A.7 version=0.1.5; display=bars; auto_exit=NO");
    sh_log("SD mount_result=0x%08lX file_open=%s errno=%d", (unsigned long)mount_result,
        sd_write ? "yes" : "no", sd_write ? 0 : errno);
    sh_log("SD status uses ACTUAL write ability, not fsdevMountSdmc return alone");

    /* Restore order and flags of first, visually successful Switch probe. */
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK) < 0) {
        sh_log("FAIL SDL_Init(video+joystick): %s", SDL_GetError());
        goto cleanup;
    }
    sh_log("SDL initialized version=%d.%d.%d", SDL_MAJOR_VERSION,
        SDL_MINOR_VERSION, SDL_PATCHLEVEL);

    window = SDL_CreateWindow("Silent Hill Switch Video Diagnostic", 0, 0,
        SH_WIDTH, SH_HEIGHT, 0);
    if (!window) { sh_log("FAIL window: %s", SDL_GetError()); goto cleanup; }
    renderer = SDL_CreateRenderer(window, 0,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!renderer) { sh_log("FAIL renderer: %s", SDL_GetError()); goto cleanup; }
    memset(&renderer_info, 0, sizeof(renderer_info));
    if (SDL_GetRendererInfo(renderer, &renderer_info) == 0)
        sh_log("VIDEO renderer=%s flags=0x%X", renderer_info.name ? renderer_info.name : "unknown",
            (unsigned int)renderer_info.flags);

    if (SDL_NumJoysticks() > 0) {
        joystick = SDL_JoystickOpen(0);
        input_ok = joystick != NULL;
    }
    sh_log("INPUT devices=%d opened=%s", SDL_NumJoysticks(), input_ok ? "yes" : "no");

    if (SDL_InitSubSystem(SDL_INIT_AUDIO) == 0) {
        memset(&requested, 0, sizeof(requested));
        memset(&negotiated, 0, sizeof(negotiated));
        requested.freq = 48000;
        requested.format = AUDIO_S16SYS;
        requested.channels = 2;
        requested.samples = 1024;
        audio = SDL_OpenAudioDevice(NULL, 0, &requested, &negotiated, 0);
        audio_ok = audio != 0 && negotiated.freq == 48000 &&
            negotiated.format == AUDIO_S16SYS && negotiated.channels == 2;
        if (audio) SDL_PauseAudioDevice(audio, 0);
    }
    sh_log("AUDIO ready=%s", audio_ok ? "yes" : "no");

    disc = fopen(SH_DISC_PATH, "rb");
    disc_found = disc != NULL;
    if (disc) fclose(disc);
    sh_log("DISC optional_visible=%s (not loaded)", disc_found ? "yes" : "no");
    sh_log("VIDEO first present upcoming; A toggles; PLUS exits; stays open");
    start = SDL_GetTicks();

    while (running && appletMainLoop()) {
        SDL_Event event;
        SDL_Rect main_panel = { 80, 70, 1120, 170 };
        SDL_Rect motion = { 92, 239, 80, 14 };
        uint32_t elapsed;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) running = 0;
            if (event.type == SDL_JOYBUTTONDOWN && joystick != NULL) {
                buttons++;
                sh_log("INPUT joy button=%u", (unsigned int)event.jbutton.button);
                if (event.jbutton.button == 0) { alternate = !alternate; if (audio_ok) sh_tone(audio); }
                if (event.jbutton.button == 10) running = 0;
            }
            if (event.type == SDL_KEYDOWN && !event.key.repeat) {
                if (event.key.keysym.sym == SDLK_RETURN) alternate = !alternate;
                if (event.key.keysym.sym == SDLK_ESCAPE) running = 0;
            }
        }

        elapsed = SDL_GetTicks() - start;
        SDL_SetRenderDrawColor(renderer, alternate ? 25 : 14, 19, 31, 255);
        SDL_RenderClear(renderer);
        SDL_SetRenderDrawColor(renderer, alternate ? 102 : 79, 92, 119, 255);
        SDL_RenderFillRect(renderer, &main_panel);
        sh_bar(renderer, 0, 1, 1);              /* SDL render working */
        sh_bar(renderer, 1, input_ok, 1);       /* Controller */
        sh_bar(renderer, 2, audio_ok, 1);       /* Audio */
        sh_bar(renderer, 3, sd_write, 1);       /* Write to sdmc succeeded */
        sh_bar(renderer, 4, disc_found, 0);     /* Optional game image */
        motion.x += (int)((elapsed / 20u) % 1000u); /* Small moving green marker */
        SDL_SetRenderDrawColor(renderer, 55, 222, 142, 255);
        SDL_RenderFillRect(renderer, &motion);
        SDL_RenderPresent(renderer);
        frames++;
        if (frames == 1) sh_log("VIDEO first SDL_RenderPresent completed");
        if (elapsed >= next_log) {
            sh_log("HEARTBEAT elapsed_ms=%u frames=%u buttons=%u sd_write=%d",
                elapsed, frames, buttons, sd_write);
            next_log += 5000u;
        }
        if (SH_TEST_EXIT_AFTER_FRAMES != 0u && frames >= SH_TEST_EXIT_AFTER_FRAMES)
            running = 0;
    }
    sh_log("END normal loop frames=%u buttons=%u", frames, buttons);
    result = frames ? 0 : 1;

cleanup:
    if (audio) SDL_CloseAudioDevice(audio);
    if (joystick) SDL_JoystickClose(joystick);
    if (renderer) SDL_DestroyRenderer(renderer);
    if (window) SDL_DestroyWindow(window);
    SDL_Quit();
    sh_log("SHUTDOWN result=%d", result);
    if (s_log) fclose(s_log);
    return result;
}
