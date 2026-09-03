#include "sh_runtime_internal.h"

#include <string.h>

#define SH_REFERENCE_SCREEN_WIDTH 320u
#define SH_REFERENCE_SCREEN_HEIGHT 240u
#define SH_REFERENCE_KONAMI_FADE_TIMESTEP_Q12 INT32_C(819)
#define SH_REFERENCE_KONAMI_DELAY_TICKS UINT64_C(180)

static const uint16_t g_reference_boot_audio_tasks[] = {
    UINT16_C(160),
    UINT16_C(162),
    UINT16_C(0)
};

static void sh_reference_emit_display(
    ShRuntime* runtime,
    uint64_t tick_index,
    uint16_t width,
    bool interlaced)
{
    ShPresentationCommand command = SH_PRESENTATION_COMMAND_INIT;

    command.type = SH_PRESENTATION_COMMAND_CONFIGURE_DISPLAY;
    command.tick_index = tick_index;
    command.width = width;
    command.height = (uint16_t)SH_REFERENCE_SCREEN_HEIGHT;
    command.interlaced = interlaced;
    (void)sh_presentation_emit(runtime, &command);
}

static void sh_reference_emit_fade(
    ShRuntime* runtime,
    uint64_t tick_index,
    bool arg0,
    bool arg1,
    bool arg2,
    bool timestep_valid,
    int32_t timestep_q12)
{
    ShPresentationCommand command = SH_PRESENTATION_COMMAND_INIT;

    command.type = SH_PRESENTATION_COMMAND_FADE_START;
    command.tick_index = tick_index;
    command.fade_arg0 = arg0;
    command.fade_arg1 = arg1;
    command.fade_arg2 = arg2;
    command.fade_timestep_valid = timestep_valid;
    command.fade_timestep_q12 = timestep_q12;
    (void)sh_presentation_emit(runtime, &command);
}

static void sh_reference_emit_logo_frame(
    ShRuntime* runtime,
    uint64_t tick_index)
{
    ShPresentationCommand command = SH_PRESENTATION_COMMAND_INIT;

    command.type = SH_PRESENTATION_COMMAND_DRAW_BOOT_LOGO;
    command.tick_index = tick_index;
    command.boot_logo = SH_BOOT_LOGO_KONAMI;
    (void)sh_presentation_emit(runtime, &command);

    command = (ShPresentationCommand)SH_PRESENTATION_COMMAND_INIT;
    command.type = SH_PRESENTATION_COMMAND_PRESENT_FRAME;
    command.tick_index = tick_index;
    (void)sh_presentation_emit(runtime, &command);
}

static void sh_reference_emit_audio_task(
    ShRuntime* runtime,
    uint64_t tick_index,
    uint16_t task_id)
{
    ShAudioCommand command = SH_AUDIO_COMMAND_INIT;

    command.type = SH_AUDIO_COMMAND_TASK;
    command.tick_index = tick_index;
    command.task_id = task_id;
    (void)sh_audio_emit(runtime, &command);
}

static bool sh_reference_state_is_implemented(ShGameState state)
{
    return state == SH_GAME_STATE_INIT ||
           state == SH_GAME_STATE_KONAMI_LOGO;
}

static void sh_reference_game_set_state(
    ShGameController* controller,
    ShGameState next_state)
{
    controller->snapshot.previous_state =
        controller->snapshot.state;
    controller->snapshot.state = next_state;
    memset(
        controller->snapshot.state_steps,
        0,
        sizeof(controller->snapshot.state_steps));
    controller->snapshot.state_tick_count = 0u;
    controller->snapshot.transition_count++;
    controller->snapshot.last_actions |=
        SH_GAME_ACTION_STATE_TRANSITION;
    controller->snapshot.state_implemented =
        sh_reference_state_is_implemented(next_state);
}

static void sh_reference_game_boot_tick(
    ShRuntime* runtime,
    ShGameController* controller,
    uint64_t tick_index)
{
    uint32_t* steps = controller->snapshot.state_steps;

    switch (steps[0])
    {
        case 0u:
            controller->snapshot.last_actions |=
                SH_GAME_ACTION_SCREEN_INIT;
            sh_reference_emit_display(
                runtime,
                tick_index,
                (uint16_t)SH_REFERENCE_SCREEN_WIDTH,
                false);
            steps[0]++;
            break;

        case 1u:
            if (!controller->boot_signals.audio_streaming_idle)
            {
                controller->snapshot.last_actions |=
                    SH_GAME_ACTION_WAIT_AUDIO;
                break;
            }

            if (steps[1] >=
                (uint32_t)(sizeof(g_reference_boot_audio_tasks) /
                sizeof(g_reference_boot_audio_tasks[0])))
            {
                controller->snapshot.state_implemented = false;
                controller->snapshot.last_actions |=
                    SH_GAME_ACTION_UNIMPLEMENTED_STATE;
                break;
            }

            controller->snapshot.last_audio_task_id =
                g_reference_boot_audio_tasks[steps[1]];

            if (controller->snapshot.last_audio_task_id != 0u)
            {
                controller->snapshot.last_actions |=
                    SH_GAME_ACTION_AUDIO_TASK;
                sh_reference_emit_audio_task(
                    runtime,
                    tick_index,
                    controller->snapshot.last_audio_task_id);
                steps[1]++;
            }
            else
            {
                steps[0]++;
            }
            break;

        case 2u:
            controller->snapshot.last_actions |=
                SH_GAME_ACTION_QUEUE_BOOT_ASSETS |
                SH_GAME_ACTION_START_FADE;
            sh_reference_emit_fade(
                runtime,
                tick_index,
                true,
                false,
                false,
                false,
                0);
            steps[0]++;
            break;

        case 3u:
            if (controller->boot_signals.fade_finished &&
                controller->boot_signals.file_queue_empty)
            {
                sh_reference_game_set_state(
                    controller,
                    SH_GAME_STATE_KONAMI_LOGO);
            }
            else
            {
                controller->snapshot.last_actions |=
                    SH_GAME_ACTION_WAIT_FADE_OR_FILES;
            }
            break;

        default:
            controller->snapshot.state_implemented = false;
            controller->snapshot.last_actions |=
                SH_GAME_ACTION_UNIMPLEMENTED_STATE;
            break;
    }
}

static void sh_reference_game_konami_tick(
    ShRuntime* runtime,
    ShGameController* controller,
    uint64_t tick_index)
{
    uint32_t* steps = controller->snapshot.state_steps;

    switch (steps[0])
    {
        case 0u:
            controller->snapshot.last_actions |=
                SH_GAME_ACTION_SCREEN_INIT |
                SH_GAME_ACTION_START_FADE |
                SH_GAME_ACTION_QUEUE_KONAMI_ASSETS;
            sh_reference_emit_display(
                runtime,
                tick_index,
                (uint16_t)(SH_REFERENCE_SCREEN_WIDTH * 2u),
                true);
            sh_reference_emit_fade(
                runtime,
                tick_index,
                true,
                true,
                false,
                true,
                SH_REFERENCE_KONAMI_FADE_TIMESTEP_Q12);
            steps[0]++;
            break;

        case 1u:
            if (controller->konami_signals.fade_none)
            {
                steps[0]++;
            }
            else
            {
                controller->snapshot.last_actions |=
                    SH_GAME_ACTION_WAIT_FADE_NONE;
            }
            break;

        case 2u:
            if (controller->konami_signals.any_input ||
                controller->snapshot.state_tick_count >
                    SH_REFERENCE_KONAMI_DELAY_TICKS)
            {
                controller->snapshot.last_actions |=
                    SH_GAME_ACTION_START_FADE;
                sh_reference_emit_fade(
                    runtime,
                    tick_index,
                    false,
                    false,
                    false,
                    true,
                    SH_REFERENCE_KONAMI_FADE_TIMESTEP_Q12);
                steps[0]++;
            }
            else
            {
                controller->snapshot.last_actions |=
                    SH_GAME_ACTION_WAIT_LOGO_DELAY;
            }
            break;

        case 3u:
            if (!controller->konami_signals.fade_finished)
            {
                controller->snapshot.last_actions |=
                    SH_GAME_ACTION_WAIT_FADE_OR_FILES;
            }
            else if (!controller->konami_signals.file_queue_empty)
            {
                controller->snapshot.last_actions |=
                    SH_GAME_ACTION_WAIT_FILE_QUEUE;
            }
            else
            {
                sh_reference_game_set_state(
                    controller,
                    SH_GAME_STATE_KCET_LOGO);
            }
            break;

        default:
            controller->snapshot.state_implemented = false;
            controller->snapshot.last_actions |=
                SH_GAME_ACTION_UNIMPLEMENTED_STATE;
            break;
    }

    controller->snapshot.last_actions |=
        SH_GAME_ACTION_DRAW_BOOT_LOGO |
        SH_GAME_ACTION_PRESENT_FRAME;
    sh_reference_emit_logo_frame(runtime, tick_index);
}

void sh_game_controller_init(ShGameController* controller)
{
    memset(controller, 0, sizeof(*controller));
    sh_game_controller_reset(controller);
    controller->reference_registered = false;
}

void sh_game_controller_reset(ShGameController* controller)
{
    ShGameBootSignals boot_signals = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameKonamiSignals konami_signals = SH_GAME_KONAMI_SIGNALS_INIT;
    ShGameSnapshot snapshot = SH_GAME_SNAPSHOT_INIT;

    controller->boot_signals = boot_signals;
    controller->konami_signals = konami_signals;
    controller->snapshot = snapshot;
}

ShResult sh_reference_game_overlay_init(
    ShRuntime* runtime,
    ShOverlayId overlay_id,
    void* userdata)
{
    ShGameController* controller = (ShGameController*)userdata;

    if (runtime == NULL ||
        overlay_id != SH_REFERENCE_ENGINE_OVERLAY_ID ||
        controller == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    sh_game_controller_reset(controller);
    controller->snapshot.reference_enabled = true;
    return SH_RESULT_OK;
}

void sh_reference_game_overlay_tick(
    ShRuntime* runtime,
    ShOverlayId overlay_id,
    uint64_t tick_index,
    void* userdata)
{
    ShGameController* controller = (ShGameController*)userdata;

    if (runtime == NULL ||
        overlay_id != SH_REFERENCE_ENGINE_OVERLAY_ID ||
        controller == NULL ||
        !controller->snapshot.reference_enabled)
    {
        return;
    }

    controller->snapshot.last_tick_index = tick_index;
    controller->snapshot.state_tick_count++;
    controller->snapshot.last_actions = SH_GAME_ACTION_NONE;
    controller->snapshot.last_audio_task_id = 0u;

    if (controller->snapshot.state == SH_GAME_STATE_INIT)
    {
        sh_reference_game_boot_tick(runtime, controller, tick_index);
    }
    else if (controller->snapshot.state == SH_GAME_STATE_KONAMI_LOGO)
    {
        sh_reference_game_konami_tick(runtime, controller, tick_index);
    }
    else
    {
        controller->snapshot.state_implemented = false;
        controller->snapshot.last_actions |=
            SH_GAME_ACTION_UNIMPLEMENTED_STATE;
    }
}

void sh_reference_game_overlay_shutdown(
    ShRuntime* runtime,
    ShOverlayId overlay_id,
    void* userdata)
{
    ShGameController* controller = (ShGameController*)userdata;

    if (runtime == NULL ||
        overlay_id != SH_REFERENCE_ENGINE_OVERLAY_ID ||
        controller == NULL)
    {
        return;
    }

    controller->snapshot.reference_enabled = false;
}
