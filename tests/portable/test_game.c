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

    assert(
        sh_runtime_game_get_snapshot(runtime, &snapshot) ==
        SH_RESULT_OK);

    return snapshot;
}

static void test_reference_boot_flow(void)
{
    ShRuntime* runtime = create_runtime();
    ShGameBootSignals signals = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameSnapshot snapshot;
    ShOverlayStats overlay_stats = SH_OVERLAY_STATS_INIT;

    assert(
        sh_runtime_game_enable_reference(runtime) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_game_enable_reference(runtime) ==
        SH_RESULT_OK);

    snapshot = get_snapshot(runtime);
    assert(snapshot.reference_enabled);
    assert(snapshot.state_implemented);
    assert(snapshot.state == SH_GAME_STATE_INIT);
    assert(snapshot.previous_state == SH_GAME_STATE_INIT);
    assert(snapshot.state_steps[0] == 0u);
    assert(snapshot.transition_count == 0u);

    assert(
        sh_runtime_overlay_get_stats(runtime, &overlay_stats) ==
        SH_RESULT_OK);
    assert(overlay_stats.registered_count == 1u);
    assert(overlay_stats.active_count == 1u);

    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.state_steps[0] == 1u);
    assert(snapshot.last_actions == SH_GAME_ACTION_SCREEN_INIT);

    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.state_steps[0] == 1u);
    assert(snapshot.last_actions == SH_GAME_ACTION_WAIT_AUDIO);

    signals.audio_streaming_idle = true;
    assert(
        sh_runtime_game_set_boot_signals(runtime, &signals) ==
        SH_RESULT_OK);

    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.state_steps[1] == 1u);
    assert(snapshot.last_actions == SH_GAME_ACTION_AUDIO_TASK);
    assert(snapshot.last_audio_task_id == UINT16_C(160));

    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.state_steps[1] == 2u);
    assert(snapshot.last_actions == SH_GAME_ACTION_AUDIO_TASK);
    assert(snapshot.last_audio_task_id == UINT16_C(162));

    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.state_steps[0] == 2u);
    assert(snapshot.state_steps[1] == 2u);
    assert(snapshot.last_actions == SH_GAME_ACTION_NONE);

    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.state_steps[0] == 3u);
    assert(
        snapshot.last_actions ==
        (SH_GAME_ACTION_QUEUE_BOOT_ASSETS |
         SH_GAME_ACTION_START_FADE));

    signals.fade_finished = true;
    assert(
        sh_runtime_game_set_boot_signals(runtime, &signals) ==
        SH_RESULT_OK);

    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.state == SH_GAME_STATE_INIT);
    assert(snapshot.last_actions == SH_GAME_ACTION_WAIT_FADE_OR_FILES);

    signals.file_queue_empty = true;
    assert(
        sh_runtime_game_set_boot_signals(runtime, &signals) ==
        SH_RESULT_OK);

    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.previous_state == SH_GAME_STATE_INIT);
    assert(snapshot.state == SH_GAME_STATE_KONAMI_LOGO);
    assert(snapshot.state_steps[0] == 0u);
    assert(snapshot.state_steps[1] == 0u);
    assert(snapshot.transition_count == 1u);
    assert(snapshot.state_tick_count == 0u);
    assert(snapshot.last_actions == SH_GAME_ACTION_STATE_TRANSITION);
    assert(!snapshot.state_implemented);

    step_once(runtime);
    snapshot = get_snapshot(runtime);
    assert(snapshot.state == SH_GAME_STATE_KONAMI_LOGO);
    assert(snapshot.last_actions == SH_GAME_ACTION_UNIMPLEMENTED_STATE);
    assert(snapshot.state_tick_count == 1u);

    assert(
        sh_runtime_game_disable_reference(runtime) ==
        SH_RESULT_OK);

    snapshot = get_snapshot(runtime);
    assert(!snapshot.reference_enabled);

    overlay_stats = (ShOverlayStats)SH_OVERLAY_STATS_INIT;
    assert(
        sh_runtime_overlay_get_stats(runtime, &overlay_stats) ==
        SH_RESULT_OK);
    assert(overlay_stats.registered_count == 0u);
    assert(overlay_stats.active_count == 0u);

    assert(
        sh_runtime_game_disable_reference(runtime) ==
        SH_RESULT_OK);

    sh_runtime_destroy(runtime);
}

static void test_contract_and_names(void)
{
    ShRuntime* runtime = create_runtime();
    ShGameBootSignals signals = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameSnapshot snapshot = SH_GAME_SNAPSHOT_INIT;

    assert(SH_GAME_STATE_INIT == 0);
    assert(SH_GAME_STATE_KONAMI_LOGO == 1);
    assert(SH_GAME_STATE_MAIN_MENU == 7);
    assert(SH_GAME_STATE_IN_GAME == 11);
    assert(SH_GAME_STATE_CREDITS == 21);
    assert(SH_SYS_STATE_GAMEPLAY == 0);
    assert(SH_SYS_STATE_GAME_PAUSED == 14);
    assert(SH_SYS_STATE_INVALID == 15);

    assert(strcmp(sh_game_state_name(SH_GAME_STATE_INIT), "Init/Boot") == 0);
    assert(strcmp(sh_game_state_name(SH_GAME_STATE_IN_GAME), "InGame") == 0);
    assert(strcmp(sh_game_state_name((ShGameState)99), "Unknown") == 0);
    assert(strcmp(sh_sys_state_name(SH_SYS_STATE_GAMEPLAY), "Gameplay") == 0);
    assert(strcmp(sh_sys_state_name((ShSysState)99), "Unknown") == 0);

    assert(
        sh_runtime_game_set_boot_signals(runtime, &signals) ==
        SH_RESULT_INVALID_STATE);

    assert(
        sh_runtime_game_enable_reference(runtime) ==
        SH_RESULT_OK);

    signals.struct_size = 0u;
    assert(
        sh_runtime_game_set_boot_signals(runtime, &signals) ==
        SH_RESULT_INVALID_ARGUMENT);

    signals = (ShGameBootSignals)SH_GAME_BOOT_SIGNALS_INIT;
    signals.abi_version++;
    assert(
        sh_runtime_game_set_boot_signals(runtime, &signals) ==
        SH_RESULT_UNSUPPORTED_VERSION);

    snapshot.struct_size = 0u;
    assert(
        sh_runtime_game_get_snapshot(runtime, &snapshot) ==
        SH_RESULT_INVALID_ARGUMENT);

    snapshot = (ShGameSnapshot)SH_GAME_SNAPSHOT_INIT;
    snapshot.abi_version++;
    assert(
        sh_runtime_game_get_snapshot(runtime, &snapshot) ==
        SH_RESULT_UNSUPPORTED_VERSION);

    sh_runtime_destroy(runtime);
}

int main(void)
{
    test_reference_boot_flow();
    test_contract_and_names();
    return 0;
}
