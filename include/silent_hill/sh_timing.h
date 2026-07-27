#ifndef SILENT_HILL_SH_TIMING_H
#define SILENT_HILL_SH_TIMING_H

#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SH_TICKS_PER_SECOND UINT32_C(60)
#define SH_INTERPOLATION_UNITS_PER_TICK UINT32_C(1000000)
#define SH_DEFAULT_MAX_TICKS_PER_ADVANCE UINT32_C(8)
#define SH_DEFAULT_MAX_FRAME_US UINT64_C(133333)

typedef void (*ShTickFn)(
    void* userdata,
    uint64_t tick_index);

typedef struct ShTimingConfig
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t max_frame_us;
    uint32_t max_ticks_per_advance;
    bool start_paused;
    ShTickFn tick;
    void* tick_userdata;
} ShTimingConfig;

#define SH_TIMING_CONFIG_INIT \
    { \
        (uint32_t)sizeof(ShTimingConfig), \
        SH_ABI_VERSION_CURRENT, \
        SH_DEFAULT_MAX_FRAME_US, \
        SH_DEFAULT_MAX_TICKS_PER_ADVANCE, \
        false, \
        NULL, \
        NULL \
    }

typedef struct ShAdvanceInfo
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t input_elapsed_us;
    uint64_t accepted_elapsed_us;
    uint64_t dropped_elapsed_us;
    uint64_t paused_elapsed_us;
    uint64_t tick_count_before;
    uint64_t tick_count_after;
    uint32_t ticks_executed;
    uint32_t interpolation_units;
    bool paused;
} ShAdvanceInfo;

#define SH_ADVANCE_INFO_INIT \
    { \
        (uint32_t)sizeof(ShAdvanceInfo), \
        SH_ABI_VERSION_CURRENT, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        false \
    }

#ifdef __cplusplus
}
#endif

#endif
