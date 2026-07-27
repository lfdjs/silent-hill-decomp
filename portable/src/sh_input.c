#include "silent_hill/sh_input.h"

#include <stdint.h>

int16_t sh_input_apply_deadzone(
    int16_t value,
    uint16_t deadzone)
{
    int32_t signed_value = (int32_t)value;
    uint32_t magnitude;
    uint32_t remaining;
    uint32_t scaled;
    bool negative = signed_value < 0;

    if (deadzone >= (uint16_t)SH_INPUT_AXIS_MAX)
    {
        return 0;
    }

    if (signed_value < 0)
    {
        signed_value = -signed_value;
    }

    magnitude = (uint32_t)signed_value;

    if (magnitude > (uint32_t)SH_INPUT_AXIS_MAX)
    {
        magnitude = (uint32_t)SH_INPUT_AXIS_MAX;
    }

    if (magnitude <= (uint32_t)deadzone)
    {
        return 0;
    }

    remaining =
        (uint32_t)SH_INPUT_AXIS_MAX -
        (uint32_t)deadzone;

    scaled =
        (
            (
                magnitude -
                (uint32_t)deadzone
            ) *
            (uint32_t)SH_INPUT_AXIS_MAX +
            (remaining / 2u)
        ) /
        remaining;

    if (scaled > (uint32_t)SH_INPUT_AXIS_MAX)
    {
        scaled = (uint32_t)SH_INPUT_AXIS_MAX;
    }

    return negative ?
        (int16_t)(-(int32_t)scaled) :
        (int16_t)scaled;
}
