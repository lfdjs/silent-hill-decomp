#ifndef SILENT_HILL_SH_PRESENTATION_H
#define SILENT_HILL_SH_PRESENTATION_H

#include "silent_hill/sh_result.h"
#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum ShPresentationCommandType
{
    SH_PRESENTATION_COMMAND_NONE = 0,
    SH_PRESENTATION_COMMAND_CONFIGURE_DISPLAY = 1,
    SH_PRESENTATION_COMMAND_FADE_START = 2,
    SH_PRESENTATION_COMMAND_DRAW_BOOT_LOGO = 3,
    SH_PRESENTATION_COMMAND_PRESENT_FRAME = 4
} ShPresentationCommandType;

typedef enum ShBootLogo
{
    SH_BOOT_LOGO_KONAMI = 0,
    SH_BOOT_LOGO_KCET = 1
} ShBootLogo;

typedef struct ShPresentationCommand
{
    uint32_t struct_size;
    uint32_t abi_version;
    ShPresentationCommandType type;
    uint64_t tick_index;
    uint16_t width;
    uint16_t height;
    bool interlaced;
    bool fade_arg0;
    bool fade_arg1;
    bool fade_arg2;
    bool fade_timestep_valid;
    int32_t fade_timestep_q12;
    ShBootLogo boot_logo;
} ShPresentationCommand;

#define SH_PRESENTATION_COMMAND_INIT \
    { \
        (uint32_t)sizeof(ShPresentationCommand), \
        SH_ABI_VERSION_CURRENT, \
        SH_PRESENTATION_COMMAND_NONE, \
        0u, \
        0u, \
        0u, \
        false, \
        false, \
        false, \
        false, \
        false, \
        0, \
        SH_BOOT_LOGO_KONAMI \
    }

typedef struct ShPresentationStats
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t pending_count;
    uint32_t capacity;
    uint64_t emitted_count;
    uint64_t popped_count;
    uint64_t dropped_count;
} ShPresentationStats;

#define SH_PRESENTATION_STATS_INIT \
    { \
        (uint32_t)sizeof(ShPresentationStats), \
        SH_ABI_VERSION_CURRENT, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u \
    }

SH_API const char* sh_presentation_command_name(
    ShPresentationCommandType type);

SH_API ShResult sh_runtime_presentation_pop(
    ShRuntime* runtime,
    ShPresentationCommand* out_command);

SH_API ShResult sh_runtime_presentation_get_stats(
    const ShRuntime* runtime,
    ShPresentationStats* out_stats);

#ifdef __cplusplus
}
#endif

#endif
