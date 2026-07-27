#include "sh_clock.h"

#include <limits.h>

#define SH_CLOCK_UNITS_PER_SECOND UINT64_C(1000000)
#define SH_CLOCK_TICKS_PER_SECOND UINT64_C(60)

static bool sh_clock_limits_are_valid(
    uint64_t max_frame_us,
    uint32_t max_ticks_per_advance)
{
    uint64_t frame_units;
    uint64_t tick_capacity_units;

    if (max_frame_us == 0u || max_ticks_per_advance == 0u)
    {
        return false;
    }

    if (max_frame_us > (UINT64_MAX / SH_CLOCK_TICKS_PER_SECOND))
    {
        return false;
    }

    frame_units = max_frame_us * SH_CLOCK_TICKS_PER_SECOND;
    tick_capacity_units =
        (uint64_t)max_ticks_per_advance *
        SH_CLOCK_UNITS_PER_SECOND;

    return frame_units <= tick_capacity_units;
}

bool sh_clock_configure(
    ShClock* clock,
    const ShTimingConfig* config)
{
    ShTimingConfig defaults = SH_TIMING_CONFIG_INIT;
    const ShTimingConfig* selected = config != NULL ? config : &defaults;

    if (clock == NULL)
    {
        return false;
    }

    if (!sh_clock_limits_are_valid(
            selected->max_frame_us,
            selected->max_ticks_per_advance))
    {
        return false;
    }

    clock->accumulator_units = 0u;
    clock->max_frame_us = selected->max_frame_us;
    clock->max_ticks_per_advance =
        selected->max_ticks_per_advance;
    clock->paused = selected->start_paused;

    return true;
}

void sh_clock_set_paused(
    ShClock* clock,
    bool paused)
{
    if (clock != NULL)
    {
        clock->paused = paused;
    }
}

bool sh_clock_is_paused(
    const ShClock* clock)
{
    return clock != NULL && clock->paused;
}

void sh_clock_advance(
    ShClock* clock,
    uint64_t elapsed_us,
    ShClockAdvance* advance)
{
    uint64_t accepted_us;
    uint64_t total_units;

    if (clock == NULL || advance == NULL)
    {
        return;
    }

    advance->input_elapsed_us = elapsed_us;
    advance->accepted_elapsed_us = 0u;
    advance->dropped_elapsed_us = 0u;
    advance->paused_elapsed_us = 0u;
    advance->ticks = 0u;
    advance->interpolation_units =
        (uint32_t)clock->accumulator_units;
    advance->paused = clock->paused;

    if (clock->paused)
    {
        advance->paused_elapsed_us = elapsed_us;
        return;
    }

    accepted_us =
        elapsed_us > clock->max_frame_us ?
        clock->max_frame_us :
        elapsed_us;

    advance->accepted_elapsed_us = accepted_us;
    advance->dropped_elapsed_us = elapsed_us - accepted_us;

    total_units =
        clock->accumulator_units +
        (accepted_us * SH_CLOCK_TICKS_PER_SECOND);

    advance->ticks =
        (uint32_t)(total_units / SH_CLOCK_UNITS_PER_SECOND);

    clock->accumulator_units =
        total_units % SH_CLOCK_UNITS_PER_SECOND;

    advance->interpolation_units =
        (uint32_t)clock->accumulator_units;
}
