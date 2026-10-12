#include "sh_port_template.h"

#include <string.h>

ShResult sh_port_template_init(ShPortTemplate* port, const ShPortHooks* hooks)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShResult result;

    if (port == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }
    if (port->runtime != NULL)
    {
        return SH_RESULT_INVALID_STATE;
    }

    memset(port, 0, sizeof(*port));
    if (hooks != NULL)
    {
        port->hooks = *hooks;
    }
    port->snapshot = (ShGameSnapshot)SH_GAME_SNAPSHOT_INIT;
    timing.start_paused = true;
    config.host = &host;
    config.timing = &timing;

    result = sh_runtime_create(&config, &port->runtime);
    if (result == SH_RESULT_OK)
    {
        result = sh_runtime_boot(port->runtime);
    }
    if (result == SH_RESULT_OK)
    {
        result = sh_runtime_game_enable_reference(port->runtime);
    }
    if (result != SH_RESULT_OK)
    {
        sh_port_template_destroy(port);
    }
    return result;
}

ShResult sh_port_template_tick(ShPortTemplate* port)
{
    ShInputState input = SH_INPUT_STATE_INIT;
    ShGameBootSignals boot = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameKonamiSignals konami = SH_GAME_KONAMI_SIGNALS_INIT;
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShInputButtons buttons;
    ShGameState previous;
    ShResult result;

    if (port == NULL || port->runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }
    if (port->reached_unsupported)
    {
        return SH_RESULT_INVALID_STATE;
    }
    if (port->ticks == UINT64_MAX)
    {
        return SH_RESULT_OVERFLOW;
    }

    buttons = port->hooks.poll_buttons != NULL ?
        port->hooks.poll_buttons(port->hooks.userdata) : 0u;
    input.connected = true;
    input.buttons = buttons;
    boot.audio_streaming_idle = true;
    boot.file_queue_empty = true;
    /* Deterministic stubs: replace these with real backend feedback. */
    boot.fade_finished = (port->snapshot.state == SH_GAME_STATE_INIT &&
        port->snapshot.state_steps[0] == 3u &&
        port->snapshot.state_tick_count >= UINT64_C(18));

    konami.file_queue_empty = true;
    konami.fade_none =
        (port->snapshot.state == SH_GAME_STATE_KONAMI_LOGO &&
         port->snapshot.state_steps[0] == 1u &&
         port->snapshot.state_tick_count >= UINT64_C(20));
    konami.any_input = buttons != 0u;
    konami.fade_finished = port->fade_out_seen &&
        port->ticks >= port->fade_out_tick &&
        port->ticks - port->fade_out_tick >= UINT64_C(12);

    result = sh_runtime_submit_input(port->runtime, &input);
    if (result == SH_RESULT_OK)
    {
        result = sh_runtime_game_set_boot_signals(port->runtime, &boot);
    }
    if (result == SH_RESULT_OK)
    {
        result = sh_runtime_game_set_konami_signals(port->runtime, &konami);
    }
    if (result == SH_RESULT_OK)
    {
        result = sh_runtime_step(port->runtime, &advance);
    }
    if (result != SH_RESULT_OK)
    {
        return result;
    }

    previous = port->snapshot.state;
    port->ticks++;
    port->snapshot = (ShGameSnapshot)SH_GAME_SNAPSHOT_INIT;
    result = sh_runtime_game_get_snapshot(port->runtime, &port->snapshot);
    if (result != SH_RESULT_OK)
    {
        return result;
    }

    for (;;)
    {
        ShPresentationCommand command = SH_PRESENTATION_COMMAND_INIT;
        result = sh_runtime_presentation_pop(port->runtime, &command);
        if (result == SH_RESULT_NOT_FOUND)
        {
            break;
        }
        if (result != SH_RESULT_OK)
        {
            return result;
        }
        port->video_commands++;
        if (command.type == SH_PRESENTATION_COMMAND_PRESENT_FRAME)
        {
            port->frames++;
        }
        if (command.type == SH_PRESENTATION_COMMAND_FADE_START &&
            !command.fade_arg0)
        {
            port->fade_out_tick = port->ticks;
            port->fade_out_seen = true;
        }
        if (port->hooks.on_video != NULL)
        {
            port->hooks.on_video(port->hooks.userdata, &command);
        }
    }

    for (;;)
    {
        ShAudioCommand command = SH_AUDIO_COMMAND_INIT;
        result = sh_runtime_audio_pop(port->runtime, &command);
        if (result == SH_RESULT_NOT_FOUND)
        {
            break;
        }
        if (result != SH_RESULT_OK)
        {
            return result;
        }
        port->audio_commands++;
        if (port->hooks.on_audio != NULL)
        {
            port->hooks.on_audio(port->hooks.userdata, &command);
        }
    }

    if (port->snapshot.state != previous &&
        port->hooks.on_transition != NULL)
    {
        port->hooks.on_transition(
            port->hooks.userdata, previous, port->snapshot.state);
    }
    if (!port->snapshot.state_implemented)
    {
        port->reached_unsupported = true;
    }
    return SH_RESULT_OK;
}

void sh_port_template_destroy(ShPortTemplate* port)
{
    if (port != NULL)
    {
        sh_runtime_destroy(port->runtime);
        memset(port, 0, sizeof(*port));
    }
}
