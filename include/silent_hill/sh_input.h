#ifndef SILENT_HILL_SH_INPUT_H
#define SILENT_HILL_SH_INPUT_H

#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef uint64_t ShInputButtons;

#define SH_INPUT_BUTTON_UP       (UINT64_C(1) << 0u)
#define SH_INPUT_BUTTON_DOWN     (UINT64_C(1) << 1u)
#define SH_INPUT_BUTTON_LEFT     (UINT64_C(1) << 2u)
#define SH_INPUT_BUTTON_RIGHT    (UINT64_C(1) << 3u)
#define SH_INPUT_BUTTON_START    (UINT64_C(1) << 4u)
#define SH_INPUT_BUTTON_SELECT   (UINT64_C(1) << 5u)
#define SH_INPUT_BUTTON_L1       (UINT64_C(1) << 6u)
#define SH_INPUT_BUTTON_R1       (UINT64_C(1) << 7u)
#define SH_INPUT_BUTTON_L2       (UINT64_C(1) << 8u)
#define SH_INPUT_BUTTON_R2       (UINT64_C(1) << 9u)
#define SH_INPUT_BUTTON_L3       (UINT64_C(1) << 10u)
#define SH_INPUT_BUTTON_R3       (UINT64_C(1) << 11u)
#define SH_INPUT_BUTTON_TRIANGLE (UINT64_C(1) << 12u)
#define SH_INPUT_BUTTON_CIRCLE   (UINT64_C(1) << 13u)
#define SH_INPUT_BUTTON_CROSS    (UINT64_C(1) << 14u)
#define SH_INPUT_BUTTON_SQUARE   (UINT64_C(1) << 15u)

#define SH_INPUT_BUTTON_KNOWN_MASK \
    ( \
        SH_INPUT_BUTTON_UP | \
        SH_INPUT_BUTTON_DOWN | \
        SH_INPUT_BUTTON_LEFT | \
        SH_INPUT_BUTTON_RIGHT | \
        SH_INPUT_BUTTON_START | \
        SH_INPUT_BUTTON_SELECT | \
        SH_INPUT_BUTTON_L1 | \
        SH_INPUT_BUTTON_R1 | \
        SH_INPUT_BUTTON_L2 | \
        SH_INPUT_BUTTON_R2 | \
        SH_INPUT_BUTTON_L3 | \
        SH_INPUT_BUTTON_R3 | \
        SH_INPUT_BUTTON_TRIANGLE | \
        SH_INPUT_BUTTON_CIRCLE | \
        SH_INPUT_BUTTON_CROSS | \
        SH_INPUT_BUTTON_SQUARE \
    )

#define SH_INPUT_AXIS_MAX INT16_C(32767)
#define SH_INPUT_DEFAULT_DEADZONE UINT16_C(4096)

typedef struct ShInputConfig
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint16_t analog_deadzone;
} ShInputConfig;

#define SH_INPUT_CONFIG_INIT \
    { \
        (uint32_t)sizeof(ShInputConfig), \
        SH_ABI_VERSION_CURRENT, \
        SH_INPUT_DEFAULT_DEADZONE \
    }

typedef struct ShInputState
{
    uint32_t struct_size;
    uint32_t abi_version;
    bool connected;
    ShInputButtons buttons;
    int16_t left_x;
    int16_t left_y;
    int16_t right_x;
    int16_t right_y;
} ShInputState;

#define SH_INPUT_STATE_INIT \
    { \
        (uint32_t)sizeof(ShInputState), \
        SH_ABI_VERSION_CURRENT, \
        false, \
        0u, \
        0, \
        0, \
        0, \
        0 \
    }

typedef struct ShInputSnapshot
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t tick_index;
    bool connected;
    ShInputButtons buttons;
    ShInputButtons pressed;
    ShInputButtons released;
    int16_t left_x;
    int16_t left_y;
    int16_t right_x;
    int16_t right_y;
} ShInputSnapshot;

#define SH_INPUT_SNAPSHOT_INIT \
    { \
        (uint32_t)sizeof(ShInputSnapshot), \
        SH_ABI_VERSION_CURRENT, \
        0u, \
        false, \
        0u, \
        0u, \
        0u, \
        0, \
        0, \
        0, \
        0 \
    }

SH_API int16_t sh_input_apply_deadzone(
    int16_t value,
    uint16_t deadzone);

#ifdef __cplusplus
}
#endif

#endif
