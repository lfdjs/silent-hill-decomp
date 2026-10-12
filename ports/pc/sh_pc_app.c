#include "sh_pc_app.h"

#include <string.h>

ShResult sh_pc_app_init(ShPcApp* app, ShPcVideoFn video_fn,
                         ShPcAudioFn audio_fn, void* sink_userdata)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShResult result;

    if (app == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    memset(app, 0, sizeof(*app));
    app->video_fn = video_fn;
    app->audio_fn = audio_fn;
    app->sink_userdata = sink_userdata;
    app->snapshot = (ShGameSnapshot)SH_GAME_SNAPSHOT_INIT;
    timing.start_paused = true;
    config.host = &host;
    config.timing = &timing;

    result = sh_runtime_create(&config, &app->runtime);
    if (result == SH_RESULT_OK)
    {
        result = sh_runtime_boot(app->runtime);
    }
    if (result == SH_RESULT_OK)
    {
        result = sh_runtime_game_enable_reference(app->runtime);
    }
    if (result != SH_RESULT_OK)
    {
        sh_pc_app_destroy(app);
    }
    return result;
}

ShResult sh_pc_app_tick(ShPcApp* app, ShInputButtons buttons)
{
    ShInputState input = SH_INPUT_STATE_INIT;
    ShGameBootSignals boot = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameKonamiSignals konami = SH_GAME_KONAMI_SIGNALS_INIT;
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShResult result;

    if (app == NULL || app->runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }
    if (app->reached_unsupported)
    {
        return SH_RESULT_INVALID_STATE;
    }

    input.connected = true;
    input.buttons = buttons;
    boot.audio_streaming_idle = true;
    boot.file_queue_empty = true;
    boot.fade_finished = (app->snapshot.state == SH_GAME_STATE_INIT &&
        app->snapshot.state_steps[0] == 3u &&
        app->snapshot.state_tick_count >= UINT64_C(18));

    konami.file_queue_empty = true;
    konami.fade_none = (app->snapshot.state == SH_GAME_STATE_KONAMI_LOGO &&
        app->snapshot.state_steps[0] == 1u &&
        app->snapshot.state_tick_count >= UINT64_C(20));
    konami.any_input = (buttons != 0u);
    konami.fade_finished = (app->fade_out_seen &&
        app->ticks >= app->fade_out_tick &&
        (app->ticks - app->fade_out_tick) >= UINT64_C(12));

    result = sh_runtime_submit_input(app->runtime, &input);
    if (result == SH_RESULT_OK)
    {
        result = sh_runtime_game_set_boot_signals(app->runtime, &boot);
    }
    if (result == SH_RESULT_OK)
    {
        result = sh_runtime_game_set_konami_signals(app->runtime, &konami);
    }
    if (result == SH_RESULT_OK)
    {
        result = sh_runtime_step(app->runtime, &advance);
    }
    if (result != SH_RESULT_OK)
    {
        return result;
    }

    app->ticks++;
    app->snapshot = (ShGameSnapshot)SH_GAME_SNAPSHOT_INIT;
    result = sh_runtime_game_get_snapshot(app->runtime, &app->snapshot);
    if (result != SH_RESULT_OK)
    {
        return result;
    }

    for (;;)
    {
        ShPresentationCommand command = SH_PRESENTATION_COMMAND_INIT;
        result = sh_runtime_presentation_pop(app->runtime, &command);
        if (result == SH_RESULT_NOT_FOUND)
        {
            break;
        }
        if (result != SH_RESULT_OK)
        {
            return result;
        }
        app->video_commands++;
        if (command.type == SH_PRESENTATION_COMMAND_PRESENT_FRAME)
        {
            app->frames++;
        }
        if (command.type == SH_PRESENTATION_COMMAND_FADE_START &&
            !command.fade_arg0)
        {
            app->fade_out_tick = app->ticks;
            app->fade_out_seen = true;
        }
        if (app->video_fn != NULL)
        {
            app->video_fn(app->sink_userdata, &command);
        }
    }

    for (;;)
    {
        ShAudioCommand command = SH_AUDIO_COMMAND_INIT;
        result = sh_runtime_audio_pop(app->runtime, &command);
        if (result == SH_RESULT_NOT_FOUND)
        {
            break;
        }
        if (result != SH_RESULT_OK)
        {
            return result;
        }
        app->audio_commands++;
        if (command.type == SH_AUDIO_COMMAND_TASK && command.task_id == 160u)
        {
            app->audio_160_count++;
        }
        if (command.type == SH_AUDIO_COMMAND_TASK && command.task_id == 162u)
        {
            app->audio_162_count++;
        }
        if (app->audio_fn != NULL)
        {
            app->audio_fn(app->sink_userdata, &command);
        }
    }

    if (!app->snapshot.state_implemented)
    {
        app->reached_unsupported = true;
    }
    return SH_RESULT_OK;
}

void sh_pc_app_destroy(ShPcApp* app)
{
    if (app != NULL)
    {
        sh_runtime_destroy(app->runtime);
        app->runtime = NULL;
    }
}
