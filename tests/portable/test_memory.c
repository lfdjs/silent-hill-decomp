#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stdint.h>
#include <string.h>

static ShRuntime* create_runtime(const ShMemoryConfig* memory)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntime* runtime = NULL;

    config.host = &host;
    config.memory = memory;

    assert(sh_runtime_create(&config, &runtime) == SH_RESULT_OK);
    assert(runtime != NULL);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);

    return runtime;
}

static void test_default_psx_address_space(void)
{
    ShRuntime* runtime = create_runtime(NULL);
    ShMemoryStats stats = SH_MEMORY_STATS_INIT;
    uint32_t offset = UINT32_MAX;
    ShPsxAddress address = 0u;
    uint8_t write_data[4] = { 0x78u, 0x56u, 0x34u, 0x12u };
    uint8_t read_data[4] = { 0u, 0u, 0u, 0u };

    assert(
        sh_runtime_memory_validate(
            runtime,
            SH_PSX_RAM_BASE,
            SH_PSX_RAM_SIZE) == SH_RESULT_OK);

    assert(
        sh_runtime_memory_validate(
            runtime,
            SH_PSX_RAM_BASE + SH_PSX_RAM_SIZE,
            0u) == SH_RESULT_OK);

    assert(
        sh_runtime_memory_validate(
            runtime,
            SH_PSX_RAM_BASE + SH_PSX_RAM_SIZE,
            1u) == SH_RESULT_INVALID_ARGUMENT);

    assert(
        sh_runtime_memory_address_to_offset(
            runtime,
            SH_PSX_RAM_BASE + UINT32_C(0x1234),
            &offset) == SH_RESULT_OK);
    assert(offset == UINT32_C(0x1234));

    assert(
        sh_runtime_memory_offset_to_address(
            runtime,
            UINT32_C(0x1234),
            &address) == SH_RESULT_OK);
    assert(address == SH_PSX_RAM_BASE + UINT32_C(0x1234));

    assert(
        sh_runtime_memory_write(
            runtime,
            SH_PSX_RAM_BASE + UINT32_C(0x100),
            write_data,
            sizeof(write_data)) == SH_RESULT_OK);

    assert(
        sh_runtime_memory_read(
            runtime,
            SH_PSX_RAM_BASE + UINT32_C(0x100),
            read_data,
            sizeof(read_data)) == SH_RESULT_OK);

    assert(memcmp(write_data, read_data, sizeof(write_data)) == 0);

    assert(
        sh_runtime_memory_fill(
            runtime,
            SH_PSX_RAM_BASE + UINT32_C(0x102),
            UINT8_C(0xAA),
            2u) == SH_RESULT_OK);

    memset(read_data, 0, sizeof(read_data));

    assert(
        sh_runtime_memory_read(
            runtime,
            SH_PSX_RAM_BASE + UINT32_C(0x100),
            read_data,
            sizeof(read_data)) == SH_RESULT_OK);

    assert(read_data[0] == UINT8_C(0x78));
    assert(read_data[1] == UINT8_C(0x56));
    assert(read_data[2] == UINT8_C(0xAA));
    assert(read_data[3] == UINT8_C(0xAA));

    assert(
        sh_runtime_memory_get_stats(runtime, &stats) == SH_RESULT_OK);

    assert(stats.psx_base == SH_PSX_RAM_BASE);
    assert(stats.size_bytes == SH_PSX_RAM_SIZE);
    assert(stats.write_operations == UINT64_C(1));
    assert(stats.read_operations == UINT64_C(2));
    assert(stats.fill_operations == UINT64_C(1));
    assert(stats.bytes_written == UINT64_C(4));
    assert(stats.bytes_read == UINT64_C(8));
    assert(stats.bytes_filled == UINT64_C(2));

    sh_runtime_destroy(runtime);
}

static void test_custom_memory_config(void)
{
    ShMemoryConfig memory = SH_MEMORY_CONFIG_INIT;
    ShRuntime* runtime;
    uint8_t value = UINT8_C(0x5A);
    uint8_t read_value = 0u;

    memory.psx_base = UINT32_C(0x10000000);
    memory.size_bytes = UINT32_C(0x00010000);

    runtime = create_runtime(&memory);

    assert(
        sh_runtime_memory_write(
            runtime,
            UINT32_C(0x1000FFFF),
            &value,
            1u) == SH_RESULT_OK);

    assert(
        sh_runtime_memory_read(
            runtime,
            UINT32_C(0x1000FFFF),
            &read_value,
            1u) == SH_RESULT_OK);

    assert(read_value == value);

    assert(
        sh_runtime_memory_write(
            runtime,
            UINT32_C(0x10010000),
            &value,
            1u) == SH_RESULT_INVALID_ARGUMENT);

    sh_runtime_destroy(runtime);
}

static void test_not_ready_and_invalid_config(void)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShMemoryConfig memory = SH_MEMORY_CONFIG_INIT;
    ShRuntime* runtime = NULL;
    uint8_t value = 0u;

    config.host = &host;
    config.memory = &memory;

    assert(sh_runtime_create(&config, &runtime) == SH_RESULT_OK);

    assert(
        sh_runtime_memory_read(
            runtime,
            SH_PSX_RAM_BASE,
            &value,
            1u) == SH_RESULT_NOT_READY);

    sh_runtime_destroy(runtime);

    runtime = NULL;
    memory.size_bytes = 0u;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);
    assert(runtime == NULL);
}

int main(void)
{
    test_default_psx_address_space();
    test_custom_memory_config();
    test_not_ready_and_invalid_config();

    return 0;
}
