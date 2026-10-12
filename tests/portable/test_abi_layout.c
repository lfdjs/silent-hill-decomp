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
    offsetof(ShMemoryConfig, struct_size) == 0u,
    "struct_size must be the first memory config field");

_Static_assert(
    offsetof(ShMemoryStats, struct_size) == 0u,
    "struct_size must be the first memory stats field");

_Static_assert(
    offsetof(ShOverlayDescriptor, struct_size) == 0u,
    "struct_size must be the first overlay descriptor field");

_Static_assert(
    offsetof(ShOverlayInfo, struct_size) == 0u,
    "struct_size must be the first overlay info field");

_Static_assert(
    offsetof(ShOverlayStats, struct_size) == 0u,
    "struct_size must be the first overlay stats field");

_Static_assert(
    offsetof(ShGameBootSignals, struct_size) == 0u,
    "struct_size must be the first game boot signal field");

_Static_assert(
    offsetof(ShGameKonamiSignals, struct_size) == 0u,
    "struct_size must be the first Konami signal field");

_Static_assert(
    offsetof(ShGameKcetSignals, struct_size) == 0u,
    "struct_size must be the first KCET signal field");

_Static_assert(
    offsetof(ShGameSnapshot, struct_size) == 0u,
    "struct_size must be the first game snapshot field");

_Static_assert(
    offsetof(ShAudioCommand, struct_size) == 0u,
    "struct_size must be the first audio command field");

_Static_assert(
    offsetof(ShAudioStats, struct_size) == 0u,
    "struct_size must be the first audio stats field");

_Static_assert(
    offsetof(ShPresentationCommand, struct_size) == 0u,
    "struct_size must be the first presentation command field");

_Static_assert(
    offsetof(ShPresentationStats, struct_size) == 0u,
    "struct_size must be the first presentation stats field");

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
    ShMemoryConfig memory_config = SH_MEMORY_CONFIG_INIT;
    ShMemoryStats memory_stats = SH_MEMORY_STATS_INIT;
    ShOverlayDescriptor overlay_descriptor = SH_OVERLAY_DESCRIPTOR_INIT;
    ShOverlayInfo overlay_info = SH_OVERLAY_INFO_INIT;
    ShOverlayStats overlay_stats = SH_OVERLAY_STATS_INIT;
    ShGameBootSignals game_signals = SH_GAME_BOOT_SIGNALS_INIT;
    ShGameKonamiSignals konami_signals = SH_GAME_KONAMI_SIGNALS_INIT;
    ShGameKcetSignals kcet_signals = SH_GAME_KCET_SIGNALS_INIT;
    ShGameSnapshot game_snapshot = SH_GAME_SNAPSHOT_INIT;
    ShAudioCommand audio_command = SH_AUDIO_COMMAND_INIT;
    ShAudioStats audio_stats = SH_AUDIO_STATS_INIT;
    ShPresentationCommand presentation_command = SH_PRESENTATION_COMMAND_INIT;
    ShPresentationStats presentation_stats = SH_PRESENTATION_STATS_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;

    assert(host.struct_size == (uint32_t)sizeof(host));
    assert(timing.struct_size == (uint32_t)sizeof(timing));
    assert(input_config.struct_size == (uint32_t)sizeof(input_config));
    assert(input_state.struct_size == (uint32_t)sizeof(input_state));
    assert(snapshot.struct_size == (uint32_t)sizeof(snapshot));
    assert(file_info.struct_size == (uint32_t)sizeof(file_info));
    assert(memory_config.struct_size == (uint32_t)sizeof(memory_config));
    assert(memory_stats.struct_size == (uint32_t)sizeof(memory_stats));
    assert(overlay_descriptor.struct_size ==
        (uint32_t)sizeof(overlay_descriptor));
    assert(overlay_info.struct_size == (uint32_t)sizeof(overlay_info));
    assert(overlay_stats.struct_size == (uint32_t)sizeof(overlay_stats));
    assert(game_signals.struct_size == (uint32_t)sizeof(game_signals));
    assert(konami_signals.struct_size == (uint32_t)sizeof(konami_signals));
    assert(kcet_signals.struct_size == (uint32_t)sizeof(kcet_signals));
    assert(game_snapshot.struct_size == (uint32_t)sizeof(game_snapshot));
    assert(audio_command.struct_size == (uint32_t)sizeof(audio_command));
    assert(audio_stats.struct_size == (uint32_t)sizeof(audio_stats));
    assert(presentation_command.struct_size == (uint32_t)sizeof(presentation_command));
    assert(presentation_stats.struct_size == (uint32_t)sizeof(presentation_stats));
    assert(config.struct_size == (uint32_t)sizeof(config));
    assert(advance.struct_size == (uint32_t)sizeof(advance));
    assert(stats.struct_size == (uint32_t)sizeof(stats));

    assert(host.abi_version == SH_ABI_VERSION_CURRENT);
    assert(timing.abi_version == SH_ABI_VERSION_CURRENT);
    assert(input_config.abi_version == SH_ABI_VERSION_CURRENT);
    assert(input_state.abi_version == SH_ABI_VERSION_CURRENT);
    assert(snapshot.abi_version == SH_ABI_VERSION_CURRENT);
    assert(file_info.abi_version == SH_ABI_VERSION_CURRENT);
    assert(memory_config.abi_version == SH_ABI_VERSION_CURRENT);
    assert(memory_stats.abi_version == SH_ABI_VERSION_CURRENT);
    assert(overlay_descriptor.abi_version == SH_ABI_VERSION_CURRENT);
    assert(overlay_info.abi_version == SH_ABI_VERSION_CURRENT);
    assert(overlay_stats.abi_version == SH_ABI_VERSION_CURRENT);
    assert(game_signals.abi_version == SH_ABI_VERSION_CURRENT);
    assert(konami_signals.abi_version == SH_ABI_VERSION_CURRENT);
    assert(game_snapshot.abi_version == SH_ABI_VERSION_CURRENT);
    assert(audio_command.abi_version == SH_ABI_VERSION_CURRENT);
    assert(audio_stats.abi_version == SH_ABI_VERSION_CURRENT);
    assert(presentation_command.abi_version == SH_ABI_VERSION_CURRENT);
    assert(presentation_stats.abi_version == SH_ABI_VERSION_CURRENT);
    assert(config.abi_version == SH_ABI_VERSION_CURRENT);
    assert(advance.abi_version == SH_ABI_VERSION_CURRENT);
    assert(stats.abi_version == SH_ABI_VERSION_CURRENT);

    assert(SH_TICKS_PER_SECOND == 60u);
    assert(SH_INTERPOLATION_UNITS_PER_TICK == 1000000u);
    assert((SH_INPUT_BUTTON_KNOWN_MASK >> 16u) == 0u);
    assert(SH_PSX_RAM_BASE == UINT32_C(0x80000000));
    assert(SH_PSX_RAM_SIZE == UINT32_C(0x00200000));
    assert(SH_OVERLAY_SLOT_COUNT == 3);
    assert(SH_GAME_STATE_INIT == 0);
    assert(SH_GAME_STATE_KONAMI_LOGO == 1);
    assert(SH_GAME_STATE_IN_GAME == 11);
    assert(SH_SYS_STATE_GAMEPLAY == 0);
    assert(SH_SYS_STATE_INVALID == 15);

    return 0;
}
