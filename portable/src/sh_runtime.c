#include "sh_runtime_internal.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

bool sh_runtime_size_is_supported(
    uint32_t supplied,
    size_t required)
{
    if (required > (size_t)UINT32_MAX)
    {
        return false;
    }

    return supplied >= (uint32_t)required;
}

bool sh_runtime_is_ready(const ShRuntime* runtime)
{
    return runtime != NULL && runtime->booted;
}

static bool sh_u64_add_would_overflow(
    uint64_t lhs,
    uint64_t rhs)
{
    return UINT64_MAX - lhs < rhs;
}

static void sh_runtime_log(
    const ShRuntime* runtime,
    ShLogLevel level,
    const char* message)
{
    if (runtime != NULL && runtime->host.log != NULL)
    {
        runtime->host.log(runtime->host.userdata, level, message);
    }
}

static ShResult sh_advance_info_validate(
    const ShAdvanceInfo* info)
{
    if (info == NULL)
    {
        return SH_RESULT_OK;
    }

    if (!sh_runtime_size_is_supported(
            info->struct_size,
            sizeof(ShAdvanceInfo)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (info->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    return SH_RESULT_OK;
}

static void sh_advance_info_write(
    ShAdvanceInfo* info,
    const ShClockAdvance* clock_advance,
    uint64_t tick_count_before,
    uint64_t tick_count_after)
{
    if (info == NULL)
    {
        return;
    }

    info->struct_size = (uint32_t)sizeof(ShAdvanceInfo);
    info->abi_version = SH_ABI_VERSION_CURRENT;
    info->input_elapsed_us = clock_advance->input_elapsed_us;
    info->accepted_elapsed_us =
        clock_advance->accepted_elapsed_us;
    info->dropped_elapsed_us =
        clock_advance->dropped_elapsed_us;
    info->paused_elapsed_us =
        clock_advance->paused_elapsed_us;
    info->tick_count_before = tick_count_before;
    info->tick_count_after = tick_count_after;
    info->ticks_executed = clock_advance->ticks;
    info->interpolation_units =
        clock_advance->interpolation_units;
    info->paused = clock_advance->paused;
}

static void sh_runtime_latch_input(ShRuntime* runtime)
{
    ShInputButtons previous_buttons =
        runtime->input_snapshot.buttons;
    ShInputButtons current_buttons =
        runtime->submitted_input.connected ?
        runtime->submitted_input.buttons :
        0u;

    runtime->input_snapshot.tick_index =
        runtime->tick_count;
    runtime->input_snapshot.connected =
        runtime->submitted_input.connected;
    runtime->input_snapshot.buttons =
        current_buttons;
    runtime->input_snapshot.pressed =
        current_buttons & ~previous_buttons;
    runtime->input_snapshot.released =
        previous_buttons & ~current_buttons;

    runtime->input_snapshot.left_x =
        runtime->submitted_input.connected ?
        runtime->submitted_input.left_x :
        0;

    runtime->input_snapshot.left_y =
        runtime->submitted_input.connected ?
        runtime->submitted_input.left_y :
        0;

    runtime->input_snapshot.right_x =
        runtime->submitted_input.connected ?
        runtime->submitted_input.right_x :
        0;

    runtime->input_snapshot.right_y =
        runtime->submitted_input.connected ?
        runtime->submitted_input.right_y :
        0;
}

static void sh_runtime_execute_ticks(
    ShRuntime* runtime,
    uint32_t tick_count)
{
    uint32_t idx;

    for (idx = 0u; idx < tick_count; idx++)
    {
        runtime->tick_count++;
        sh_runtime_latch_input(runtime);
        sh_overlay_manager_tick(
            &runtime->overlays,
            runtime,
            runtime->tick_count);

        if (runtime->tick != NULL)
        {
            runtime->tick(
                runtime->tick_userdata,
                runtime->tick_count);
        }
    }
}

uint32_t sh_api_version(void)
{
    return SH_ABI_VERSION_CURRENT;
}

const char* sh_result_string(ShResult result)
{
    switch (result)
    {
        case SH_RESULT_OK:
            return "ok";

        case SH_RESULT_INVALID_ARGUMENT:
            return "invalid argument";

        case SH_RESULT_UNSUPPORTED_VERSION:
            return "unsupported version";

        case SH_RESULT_HOST_ERROR:
            return "host error";

        case SH_RESULT_OUT_OF_MEMORY:
            return "out of memory";

        case SH_RESULT_NOT_READY:
            return "not ready";

        case SH_RESULT_OVERFLOW:
            return "overflow";

        case SH_RESULT_INVALID_STATE:
            return "invalid state";

        case SH_RESULT_UNSUPPORTED:
            return "unsupported";

        case SH_RESULT_NOT_FOUND:
            return "not found";

        case SH_RESULT_IO_ERROR:
            return "I/O error";

        case SH_RESULT_BUFFER_TOO_SMALL:
            return "buffer too small";

        default:
            return "unknown result";
    }
}

ShResult sh_runtime_create(
    const ShRuntimeConfig* config,
    ShRuntime** out_runtime)
{
    ShRuntime* runtime;
    ShTimingConfig default_timing = SH_TIMING_CONFIG_INIT;
    ShInputConfig default_input = SH_INPUT_CONFIG_INIT;
    ShMemoryConfig default_memory = SH_MEMORY_CONFIG_INIT;
    ShInputState initial_input = SH_INPUT_STATE_INIT;
    ShInputSnapshot initial_snapshot =
        SH_INPUT_SNAPSHOT_INIT;
    const ShTimingConfig* timing;
    const ShInputConfig* input;
    const ShMemoryConfig* memory;

    if (out_runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    *out_runtime = NULL;

    if (config == NULL || config->host == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_runtime_size_is_supported(
            config->struct_size,
            sizeof(ShRuntimeConfig)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (config->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    if (!sh_runtime_size_is_supported(
            config->host->struct_size,
            sizeof(ShHostServices)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (config->host->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    timing =
        config->timing != NULL ?
        config->timing :
        &default_timing;

    if (!sh_runtime_size_is_supported(
            timing->struct_size,
            sizeof(ShTimingConfig)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (timing->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    input =
        config->input != NULL ?
        config->input :
        &default_input;

    if (!sh_runtime_size_is_supported(
            input->struct_size,
            sizeof(ShInputConfig)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (input->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    if (input->analog_deadzone >=
        (uint16_t)SH_INPUT_AXIS_MAX)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    memory =
        config->memory != NULL ?
        config->memory :
        &default_memory;

    if (!sh_runtime_size_is_supported(
            memory->struct_size,
            sizeof(ShMemoryConfig)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (memory->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    runtime = (ShRuntime*)calloc(1u, sizeof(*runtime));

    if (runtime == NULL)
    {
        return SH_RESULT_OUT_OF_MEMORY;
    }

    if (!sh_clock_configure(&runtime->clock, timing))
    {
        free(runtime);
        return SH_RESULT_INVALID_ARGUMENT;
    }

    {
        ShResult memory_result = sh_memory_init(
            &runtime->memory,
            memory);

        if (memory_result != SH_RESULT_OK)
        {
            free(runtime);
            return memory_result;
        }
    }

    sh_overlay_manager_init(&runtime->overlays);
    sh_game_controller_init(&runtime->game);

    memcpy(&runtime->host, config->host, sizeof(runtime->host));
    memcpy(
        &runtime->input_config,
        input,
        sizeof(runtime->input_config));

    runtime->submitted_input = initial_input;
    runtime->input_snapshot = initial_snapshot;

    sh_rng_init(&runtime->rng, config->initial_rng_seed);

    runtime->tick = timing->tick;
    runtime->tick_userdata = timing->tick_userdata;

    *out_runtime = runtime;
    return SH_RESULT_OK;
}

void sh_runtime_destroy(ShRuntime* runtime)
{
    if (runtime == NULL)
    {
        return;
    }

    sh_overlay_manager_destroy(&runtime->overlays, runtime);
    sh_memory_destroy(&runtime->memory);
    free(runtime);
}

ShResult sh_runtime_boot(ShRuntime* runtime)
{
    if (runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        runtime->booted = true;

        sh_runtime_log(
            runtime,
            SH_LOG_LEVEL_INFO,
            "silent_hill_core: runtime booted");
    }

    return SH_RESULT_OK;
}

ShResult sh_runtime_submit_input(
    ShRuntime* runtime,
    const ShInputState* input)
{
    ShInputState submitted;

    if (runtime == NULL || input == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    if (!sh_runtime_size_is_supported(
            input->struct_size,
            sizeof(ShInputState)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (input->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    if ((input->buttons & ~SH_INPUT_BUTTON_KNOWN_MASK) != 0u)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    submitted = *input;
    submitted.struct_size = (uint32_t)sizeof(ShInputState);
    submitted.abi_version = SH_ABI_VERSION_CURRENT;

    if (!submitted.connected)
    {
        submitted.buttons = 0u;
        submitted.left_x = 0;
        submitted.left_y = 0;
        submitted.right_x = 0;
        submitted.right_y = 0;
    }
    else
    {
        submitted.left_x = sh_input_apply_deadzone(
            submitted.left_x,
            runtime->input_config.analog_deadzone);

        submitted.left_y = sh_input_apply_deadzone(
            submitted.left_y,
            runtime->input_config.analog_deadzone);

        submitted.right_x = sh_input_apply_deadzone(
            submitted.right_x,
            runtime->input_config.analog_deadzone);

        submitted.right_y = sh_input_apply_deadzone(
            submitted.right_y,
            runtime->input_config.analog_deadzone);
    }

    runtime->submitted_input = submitted;
    return SH_RESULT_OK;
}

ShResult sh_runtime_get_input(
    const ShRuntime* runtime,
    ShInputSnapshot* out_snapshot)
{
    if (runtime == NULL || out_snapshot == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    if (!sh_runtime_size_is_supported(
            out_snapshot->struct_size,
            sizeof(ShInputSnapshot)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_snapshot->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    *out_snapshot = runtime->input_snapshot;
    return SH_RESULT_OK;
}

ShResult sh_runtime_advance(
    ShRuntime* runtime,
    uint64_t elapsed_us,
    ShAdvanceInfo* out_info)
{
    ShClockAdvance advance;
    ShResult info_result;
    uint64_t accumulator_before;
    uint64_t tick_count_before;

    if (runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    info_result = sh_advance_info_validate(out_info);

    if (info_result != SH_RESULT_OK)
    {
        return info_result;
    }

    accumulator_before = runtime->clock.accumulator_units;
    sh_clock_advance(&runtime->clock, elapsed_us, &advance);

    if (sh_u64_add_would_overflow(
            runtime->total_elapsed_us,
            advance.input_elapsed_us) ||
        sh_u64_add_would_overflow(
            runtime->accepted_elapsed_us,
            advance.accepted_elapsed_us) ||
        sh_u64_add_would_overflow(
            runtime->dropped_elapsed_us,
            advance.dropped_elapsed_us) ||
        sh_u64_add_would_overflow(
            runtime->paused_elapsed_us,
            advance.paused_elapsed_us) ||
        sh_u64_add_would_overflow(
            runtime->tick_count,
            (uint64_t)advance.ticks) ||
        runtime->update_count == UINT64_MAX)
    {
        runtime->clock.accumulator_units = accumulator_before;
        return SH_RESULT_OVERFLOW;
    }

    tick_count_before = runtime->tick_count;

    runtime->update_count++;
    runtime->total_elapsed_us += advance.input_elapsed_us;
    runtime->accepted_elapsed_us +=
        advance.accepted_elapsed_us;
    runtime->dropped_elapsed_us +=
        advance.dropped_elapsed_us;
    runtime->paused_elapsed_us +=
        advance.paused_elapsed_us;
    runtime->last_advance_ticks = advance.ticks;

    sh_runtime_execute_ticks(runtime, advance.ticks);

    sh_advance_info_write(
        out_info,
        &advance,
        tick_count_before,
        runtime->tick_count);

    return SH_RESULT_OK;
}

ShResult sh_runtime_update(
    ShRuntime* runtime,
    uint64_t elapsed_us)
{
    return sh_runtime_advance(runtime, elapsed_us, NULL);
}

ShResult sh_runtime_set_paused(
    ShRuntime* runtime,
    bool paused)
{
    if (runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    sh_clock_set_paused(&runtime->clock, paused);

    return SH_RESULT_OK;
}

ShResult sh_runtime_step(
    ShRuntime* runtime,
    ShAdvanceInfo* out_info)
{
    ShClockAdvance advance = {
        0u,
        0u,
        0u,
        0u,
        1u,
        0u,
        true
    };
    ShResult info_result;
    uint64_t tick_count_before;

    if (runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    if (!sh_clock_is_paused(&runtime->clock))
    {
        return SH_RESULT_INVALID_STATE;
    }

    info_result = sh_advance_info_validate(out_info);

    if (info_result != SH_RESULT_OK)
    {
        return info_result;
    }

    if (runtime->update_count == UINT64_MAX ||
        runtime->tick_count == UINT64_MAX)
    {
        return SH_RESULT_OVERFLOW;
    }

    advance.interpolation_units =
        (uint32_t)runtime->clock.accumulator_units;

    tick_count_before = runtime->tick_count;

    runtime->update_count++;
    runtime->last_advance_ticks = 1u;

    sh_runtime_execute_ticks(runtime, 1u);

    sh_advance_info_write(
        out_info,
        &advance,
        tick_count_before,
        runtime->tick_count);

    return SH_RESULT_OK;
}

ShResult sh_runtime_get_stats(
    const ShRuntime* runtime,
    ShRuntimeStats* out_stats)
{
    if (runtime == NULL || out_stats == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_runtime_size_is_supported(
            out_stats->struct_size,
            sizeof(ShRuntimeStats)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_stats->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    out_stats->struct_size =
        (uint32_t)sizeof(ShRuntimeStats);
    out_stats->abi_version =
        SH_ABI_VERSION_CURRENT;
    out_stats->update_count =
        runtime->update_count;
    out_stats->total_elapsed_us =
        runtime->total_elapsed_us;
    out_stats->booted =
        runtime->booted;
    out_stats->tick_count =
        runtime->tick_count;
    out_stats->accepted_elapsed_us =
        runtime->accepted_elapsed_us;
    out_stats->dropped_elapsed_us =
        runtime->dropped_elapsed_us;
    out_stats->paused_elapsed_us =
        runtime->paused_elapsed_us;
    out_stats->interpolation_units =
        (uint32_t)runtime->clock.accumulator_units;
    out_stats->last_advance_ticks =
        runtime->last_advance_ticks;
    out_stats->paused =
        sh_clock_is_paused(&runtime->clock);

    return SH_RESULT_OK;
}
