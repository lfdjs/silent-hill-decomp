#include "silent_hill/sh_api.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int parse_tick_count(int argc, char** argv, uint32_t* out_ticks)
{
    unsigned long value;
    char* end = NULL;

    if (out_ticks == NULL)
    {
        return 0;
    }

    *out_ticks = 8u;

    if (argc == 1)
    {
        return 1;
    }

    if (argc != 3 || argv[1] == NULL || argv[2] == NULL ||
        strcmp(argv[1], "--ticks") != 0)
    {
        return 0;
    }

    value = strtoul(argv[2], &end, 10);

    if (end == argv[2] || *end != '\0' || value == 0ul ||
        value > (unsigned long)UINT32_MAX)
    {
        return 0;
    }

    *out_ticks = (uint32_t)value;
    return 1;
}

static void print_snapshot(const ShGameSnapshot* snapshot)
{
    printf(
        "tick=%" PRIu64 " state=%u(%s) step=%u/%u/%u "
        "actions=0x%08" PRIx32,
        snapshot->last_tick_index,
        (unsigned int)snapshot->state,
        sh_game_state_name(snapshot->state),
        (unsigned int)snapshot->state_steps[0],
        (unsigned int)snapshot->state_steps[1],
        (unsigned int)snapshot->state_steps[2],
        snapshot->last_actions);

    if ((snapshot->last_actions & SH_GAME_ACTION_AUDIO_TASK) != 0u)
    {
        printf(
            " audio_task=%u",
            (unsigned int)snapshot->last_audio_task_id);
    }

    if (!snapshot->state_implemented)
    {
        printf(" implemented=no");
    }

    putchar('\n');
}

int main(int argc, char** argv)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShGameBootSignals signals = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameSnapshot snapshot = SH_GAME_SNAPSHOT_INIT;
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShRuntime* runtime = NULL;
    uint32_t ticks;
    uint32_t idx;
    ShResult result;

    if (!parse_tick_count(argc, argv, &ticks))
    {
        fprintf(stderr, "usage: %s [--ticks N]\n", argv[0]);
        return EXIT_FAILURE;
    }

    timing.start_paused = true;
    config.host = &host;
    config.timing = &timing;

    result = sh_runtime_create(&config, &runtime);

    if (result != SH_RESULT_OK)
    {
        fprintf(stderr, "runtime create: %s\n", sh_result_string(result));
        return EXIT_FAILURE;
    }

    result = sh_runtime_boot(runtime);

    if (result == SH_RESULT_OK)
    {
        result = sh_runtime_game_enable_reference(runtime);
    }

    if (result != SH_RESULT_OK)
    {
        fprintf(stderr, "runtime boot: %s\n", sh_result_string(result));
        sh_runtime_destroy(runtime);
        return EXIT_FAILURE;
    }

    signals.audio_streaming_idle = true;

    printf(
        "Silent Hill portable headless ABI %u.%u.%u\n",
        SH_VERSION_MAJOR,
        SH_VERSION_MINOR,
        SH_VERSION_PATCH);
    printf(
        "reference: GameState_Init/Boot=0 -> KonamiLogo=1\n");

    for (idx = 0u; idx < ticks; idx++)
    {
        result = sh_runtime_game_get_snapshot(runtime, &snapshot);

        if (result != SH_RESULT_OK)
        {
            break;
        }

        if (snapshot.state == SH_GAME_STATE_INIT &&
            snapshot.state_steps[0] == 3u)
        {
            signals.fade_finished = true;
            signals.file_queue_empty = true;
        }

        result = sh_runtime_game_set_boot_signals(runtime, &signals);

        if (result != SH_RESULT_OK)
        {
            break;
        }

        advance = (ShAdvanceInfo)SH_ADVANCE_INFO_INIT;
        result = sh_runtime_step(runtime, &advance);

        if (result != SH_RESULT_OK)
        {
            break;
        }

        snapshot = (ShGameSnapshot)SH_GAME_SNAPSHOT_INIT;
        result = sh_runtime_game_get_snapshot(runtime, &snapshot);

        if (result != SH_RESULT_OK)
        {
            break;
        }

        print_snapshot(&snapshot);
    }

    sh_runtime_destroy(runtime);

    if (result != SH_RESULT_OK)
    {
        fprintf(stderr, "headless run: %s\n", sh_result_string(result));
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
