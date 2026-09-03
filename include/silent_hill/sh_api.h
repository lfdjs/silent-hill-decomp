#ifndef SILENT_HILL_SH_API_H
#define SILENT_HILL_SH_API_H

#include "silent_hill/sh_audio.h"
#include "silent_hill/sh_game.h"
#include "silent_hill/sh_host.h"
#include "silent_hill/sh_input.h"
#include "silent_hill/sh_io.h"
#include "silent_hill/sh_memory.h"
#include "silent_hill/sh_overlay.h"
#include "silent_hill/sh_presentation.h"
#include "silent_hill/sh_result.h"
#include "silent_hill/sh_rng.h"
#include "silent_hill/sh_timing.h"
#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif


typedef struct ShRuntimeConfig
{
    uint32_t struct_size;
    uint32_t abi_version;
    const ShHostServices* host;
    uint32_t initial_rng_seed;
    const ShTimingConfig* timing;
    const ShInputConfig* input;
    const ShMemoryConfig* memory;
} ShRuntimeConfig;

#define SH_RUNTIME_CONFIG_INIT \
    { \
        (uint32_t)sizeof(ShRuntimeConfig), \
        SH_ABI_VERSION_CURRENT, \
        NULL, \
        0u, \
        NULL, \
        NULL, \
        NULL \
    }

typedef struct ShRuntimeStats
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t update_count;
    uint64_t total_elapsed_us;
    bool booted;
    uint64_t tick_count;
    uint64_t accepted_elapsed_us;
    uint64_t dropped_elapsed_us;
    uint64_t paused_elapsed_us;
    uint32_t interpolation_units;
    uint32_t last_advance_ticks;
    bool paused;
} ShRuntimeStats;

#define SH_RUNTIME_STATS_INIT \
    { \
        (uint32_t)sizeof(ShRuntimeStats), \
        SH_ABI_VERSION_CURRENT, \
        0u, \
        0u, \
        false, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        false \
    }

SH_API uint32_t sh_api_version(void);

SH_API ShResult sh_runtime_create(
    const ShRuntimeConfig* config,
    ShRuntime** out_runtime);

SH_API void sh_runtime_destroy(ShRuntime* runtime);

SH_API ShResult sh_runtime_boot(ShRuntime* runtime);

SH_API ShResult sh_runtime_advance(
    ShRuntime* runtime,
    uint64_t elapsed_us,
    ShAdvanceInfo* out_info);

SH_API ShResult sh_runtime_update(
    ShRuntime* runtime,
    uint64_t elapsed_us);

SH_API ShResult sh_runtime_set_paused(
    ShRuntime* runtime,
    bool paused);

SH_API ShResult sh_runtime_step(
    ShRuntime* runtime,
    ShAdvanceInfo* out_info);

SH_API ShResult sh_runtime_get_stats(
    const ShRuntime* runtime,
    ShRuntimeStats* out_stats);

SH_API ShResult sh_runtime_submit_input(
    ShRuntime* runtime,
    const ShInputState* input);

SH_API ShResult sh_runtime_get_input(
    const ShRuntime* runtime,
    ShInputSnapshot* out_snapshot);

SH_API ShResult sh_runtime_file_stat(
    const ShRuntime* runtime,
    ShFileDomain domain,
    const char* path,
    ShFileInfo* out_info);

SH_API ShResult sh_runtime_file_read(
    const ShRuntime* runtime,
    ShFileDomain domain,
    const char* path,
    uint64_t offset,
    void* destination,
    size_t size,
    size_t* out_read);

SH_API ShResult sh_runtime_storage_write_atomic(
    const ShRuntime* runtime,
    const char* path,
    const void* source,
    size_t size);

SH_API ShResult sh_runtime_storage_remove(
    const ShRuntime* runtime,
    const char* path);

#ifdef __cplusplus
}
#endif

#endif
