#ifndef SILENT_HILL_SH_OVERLAY_H
#define SILENT_HILL_SH_OVERLAY_H

#include "silent_hill/sh_memory.h"
#include "silent_hill/sh_result.h"
#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SH_OVERLAY_NAME_MAX 64u
#define SH_OVERLAY_MAX_REGISTERED 128u

typedef uint32_t ShOverlayId;

typedef enum ShOverlaySlot
{
    SH_OVERLAY_SLOT_ENGINE = 0,
    SH_OVERLAY_SLOT_SCREEN = 1,
    SH_OVERLAY_SLOT_MAP = 2,
    SH_OVERLAY_SLOT_COUNT = 3
} ShOverlaySlot;

typedef ShResult (*ShOverlayInitFn)(
    ShRuntime* runtime,
    ShOverlayId overlay_id,
    void* userdata);

typedef void (*ShOverlayTickFn)(
    ShRuntime* runtime,
    ShOverlayId overlay_id,
    uint64_t tick_index,
    void* userdata);

typedef void (*ShOverlayShutdownFn)(
    ShRuntime* runtime,
    ShOverlayId overlay_id,
    void* userdata);

typedef struct ShOverlayDescriptor
{
    uint32_t struct_size;
    uint32_t abi_version;
    ShOverlayId id;
    ShOverlaySlot slot;
    const char* name;
    ShPsxAddress psx_load_address;
    uint32_t memory_size;
    bool clear_memory_on_activate;
    ShOverlayInitFn init;
    ShOverlayTickFn tick;
    ShOverlayShutdownFn shutdown;
    void* userdata;
} ShOverlayDescriptor;

#define SH_OVERLAY_DESCRIPTOR_INIT \
    { \
        (uint32_t)sizeof(ShOverlayDescriptor), \
        SH_ABI_VERSION_CURRENT, \
        0u, \
        SH_OVERLAY_SLOT_ENGINE, \
        NULL, \
        0u, \
        0u, \
        false, \
        NULL, \
        NULL, \
        NULL, \
        NULL \
    }

typedef struct ShOverlayInfo
{
    uint32_t struct_size;
    uint32_t abi_version;
    ShOverlayId id;
    ShOverlaySlot slot;
    ShPsxAddress psx_load_address;
    uint32_t memory_size;
    bool active;
    char name[SH_OVERLAY_NAME_MAX];
} ShOverlayInfo;

#define SH_OVERLAY_INFO_INIT \
    { \
        (uint32_t)sizeof(ShOverlayInfo), \
        SH_ABI_VERSION_CURRENT, \
        0u, \
        SH_OVERLAY_SLOT_ENGINE, \
        0u, \
        0u, \
        false, \
        { 0 } \
    }

typedef struct ShOverlayStats
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t registered_count;
    uint32_t active_count;
    uint64_t activation_count;
    uint64_t deactivation_count;
    uint64_t tick_callback_count;
} ShOverlayStats;

#define SH_OVERLAY_STATS_INIT \
    { \
        (uint32_t)sizeof(ShOverlayStats), \
        SH_ABI_VERSION_CURRENT, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u \
    }

SH_API ShResult sh_runtime_overlay_register(
    ShRuntime* runtime,
    const ShOverlayDescriptor* descriptor);

SH_API ShResult sh_runtime_overlay_unregister(
    ShRuntime* runtime,
    ShOverlayId overlay_id);

SH_API ShResult sh_runtime_overlay_activate(
    ShRuntime* runtime,
    ShOverlayId overlay_id);

SH_API ShResult sh_runtime_overlay_deactivate(
    ShRuntime* runtime,
    ShOverlaySlot slot);

SH_API ShResult sh_runtime_overlay_get_active(
    const ShRuntime* runtime,
    ShOverlaySlot slot,
    ShOverlayInfo* out_info);

SH_API ShResult sh_runtime_overlay_get_stats(
    const ShRuntime* runtime,
    ShOverlayStats* out_stats);

#ifdef __cplusplus
}
#endif

#endif
