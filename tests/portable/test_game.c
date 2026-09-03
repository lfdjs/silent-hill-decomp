#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stdint.h>
#include <string.h>

static ShRuntime* create_runtime(void)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntime* runtime = NULL;

    timing.start_paused = true;
    config.host = &host;
    config.timing = &timing;

    assert(sh_runtime_create(&config, &runtime) == SH_RESULT_OK);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);
    return runtime;
}

static void step_once(ShRuntime* runtime)
{
    ShAdvanceInfo info = SH_ADVANCE_INFO_INIT;
    assert(sh_runtime_step(runtime, &info) == SH_RESULT_OK);
    assert(info.ticks_executed == 1u);
}

static ShGameSnapshot get_snapshot(ShRuntime* runtime)
{
    ShGameSnapshot snapshot = SH_GAME_SNAPSHOT_INIT;
    assert(sh_runtime_game_get_snapshot(runtime, &snapshot) == SH_RESULT_OK);
    return snapshot;
}

static void advance_to_konami(ShRuntime* runtime)
{
    ShGameBootSignals signals = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameSnapshot snapshot;

    signals.audio_streaming_idle = true;
    assert(sh_runtime_game_set_boot_signals(runtime, &signals) == SH_RESULT_OK);

    step_once(runtime);
    step_once(runtime);
    step_once(runtime);
    step_once(runtime);
    step_once(runtime);

    signals.fade_finished = true;
    signals.file_queue_empty = true;
    assert(sh_runtime_game_set_boot_signals(runtime, &signals) == SH_RESULT_OK);
    step_once(runtime);

    snapshot = get_snapshot(runtime);
    assert(snapshot.state == SH_GAME_STATE_KONAMI_LOGO);
    assert(snapshot.state_implemented);
}

static void test_reference_boot_and_konami_flow(void)
{
    ShRuntime* runtime = create_runtime();
    ShGameKonamiSignals signals = SH_GAME_KONAMI_SIGNALS_INIT;
    ShGameSnapshot snapshot;

    assert(sh_runtime_game_enable_reference(runtime) == SH_RESULT_OK);
    advance_to_konami(runtime);

    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.state == SH_GAME_STATE_KONAMI_LOGO);
    assert(snapshot.state_steps[0] == 1u);
    assert(snapshot.last_actions ==
        (SH_GAME_ACTION_SCREEN_INIT |
         SH_GAME_ACTION_START_FADE |
         SH_GAME_ACTION_QUEUE_KONAMI_ASSETS |
         SH_GAME_ACTION_DRAW_BOOT_LOGO |
         SH_GAME_ACTION_PRESENT_FRAME));

    signals.fade_none = true;
    assert(sh_runtime_game_set_konami_signals(runtime, &signals) == SH_RESULT_OK);
    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.state_steps[0] == 2u);

    signals.any_input = true;
    assert(sh_runtime_game_set_konami_signals(runtime, &signals) == SH_RESULT_OK);
    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.state_steps[0] == 3u);
    assert((snapshot.last_actions & SH_GAME_ACTION_START_FADE) != 0u);

    signals.fade_finished = true;
    signals.file_queue_empty = false;
    assert(sh_runtime_game_set_konami_signals(runtime, &signals) == SH_RESULT_OK);
    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.state == SH_GAME_STATE_KONAMI_LOGO);
    assert((snapshot.last_actions & SH_GAME_ACTION_WAIT_FILE_QUEUE) != 0u);

    signals.file_queue_empty = true;
    assert(sh_runtime_game_set_konami_signals(runtime, &signals) == SH_RESULT_OK);
    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.previous_state == SH_GAME_STATE_KONAMI_LOGO);
    assert(snapshot.state == SH_GAME_STATE_KCET_LOGO);
    assert(snapshot.transition_count == 2u);
    assert(!snapshot.state_implemented);

    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.last_actions == SH_GAME_ACTION_UNIMPLEMENTED_STATE);

    assert(sh_runtime_game_disable_reference(runtime) == SH_RESULT_OK);
    sh_runtime_destroy(runtime);
}

static void test_contract_and_names(void)
{
    ShRuntime* runtime = create_runtime();
    ShGameBootSignals boot = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameKonamiSignals konami = SH_GAME_KONAMI_SIGNALS_INIT;

    assert(strcmp(sh_game_state_name(SH_GAME_STATE_KONAMI_LOGO), "KonamiLogo") == 0);
    assert(strcmp(sh_game_state_name(SH_GAME_STATE_KCET_LOGO), "KcetLogo") == 0);
    assert(strcmp(sh_sys_state_name(SH_SYS_STATE_GAMEPLAY), "Gameplay") == 0);

    assert(sh_runtime_game_set_konami_signals(runtime, &konami) == SH_RESULT_INVALID_STATE);
    assert(sh_runtime_game_enable_reference(runtime) == SH_RESULT_OK);

    konami.struct_size = 0u;
    assert(sh_runtime_game_set_konami_signals(runtime, &konami) == SH_RESULT_INVALID_ARGUMENT);

    konami = (ShGameKonamiSignals)SH_GAME_KONAMI_SIGNALS_INIT;
    konami.abi_version++;
    assert(sh_runtime_game_set_konami_signals(runtime, &konami) == SH_RESULT_UNSUPPORTED_VERSION);

    boot.struct_size = 0u;
    assert(sh_runtime_game_set_boot_signals(runtime, &boot) == SH_RESULT_INVALID_ARGUMENT);

    sh_runtime_destroy(runtime);
}

int main(void)
{
    test_reference_boot_and_konami_flow();
    test_contract_and_names();
    return 0;
}
