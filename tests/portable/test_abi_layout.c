#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stddef.h>
#include <stdint.h>

_Static_assert(sizeof(uint8_t) == 1u, "uint8_t must be 8-bit");
_Static_assert(sizeof(uint16_t) == 2u, "uint16_t must be 16-bit");
_Static_assert(sizeof(uint32_t) == 4u, "uint32_t must be 32-bit");
_Static_assert(sizeof(uint64_t) == 8u, "uint64_t must be 64-bit");

_Static_assert(
    offsetof(ShHostServices, struct_size) == 0u,
    "struct_size must be the first host field");

_Static_assert(
    offsetof(ShHostServices, abi_version) == sizeof(uint32_t),
    "abi_version must follow struct_size");

_Static_assert(
    offsetof(ShTimingConfig, struct_size) == 0u,
    "struct_size must be the first timing field");

_Static_assert(
    offsetof(ShInputConfig, struct_size) == 0u,
    "struct_size must be the first input config field");

_Static_assert(
    offsetof(ShInputState, struct_size) == 0u,
    "struct_size must be the first input state field");

_Static_assert(
    offsetof(ShInputSnapshot, struct_size) == 0u,
    "struct_size must be the first input snapshot field");

_Static_assert(
    offsetof(ShFileInfo, struct_size) == 0u,
    "struct_size must be the first file info field");

_Static_assert(
    offsetof(ShRuntimeConfig, struct_size) == 0u,
    "struct_size must be the first config field");

_Static_assert(
    offsetof(ShRuntimeConfig, abi_version) == sizeof(uint32_t),
    "abi_version must follow struct_size");

_Static_assert(
    offsetof(ShAdvanceInfo, struct_size) == 0u,
    "struct_size must be the first advance field");

_Static_assert(
    offsetof(ShRuntimeStats, struct_size) == 0u,
    "struct_size must be the first stats field");

_Static_assert(
    sizeof(ShRng) == sizeof(uint32_t),
    "ShRng must contain exactly one 32-bit seed");

int main(void)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShInputConfig input_config = SH_INPUT_CONFIG_INIT;
    ShInputState input_state = SH_INPUT_STATE_INIT;
    ShInputSnapshot snapshot = SH_INPUT_SNAPSHOT_INIT;
    ShFileInfo file_info = SH_FILE_INFO_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;

    assert(host.struct_size == (uint32_t)sizeof(host));
    assert(timing.struct_size == (uint32_t)sizeof(timing));
    assert(input_config.struct_size == (uint32_t)sizeof(input_config));
    assert(input_state.struct_size == (uint32_t)sizeof(input_state));
    assert(snapshot.struct_size == (uint32_t)sizeof(snapshot));
    assert(file_info.struct_size == (uint32_t)sizeof(file_info));
    assert(config.struct_size == (uint32_t)sizeof(config));
    assert(advance.struct_size == (uint32_t)sizeof(advance));
    assert(stats.struct_size == (uint32_t)sizeof(stats));

    assert(host.abi_version == SH_ABI_VERSION_CURRENT);
    assert(timing.abi_version == SH_ABI_VERSION_CURRENT);
    assert(input_config.abi_version == SH_ABI_VERSION_CURRENT);
    assert(input_state.abi_version == SH_ABI_VERSION_CURRENT);
    assert(snapshot.abi_version == SH_ABI_VERSION_CURRENT);
    assert(file_info.abi_version == SH_ABI_VERSION_CURRENT);
    assert(config.abi_version == SH_ABI_VERSION_CURRENT);
    assert(advance.abi_version == SH_ABI_VERSION_CURRENT);
    assert(stats.abi_version == SH_ABI_VERSION_CURRENT);

    assert(SH_TICKS_PER_SECOND == 60u);
    assert(SH_INTERPOLATION_UNITS_PER_TICK == 1000000u);
    assert((SH_INPUT_BUTTON_KNOWN_MASK >> 16u) == 0u);

    return 0;
}
