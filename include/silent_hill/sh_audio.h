#ifndef SILENT_HILL_SH_AUDIO_H
#define SILENT_HILL_SH_AUDIO_H

#include "silent_hill/sh_result.h"
#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum ShAudioCommandType
{
    SH_AUDIO_COMMAND_NONE = 0,
    SH_AUDIO_COMMAND_TASK = 1
} ShAudioCommandType;

typedef struct ShAudioCommand
{
    uint32_t struct_size;
    uint32_t abi_version;
    ShAudioCommandType type;
    uint64_t tick_index;
    uint16_t task_id;
    uint16_t reserved;
} ShAudioCommand;

#define SH_AUDIO_COMMAND_INIT \
    { \
        (uint32_t)sizeof(ShAudioCommand), \
        SH_ABI_VERSION_CURRENT, \
        SH_AUDIO_COMMAND_NONE, \
        0u, \
        0u, \
        0u \
    }

typedef struct ShAudioStats
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t pending_count;
    uint32_t capacity;
    uint64_t emitted_count;
    uint64_t popped_count;
    uint64_t dropped_count;
} ShAudioStats;

#define SH_AUDIO_STATS_INIT \
    { \
        (uint32_t)sizeof(ShAudioStats), \
        SH_ABI_VERSION_CURRENT, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u \
    }

SH_API const char* sh_audio_command_name(ShAudioCommandType type);

SH_API ShResult sh_runtime_audio_pop(
    ShRuntime* runtime,
    ShAudioCommand* out_command);

SH_API ShResult sh_runtime_audio_get_stats(
    const ShRuntime* runtime,
    ShAudioStats* out_stats);

#ifdef __cplusplus
}
#endif

#endif
