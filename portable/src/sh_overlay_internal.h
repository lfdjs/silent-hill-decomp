#ifndef SILENT_HILL_SH_OVERLAY_INTERNAL_H
#define SILENT_HILL_SH_OVERLAY_INTERNAL_H

#include "silent_hill/sh_overlay.h"

typedef struct ShOverlayRecord
{
    bool used;
    ShOverlayId id;
    ShOverlaySlot slot;
    ShPsxAddress psx_load_address;
    uint32_t memory_size;
    bool clear_memory_on_activate;
    ShOverlayInitFn init;
    ShOverlayTickFn tick;
    ShOverlayShutdownFn shutdown;
    void* userdata;
    char name[SH_OVERLAY_NAME_MAX];
} ShOverlayRecord;

typedef struct ShOverlayManager
{
    ShOverlayRecord records[SH_OVERLAY_MAX_REGISTERED];
    int32_t active_record[SH_OVERLAY_SLOT_COUNT];
    uint32_t registered_count;
    uint64_t activation_count;
    uint64_t deactivation_count;
    uint64_t tick_callback_count;
} ShOverlayManager;

void sh_overlay_manager_init(ShOverlayManager* manager);

void sh_overlay_manager_destroy(
    ShOverlayManager* manager,
    ShRuntime* runtime);

void sh_overlay_manager_tick(
    ShOverlayManager* manager,
    ShRuntime* runtime,
    uint64_t tick_index);

#endif
