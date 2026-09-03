#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stdint.h>
#include <string.h>

typedef struct OverlayProbe
{
    uint32_t init_count;
    uint32_t tick_count;
    uint32_t shutdown_count;
    uint64_t last_tick;
    ShOverlayId last_id;
    uint8_t init_marker;
} OverlayProbe;

static ShResult probe_init(
    ShRuntime* runtime,
    ShOverlayId overlay_id,
    void* userdata)
{
    OverlayProbe* probe = (OverlayProbe*)userdata;

    assert(runtime != NULL);
    assert(probe != NULL);

    probe->init_count++;
    probe->last_id = overlay_id;

    if (probe->init_marker != 0u)
    {
        assert(
            sh_runtime_memory_write(
                runtime,
                SH_PSX_RAM_BASE + UINT32_C(0x1000),
                &probe->init_marker,
                1u) == SH_RESULT_OK);
    }

    return SH_RESULT_OK;
}

static void probe_tick(
    ShRuntime* runtime,
    ShOverlayId overlay_id,
    uint64_t tick_index,
    void* userdata)
{
    OverlayProbe* probe = (OverlayProbe*)userdata;

    assert(runtime != NULL);
    assert(probe != NULL);

    probe->tick_count++;
    probe->last_tick = tick_index;
    probe->last_id = overlay_id;
}

static void probe_shutdown(
    ShRuntime* runtime,
    ShOverlayId overlay_id,
    void* userdata)
{
    OverlayProbe* probe = (OverlayProbe*)userdata;

    assert(runtime != NULL);
    assert(probe != NULL);

    probe->shutdown_count++;
    probe->last_id = overlay_id;
}

static ShRuntime* create_runtime(void)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntime* runtime = NULL;

    config.host = &host;

    assert(sh_runtime_create(&config, &runtime) == SH_RESULT_OK);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);

    return runtime;
}

static ShOverlayDescriptor make_descriptor(
    ShOverlayId id,
    ShOverlaySlot slot,
    const char* name,
    OverlayProbe* probe)
{
    ShOverlayDescriptor descriptor = SH_OVERLAY_DESCRIPTOR_INIT;

    descriptor.id = id;
    descriptor.slot = slot;
    descriptor.name = name;
    descriptor.psx_load_address =
        SH_PSX_RAM_BASE + UINT32_C(0x1000);
    descriptor.memory_size = UINT32_C(0x100);
    descriptor.clear_memory_on_activate = true;
    descriptor.init = probe_init;
    descriptor.tick = probe_tick;
    descriptor.shutdown = probe_shutdown;
    descriptor.userdata = probe;

    return descriptor;
}

static void test_registration_activation_and_ticks(void)
{
    ShRuntime* runtime = create_runtime();
    OverlayProbe engine_probe = { 0u, 0u, 0u, 0u, 0u, UINT8_C(0x11) };
    OverlayProbe map_probe = { 0u, 0u, 0u, 0u, 0u, UINT8_C(0x22) };
    ShOverlayDescriptor engine = make_descriptor(
        1u,
        SH_OVERLAY_SLOT_ENGINE,
        "BODYPROG",
        &engine_probe);
    ShOverlayDescriptor map = make_descriptor(
        2u,
        SH_OVERLAY_SLOT_MAP,
        "MAP_TEST",
        &map_probe);
    ShOverlayInfo info = SH_OVERLAY_INFO_INIT;
    ShOverlayStats stats = SH_OVERLAY_STATS_INIT;
    uint8_t marker = 0u;

    assert(
        sh_runtime_overlay_register(runtime, &engine) ==
        SH_RESULT_OK);
    assert(
        sh_runtime_overlay_register(runtime, &map) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_overlay_register(runtime, &engine) ==
        SH_RESULT_INVALID_STATE);

    assert(
        sh_runtime_overlay_activate(runtime, 1u) ==
        SH_RESULT_OK);
    assert(engine_probe.init_count == 1u);

    assert(
        sh_runtime_memory_read(
            runtime,
            SH_PSX_RAM_BASE + UINT32_C(0x1000),
            &marker,
            1u) == SH_RESULT_OK);
    assert(marker == UINT8_C(0x11));

    assert(
        sh_runtime_overlay_activate(runtime, 2u) ==
        SH_RESULT_OK);
    assert(map_probe.init_count == 1u);

    assert(
        sh_runtime_overlay_get_active(
            runtime,
            SH_OVERLAY_SLOT_ENGINE,
            &info) == SH_RESULT_OK);
    assert(info.id == 1u);
    assert(info.active);
    assert(strcmp(info.name, "BODYPROG") == 0);

    assert(
        sh_runtime_update(runtime, UINT64_C(16667)) ==
        SH_RESULT_OK);

    assert(engine_probe.tick_count == 1u);
    assert(map_probe.tick_count == 1u);
    assert(engine_probe.last_tick == UINT64_C(1));
    assert(map_probe.last_tick == UINT64_C(1));

    assert(
        sh_runtime_overlay_get_stats(runtime, &stats) ==
        SH_RESULT_OK);

    assert(stats.registered_count == 2u);
    assert(stats.active_count == 2u);
    assert(stats.activation_count == UINT64_C(2));
    assert(stats.deactivation_count == UINT64_C(0));
    assert(stats.tick_callback_count == UINT64_C(2));

    assert(
        sh_runtime_overlay_unregister(runtime, 1u) ==
        SH_RESULT_INVALID_STATE);

    assert(
        sh_runtime_overlay_deactivate(
            runtime,
            SH_OVERLAY_SLOT_ENGINE) == SH_RESULT_OK);
    assert(engine_probe.shutdown_count == 1u);

    assert(
        sh_runtime_overlay_unregister(runtime, 1u) ==
        SH_RESULT_OK);

    sh_runtime_destroy(runtime);

    assert(map_probe.shutdown_count == 1u);
}

static void test_replacement_and_memory_clear(void)
{
    ShRuntime* runtime = create_runtime();
    OverlayProbe first_probe = { 0u, 0u, 0u, 0u, 0u, UINT8_C(0x33) };
    OverlayProbe second_probe = { 0u, 0u, 0u, 0u, 0u, 0u };
    ShOverlayDescriptor first = make_descriptor(
        10u,
        SH_OVERLAY_SLOT_SCREEN,
        "FIRST",
        &first_probe);
    ShOverlayDescriptor second = make_descriptor(
        11u,
        SH_OVERLAY_SLOT_SCREEN,
        "SECOND",
        &second_probe);
    uint8_t marker = UINT8_C(0xFF);

    assert(sh_runtime_overlay_register(runtime, &first) == SH_RESULT_OK);
    assert(sh_runtime_overlay_register(runtime, &second) == SH_RESULT_OK);

    assert(sh_runtime_overlay_activate(runtime, 10u) == SH_RESULT_OK);
    assert(first_probe.init_count == 1u);

    assert(sh_runtime_overlay_activate(runtime, 11u) == SH_RESULT_OK);
    assert(first_probe.shutdown_count == 1u);
    assert(second_probe.init_count == 1u);

    assert(
        sh_runtime_memory_read(
            runtime,
            SH_PSX_RAM_BASE + UINT32_C(0x1000),
            &marker,
            1u) == SH_RESULT_OK);
    assert(marker == 0u);

    sh_runtime_destroy(runtime);
    assert(second_probe.shutdown_count == 1u);
}

static void test_invalid_descriptor_range(void)
{
    ShRuntime* runtime = create_runtime();
    OverlayProbe probe = { 0u, 0u, 0u, 0u, 0u, 0u };
    ShOverlayDescriptor descriptor = make_descriptor(
        20u,
        SH_OVERLAY_SLOT_MAP,
        "INVALID_RANGE",
        &probe);

    descriptor.psx_load_address =
        SH_PSX_RAM_BASE + SH_PSX_RAM_SIZE - UINT32_C(0x10);
    descriptor.memory_size = UINT32_C(0x100);

    assert(
        sh_runtime_overlay_register(runtime, &descriptor) ==
        SH_RESULT_INVALID_ARGUMENT);

    descriptor = (ShOverlayDescriptor)SH_OVERLAY_DESCRIPTOR_INIT;
    descriptor.id = 21u;
    descriptor.slot = SH_OVERLAY_SLOT_MAP;
    descriptor.name = "LOGICAL_ONLY";
    descriptor.psx_load_address = 0u;
    descriptor.memory_size = 0u;
    descriptor.userdata = &probe;

    assert(
        sh_runtime_overlay_register(runtime, &descriptor) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_overlay_activate(runtime, 21u) ==
        SH_RESULT_OK);

    sh_runtime_destroy(runtime);
}

int main(void)
{
    test_registration_activation_and_ticks();
    test_replacement_and_memory_clear();
    test_invalid_descriptor_range();

    return 0;
}
