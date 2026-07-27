#ifndef SILENT_HILL_SH_CLOCK_H
#define SILENT_HILL_SH_CLOCK_H

#include "silent_hill/sh_timing.h"

typedef struct ShClock
{
    uint64_t accumulator_units;
    uint64_t max_frame_us;
    uint32_t max_ticks_per_advance;
    bool paused;
} ShClock;

typedef struct ShClockAdvance
{
    uint64_t input_elapsed_us;
    uint64_t accepted_elapsed_us;
    uint64_t dropped_elapsed_us;
    uint64_t paused_elapsed_us;
    uint32_t ticks;
    uint32_t interpolation_units;
    bool paused;
} ShClockAdvance;

bool sh_clock_configure(
    ShClock* clock,
    const ShTimingConfig* config);

void sh_clock_set_paused(
    ShClock* clock,
    bool paused);

bool sh_clock_is_paused(
    const ShClock* clock);

void sh_clock_advance(
    ShClock* clock,
    uint64_t elapsed_us,
    ShClockAdvance* advance);

#endif
