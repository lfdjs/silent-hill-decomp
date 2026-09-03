#include "silent_hill/sh_api.h"

#include <assert.h>

static void step(ShRuntime* runtime)
{
    ShAdvanceInfo info = SH_ADVANCE_INFO_INIT;
    assert(sh_runtime_step(runtime, &info) == SH_RESULT_OK);
}

int main(void)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShGameBootSignals boot = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameKonamiSignals konami = SH_GAME_KONAMI_SIGNALS_INIT;
    ShGameSnapshot snapshot = SH_GAME_SNAPSHOT_INIT;
    ShRuntime* runtime = NULL;

    timing.start_paused = true;
    config.host = &host;
    config.timing = &timing;
    assert(sh_runtime_create(&config, &runtime) == SH_RESULT_OK);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);
    assert(sh_runtime_game_enable_reference(runtime) == SH_RESULT_OK);

    boot.audio_streaming_idle = true;
    assert(sh_runtime_game_set_boot_signals(runtime, &boot) == SH_RESULT_OK);
    step(runtime); step(runtime); step(runtime); step(runtime); step(runtime);
    boot.fade_finished = true;
    boot.file_queue_empty = true;
    assert(sh_runtime_game_set_boot_signals(runtime, &boot) == SH_RESULT_OK);
    step(runtime);

    step(runtime);
    assert(sh_runtime_game_get_snapshot(runtime, &snapshot) == SH_RESULT_OK);
    assert(snapshot.state == SH_GAME_STATE_KONAMI_LOGO);
    assert(snapshot.state_steps[0] == 1u);

    konami.fade_none = true;
    assert(sh_runtime_game_set_konami_signals(runtime, &konami) == SH_RESULT_OK);
    step(runtime);
    snapshot = (ShGameSnapshot)SH_GAME_SNAPSHOT_INIT;
    assert(sh_runtime_game_get_snapshot(runtime, &snapshot) == SH_RESULT_OK);
    assert(snapshot.state_steps[0] == 2u);

    konami.any_input = true;
    assert(sh_runtime_game_set_konami_signals(runtime, &konami) == SH_RESULT_OK);
    step(runtime);
    snapshot = (ShGameSnapshot)SH_GAME_SNAPSHOT_INIT;
    assert(sh_runtime_game_get_snapshot(runtime, &snapshot) == SH_RESULT_OK);
    assert(snapshot.state_steps[0] == 3u);

    konami.fade_finished = true;
    konami.file_queue_empty = true;
    assert(sh_runtime_game_set_konami_signals(runtime, &konami) == SH_RESULT_OK);
    step(runtime);
    snapshot = (ShGameSnapshot)SH_GAME_SNAPSHOT_INIT;
    assert(sh_runtime_game_get_snapshot(runtime, &snapshot) == SH_RESULT_OK);
    assert(snapshot.state == SH_GAME_STATE_KCET_LOGO);
    assert(snapshot.previous_state == SH_GAME_STATE_KONAMI_LOGO);
    assert(snapshot.transition_count == 2u);
    assert(!snapshot.state_implemented);

    sh_runtime_destroy(runtime);
    return 0;
}
