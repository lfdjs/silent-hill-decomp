#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stdint.h>

typedef struct ExpectedTrace
{
    ShGameState state;
    uint32_t step0;
    uint32_t step1;
    ShGameActions actions;
    uint16_t audio_task;
} ExpectedTrace;

static const ExpectedTrace g_expected[] = {
    { SH_GAME_STATE_INIT, 1u, 0u, SH_GAME_ACTION_SCREEN_INIT, 0u },
    { SH_GAME_STATE_INIT, 1u, 1u, SH_GAME_ACTION_AUDIO_TASK, UINT16_C(160) },
    { SH_GAME_STATE_INIT, 1u, 2u, SH_GAME_ACTION_AUDIO_TASK, UINT16_C(162) },
    { SH_GAME_STATE_INIT, 2u, 2u, SH_GAME_ACTION_NONE, 0u },
    { SH_GAME_STATE_INIT, 3u, 2u,
      SH_GAME_ACTION_QUEUE_BOOT_ASSETS | SH_GAME_ACTION_START_FADE, 0u },
    { SH_GAME_STATE_KONAMI_LOGO, 0u, 0u,
      SH_GAME_ACTION_STATE_TRANSITION, 0u },
    { SH_GAME_STATE_KONAMI_LOGO, 1u, 0u,
      SH_GAME_ACTION_SCREEN_INIT | SH_GAME_ACTION_START_FADE |
      SH_GAME_ACTION_QUEUE_KONAMI_ASSETS | SH_GAME_ACTION_DRAW_BOOT_LOGO |
      SH_GAME_ACTION_PRESENT_FRAME, 0u },
    { SH_GAME_STATE_KONAMI_LOGO, 2u, 0u,
      SH_GAME_ACTION_DRAW_BOOT_LOGO | SH_GAME_ACTION_PRESENT_FRAME, 0u },
    { SH_GAME_STATE_KONAMI_LOGO, 3u, 0u,
      SH_GAME_ACTION_START_FADE | SH_GAME_ACTION_DRAW_BOOT_LOGO |
      SH_GAME_ACTION_PRESENT_FRAME, 0u },
    { SH_GAME_STATE_KCET_LOGO, 0u, 0u,
      SH_GAME_ACTION_STATE_TRANSITION | SH_GAME_ACTION_DRAW_BOOT_LOGO |
      SH_GAME_ACTION_PRESENT_FRAME, 0u },
    { SH_GAME_STATE_KCET_LOGO, 0u, 0u,
      SH_GAME_ACTION_UNIMPLEMENTED_STATE, 0u }
};

int main(void)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShGameBootSignals boot = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameKonamiSignals konami = SH_GAME_KONAMI_SIGNALS_INIT;
    ShRuntime* runtime = NULL;
    size_t idx;

    timing.start_paused = true;
    config.host = &host;
    config.timing = &timing;

    assert(sh_runtime_create(&config, &runtime) == SH_RESULT_OK);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);
    assert(sh_runtime_game_enable_reference(runtime) == SH_RESULT_OK);
    boot.audio_streaming_idle = true;

    for (idx = 0u; idx < sizeof(g_expected) / sizeof(g_expected[0]); idx++)
    {
        ShGameSnapshot snapshot = SH_GAME_SNAPSHOT_INIT;
        ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;

        if (idx == 5u)
        {
            boot.fade_finished = true;
            boot.file_queue_empty = true;
        }
        if (idx == 7u)
        {
            konami.fade_none = true;
        }
        if (idx == 8u)
        {
            konami.any_input = true;
        }
        if (idx == 9u)
        {
            konami.fade_finished = true;
            konami.file_queue_empty = true;
        }

        assert(sh_runtime_game_set_boot_signals(runtime, &boot) == SH_RESULT_OK);
        assert(sh_runtime_game_set_konami_signals(runtime, &konami) == SH_RESULT_OK);
        assert(sh_runtime_step(runtime, &advance) == SH_RESULT_OK);
        assert(sh_runtime_game_get_snapshot(runtime, &snapshot) == SH_RESULT_OK);

        assert(snapshot.last_tick_index == (uint64_t)(idx + 1u));
        assert(snapshot.state == g_expected[idx].state);
        assert(snapshot.state_steps[0] == g_expected[idx].step0);
        assert(snapshot.state_steps[1] == g_expected[idx].step1);
        assert(snapshot.last_actions == g_expected[idx].actions);
        assert(snapshot.last_audio_task_id == g_expected[idx].audio_task);
    }

    sh_runtime_destroy(runtime);
    return 0;
}
