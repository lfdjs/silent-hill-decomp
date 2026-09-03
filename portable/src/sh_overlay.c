#include "sh_runtime_internal.h"

#include <limits.h>
#include <string.h>

static bool sh_overlay_slot_valid(ShOverlaySlot slot)
{
    return slot >= SH_OVERLAY_SLOT_ENGINE &&
        slot < SH_OVERLAY_SLOT_COUNT;
}

static int32_t sh_overlay_find_record(
    const ShOverlayManager* manager,
    ShOverlayId overlay_id)
{
    uint32_t idx;

    for (idx = 0u; idx < SH_OVERLAY_MAX_REGISTERED; idx++)
    {
        if (manager->records[idx].used &&
            manager->records[idx].id == overlay_id)
        {
            return (int32_t)idx;
        }
    }

    return -1;
}

static int32_t sh_overlay_find_free_record(
    const ShOverlayManager* manager)
{
    uint32_t idx;

    for (idx = 0u; idx < SH_OVERLAY_MAX_REGISTERED; idx++)
    {
        if (!manager->records[idx].used)
        {
            return (int32_t)idx;
        }
    }

    return -1;
}

static bool sh_overlay_name_valid(const char* name)
{
    size_t length;

    if (name == NULL || name[0] == '\0')
    {
        return false;
    }

    length = strlen(name);
    return length < (size_t)SH_OVERLAY_NAME_MAX;
}

static bool sh_overlay_descriptor_valid(
    const ShRuntime* runtime,
    const ShOverlayDescriptor* descriptor)
{
    if (descriptor == NULL)
    {
        return false;
    }

    if (!sh_runtime_size_is_supported(
            descriptor->struct_size,
            sizeof(ShOverlayDescriptor)))
    {
        return false;
    }

    if (descriptor->abi_version != SH_ABI_VERSION_CURRENT ||
        descriptor->id == 0u ||
        !sh_overlay_slot_valid(descriptor->slot) ||
        !sh_overlay_name_valid(descriptor->name))
    {
        return false;
    }

    if (descriptor->memory_size == 0u)
    {
        return descriptor->psx_load_address == 0u;
    }

    return sh_memory_range_valid(
        &runtime->memory,
        descriptor->psx_load_address,
        descriptor->memory_size);
}

static void sh_overlay_record_to_info(
    const ShOverlayRecord* record,
    bool active,
    ShOverlayInfo* out_info)
{
    out_info->struct_size = (uint32_t)sizeof(ShOverlayInfo);
    out_info->abi_version = SH_ABI_VERSION_CURRENT;
    out_info->id = record->id;
    out_info->slot = record->slot;
    out_info->psx_load_address = record->psx_load_address;
    out_info->memory_size = record->memory_size;
    out_info->active = active;

    memcpy(
        out_info->name,
        record->name,
        sizeof(out_info->name));
}

void sh_overlay_manager_init(ShOverlayManager* manager)
{
    uint32_t slot;

    memset(manager, 0, sizeof(*manager));

    for (slot = 0u; slot < (uint32_t)SH_OVERLAY_SLOT_COUNT; slot++)
    {
        manager->active_record[slot] = -1;
    }
}

static void sh_overlay_deactivate_slot_internal(
    ShOverlayManager* manager,
    ShRuntime* runtime,
    ShOverlaySlot slot)
{
    int32_t record_index;
    ShOverlayRecord* record;

    record_index = manager->active_record[(uint32_t)slot];

    if (record_index < 0)
    {
        return;
    }

    record = &manager->records[(uint32_t)record_index];

    if (record->shutdown != NULL)
    {
        record->shutdown(runtime, record->id, record->userdata);
    }

    manager->active_record[(uint32_t)slot] = -1;
    manager->deactivation_count++;
}

void sh_overlay_manager_destroy(
    ShOverlayManager* manager,
    ShRuntime* runtime)
{
    int32_t slot;

    if (manager == NULL)
    {
        return;
    }

    for (slot = (int32_t)SH_OVERLAY_SLOT_COUNT - 1; slot >= 0; slot--)
    {
        sh_overlay_deactivate_slot_internal(
            manager,
            runtime,
            (ShOverlaySlot)slot);
    }

    memset(manager, 0, sizeof(*manager));
}

void sh_overlay_manager_tick(
    ShOverlayManager* manager,
    ShRuntime* runtime,
    uint64_t tick_index)
{
    uint32_t slot;

    for (slot = 0u; slot < (uint32_t)SH_OVERLAY_SLOT_COUNT; slot++)
    {
        int32_t record_index = manager->active_record[slot];

        if (record_index >= 0)
        {
            ShOverlayRecord* record =
                &manager->records[(uint32_t)record_index];

            if (record->tick != NULL)
            {
                record->tick(
                    runtime,
                    record->id,
                    tick_index,
                    record->userdata);

                manager->tick_callback_count++;
            }
        }
    }
}

ShResult sh_runtime_overlay_register(
    ShRuntime* runtime,
    const ShOverlayDescriptor* descriptor)
{
    ShOverlayManager* manager;
    ShOverlayRecord* record;
    int32_t record_index;

    if (runtime == NULL || descriptor == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    if (!sh_overlay_descriptor_valid(runtime, descriptor))
    {
        return descriptor->abi_version != SH_ABI_VERSION_CURRENT ?
            SH_RESULT_UNSUPPORTED_VERSION :
            SH_RESULT_INVALID_ARGUMENT;
    }

    manager = &runtime->overlays;

    if (sh_overlay_find_record(manager, descriptor->id) >= 0)
    {
        return SH_RESULT_INVALID_STATE;
    }

    if (manager->registered_count >= SH_OVERLAY_MAX_REGISTERED)
    {
        return SH_RESULT_BUFFER_TOO_SMALL;
    }

    record_index = sh_overlay_find_free_record(manager);

    if (record_index < 0)
    {
        return SH_RESULT_BUFFER_TOO_SMALL;
    }

    record = &manager->records[(uint32_t)record_index];
    memset(record, 0, sizeof(*record));

    record->used = true;
    record->id = descriptor->id;
    record->slot = descriptor->slot;
    record->psx_load_address = descriptor->psx_load_address;
    record->memory_size = descriptor->memory_size;
    record->clear_memory_on_activate =
        descriptor->clear_memory_on_activate;
    record->init = descriptor->init;
    record->tick = descriptor->tick;
    record->shutdown = descriptor->shutdown;
    record->userdata = descriptor->userdata;

    memcpy(
        record->name,
        descriptor->name,
        strlen(descriptor->name) + 1u);

    manager->registered_count++;
    return SH_RESULT_OK;
}

ShResult sh_runtime_overlay_unregister(
    ShRuntime* runtime,
    ShOverlayId overlay_id)
{
    ShOverlayManager* manager;
    int32_t record_index;
    ShOverlayRecord* record;

    if (runtime == NULL || overlay_id == 0u)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    manager = &runtime->overlays;
    record_index = sh_overlay_find_record(manager, overlay_id);

    if (record_index < 0)
    {
        return SH_RESULT_NOT_FOUND;
    }

    record = &manager->records[(uint32_t)record_index];

    if (manager->active_record[(uint32_t)record->slot] == record_index)
    {
        return SH_RESULT_INVALID_STATE;
    }

    memset(record, 0, sizeof(*record));
    manager->registered_count--;

    return SH_RESULT_OK;
}

ShResult sh_runtime_overlay_activate(
    ShRuntime* runtime,
    ShOverlayId overlay_id)
{
    ShOverlayManager* manager;
    ShOverlayRecord* record;
    int32_t record_index;
    ShResult init_result;

    if (runtime == NULL || overlay_id == 0u)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    manager = &runtime->overlays;
    record_index = sh_overlay_find_record(manager, overlay_id);

    if (record_index < 0)
    {
        return SH_RESULT_NOT_FOUND;
    }

    record = &manager->records[(uint32_t)record_index];

    if (manager->active_record[(uint32_t)record->slot] == record_index)
    {
        return SH_RESULT_OK;
    }

    sh_overlay_deactivate_slot_internal(
        manager,
        runtime,
        record->slot);

    if (record->clear_memory_on_activate &&
        record->memory_size > 0u)
    {
        ShResult clear_result = sh_memory_fill_internal(
            &runtime->memory,
            record->psx_load_address,
            0u,
            record->memory_size);

        if (clear_result != SH_RESULT_OK)
        {
            return clear_result;
        }
    }

    manager->active_record[(uint32_t)record->slot] = record_index;

    if (record->init != NULL)
    {
        init_result = record->init(
            runtime,
            record->id,
            record->userdata);

        if (init_result != SH_RESULT_OK)
        {
            manager->active_record[(uint32_t)record->slot] = -1;
            return init_result;
        }
    }

    manager->activation_count++;
    return SH_RESULT_OK;
}

ShResult sh_runtime_overlay_deactivate(
    ShRuntime* runtime,
    ShOverlaySlot slot)
{
    if (runtime == NULL || !sh_overlay_slot_valid(slot))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    sh_overlay_deactivate_slot_internal(
        &runtime->overlays,
        runtime,
        slot);

    return SH_RESULT_OK;
}

ShResult sh_runtime_overlay_get_active(
    const ShRuntime* runtime,
    ShOverlaySlot slot,
    ShOverlayInfo* out_info)
{
    int32_t record_index;
    const ShOverlayRecord* record;

    if (runtime == NULL || out_info == NULL ||
        !sh_overlay_slot_valid(slot))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    if (!sh_runtime_size_is_supported(
            out_info->struct_size,
            sizeof(ShOverlayInfo)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_info->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    record_index = runtime->overlays.active_record[(uint32_t)slot];

    if (record_index < 0)
    {
        return SH_RESULT_NOT_FOUND;
    }

    record = &runtime->overlays.records[(uint32_t)record_index];
    sh_overlay_record_to_info(record, true, out_info);

    return SH_RESULT_OK;
}

ShResult sh_runtime_overlay_get_stats(
    const ShRuntime* runtime,
    ShOverlayStats* out_stats)
{
    uint32_t slot;
    uint32_t active_count = 0u;

    if (runtime == NULL || out_stats == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    if (!sh_runtime_size_is_supported(
            out_stats->struct_size,
            sizeof(ShOverlayStats)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_stats->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    for (slot = 0u; slot < (uint32_t)SH_OVERLAY_SLOT_COUNT; slot++)
    {
        if (runtime->overlays.active_record[slot] >= 0)
        {
            active_count++;
        }
    }

    out_stats->struct_size = (uint32_t)sizeof(ShOverlayStats);
    out_stats->abi_version = SH_ABI_VERSION_CURRENT;
    out_stats->registered_count = runtime->overlays.registered_count;
    out_stats->active_count = active_count;
    out_stats->activation_count = runtime->overlays.activation_count;
    out_stats->deactivation_count = runtime->overlays.deactivation_count;
    out_stats->tick_callback_count = runtime->overlays.tick_callback_count;

    return SH_RESULT_OK;
}
