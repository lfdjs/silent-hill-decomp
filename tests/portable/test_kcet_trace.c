#include "silent_hill/sh_api.h"
#include <assert.h>

static void step(ShRuntime* runtime)
{
    ShAdvanceInfo info = SH_ADVANCE_INFO_INIT;
    assert(sh_runtime_step(runtime, &info) == SH_RESULT_OK);
}

static ShGameSnapshot snapshot(ShRuntime* runtime)
{
    ShGameSnapshot result = SH_GAME_SNAPSHOT_INIT;
    assert(sh_runtime_game_get_snapshot(runtime, &result) == SH_RESULT_OK);
    return result;
}

static void validate_route(ShKcetCardRoute route, ShGameState target)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShGameBootSignals boot = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameKonamiSignals konami = SH_GAME_KONAMI_SIGNALS_INIT;
    ShGameKcetSignals kcet = SH_GAME_KCET_SIGNALS_INIT;
    ShRuntime* runtime = NULL;
    ShGameSnapshot state;
    uint32_t i;
    bool found_kcet_draw = false;

    timing.start_paused = true;
    config.host = &host;
    config.timing = &timing;
    assert(sh_runtime_create(&config, &runtime) == SH_RESULT_OK);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);
    assert(sh_runtime_game_enable_reference(runtime) == SH_RESULT_OK);

    assert(sh_runtime_game_set_kcet_signals(NULL, &kcet) ==
        SH_RESULT_INVALID_ARGUMENT);
    kcet.card_route = route;
    assert(sh_runtime_game_set_kcet_signals(runtime, &kcet) == SH_RESULT_OK);

    boot.audio_streaming_idle = true;
    boot.file_queue_empty = true;
    boot.fade_finished = true;
    assert(sh_runtime_game_set_boot_signals(runtime, &boot) == SH_RESULT_OK);
    for (i = 0; i < 6u; i++) step(runtime);
    state = snapshot(runtime);
    assert(state.state == SH_GAME_STATE_KONAMI_LOGO);

    konami.fade_none = true;
    konami.file_queue_empty = true;
    konami.fade_finished = true;
    konami.any_input = true;
    assert(sh_runtime_game_set_konami_signals(runtime, &konami) ==
        SH_RESULT_OK);
    for (i = 0; i < 4u; i++) step(runtime);
    state = snapshot(runtime);
    assert(state.state == SH_GAME_STATE_KCET_LOGO);
    assert(state.state_implemented);

    step(runtime); /* KCET Init */
    state = snapshot(runtime);
    assert(state.state_steps[0] == 1u);
    assert(state.last_actions & SH_GAME_ACTION_RESTORE_SETTINGS);

    kcet.fade_none = true;
    kcet.file_queue_empty = true;
    assert(sh_runtime_game_set_kcet_signals(runtime, &kcet) == SH_RESULT_OK);
    step(runtime); /* card check */
    state = snapshot(runtime);
    assert(state.state_steps[0] == (uint32_t)route + 1u);
    step(runtime); /* route to Intro */
    state = snapshot(runtime);
    if (route == SH_KCET_CARD_HAS_SAVE)
    {
        assert(state.state_steps[0] == 5u);
        assert(!state.state_implemented);
        step(runtime);
        assert(snapshot(runtime).last_actions &
            SH_GAME_ACTION_UNSUPPORTED_SAVE_LOAD);
    }
    else
    {
        assert(state.state_steps[0] == 6u);
        assert(state.last_actions & SH_GAME_ACTION_QUEUE_STREAM_ASSETS);
        kcet.any_input = true;
        kcet.fade_finished = true;
        assert(sh_runtime_game_set_kcet_signals(runtime, &kcet) ==
            SH_RESULT_OK);
        step(runtime); /* request fade out */
        assert(snapshot(runtime).state_steps[0] == 7u);
        step(runtime); /* transition */
        state = snapshot(runtime);
        assert(state.state == target);
        assert(!state.state_implemented);
        assert(state.transition_count == 3u);
    }

    for (;;)
    {
        ShPresentationCommand cmd = SH_PRESENTATION_COMMAND_INIT;
        ShResult result = sh_runtime_presentation_pop(runtime, &cmd);
        if (result == SH_RESULT_NOT_FOUND) break;
        assert(result == SH_RESULT_OK);
        if (cmd.type == SH_PRESENTATION_COMMAND_DRAW_BOOT_LOGO &&
            cmd.boot_logo == SH_BOOT_LOGO_KCET)
        {
            found_kcet_draw = true;
        }
    }
    assert(found_kcet_draw);
    sh_runtime_destroy(runtime);
}

int main(void)
{
    validate_route(SH_KCET_CARD_NO_CARD, SH_GAME_STATE_MOVIE_INTRO_FADE_IN);
    validate_route(SH_KCET_CARD_NO_SPACE, SH_GAME_STATE_MOVIE_INTRO_FADE_IN);
    validate_route(SH_KCET_CARD_NO_SAVE, SH_GAME_STATE_MOVIE_INTRO);
    validate_route(SH_KCET_CARD_HAS_SAVE, SH_GAME_STATE_AUTO_LOAD_SAVEGAME);
    return 0;
}
