#include "sh_port_template.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

static void transition(void* userdata, ShGameState from, ShGameState to)
{
    (void)userdata;
    printf("Transition: %s -> %s\n",
        sh_game_state_name(from), sh_game_state_name(to));
}

int main(void)
{
    ShPortTemplate port = {0};
    ShPortHooks hooks = {0};
    ShResult result;
    uint64_t ticks;
    uint64_t frames;
    uint64_t audio;
    ShGameState last;

    hooks.on_transition = transition;
    result = sh_port_template_init(&port, &hooks);
    if (result != SH_RESULT_OK)
    {
        fprintf(stderr, "port init: %s\n", sh_result_string(result));
        return EXIT_FAILURE;
    }

    while (!port.reached_unsupported && port.ticks < UINT64_C(300))
    {
        result = sh_port_template_tick(&port);
        if (result != SH_RESULT_OK)
        {
            fprintf(stderr, "port tick: %s\n", sh_result_string(result));
            sh_port_template_destroy(&port);
            return EXIT_FAILURE;
        }
    }

    ticks = port.ticks;
    frames = port.frames;
    audio = port.audio_commands;
    last = port.snapshot.state;
    sh_port_template_destroy(&port);

    printf("Port template ABI %s: ticks=%" PRIu64
           " frames=%" PRIu64 " audio=%" PRIu64 " state=%s\n",
           SH_VERSION_STRING, ticks, frames, audio,
           sh_game_state_name(last));
    return last == SH_GAME_STATE_KCET_LOGO ? EXIT_SUCCESS : EXIT_FAILURE;
}
