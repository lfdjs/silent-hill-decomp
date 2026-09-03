#include "sh_runtime_internal.h"

#include <string.h>

static const uint16_t g_reference_boot_audio_tasks[] = {
    UINT16_C(160),
    UINT16_C(162),
    UINT16_C(0)
};

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
        next_state == SH_GAME_STATE_INIT;
}

static void sh_reference_game_boot_tick(
    ShGameController* controller)
{
    uint32_t* steps = controller->snapshot.state_steps;

    switch (steps[0])
    {
        case 0u:
            controller->snapshot.last_actions |=
                SH_GAME_ACTION_SCREEN_INIT;
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

void sh_game_controller_init(ShGameController* controller)
{
    memset(controller, 0, sizeof(*controller));
    sh_game_controller_reset(controller);
    controller->reference_registered = false;
}

void sh_game_controller_reset(ShGameController* controller)
{
    ShGameBootSignals signals = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameSnapshot snapshot = SH_GAME_SNAPSHOT_INIT;

    controller->boot_signals = signals;
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
        sh_reference_game_boot_tick(controller);
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
