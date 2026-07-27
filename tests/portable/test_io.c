#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct MemoryHost
{
    uint8_t save_data[256];
    size_t save_size;
    bool save_exists;
} MemoryHost;

static const uint8_t g_asset_data[] = {
    0x10u,
    0x20u,
    0x30u,
    0x40u,
    0x50u,
    0x60u
};

static ShResult memory_file_stat(
    void* userdata,
    ShFileDomain domain,
    const char* path,
    uint64_t* out_size)
{
    MemoryHost* host = (MemoryHost*)userdata;

    assert(host != NULL);
    assert(path != NULL);
    assert(out_size != NULL);

    if (domain == SH_FILE_DOMAIN_ASSET &&
        strcmp(path, "assets/test.bin") == 0)
    {
        *out_size = sizeof(g_asset_data);
        return SH_RESULT_OK;
    }

    if (domain == SH_FILE_DOMAIN_SAVE &&
        strcmp(path, "slots/slot01.sav") == 0 &&
        host->save_exists)
    {
        *out_size = host->save_size;
        return SH_RESULT_OK;
    }

    return SH_RESULT_NOT_FOUND;
}

static ShResult memory_file_read(
    void* userdata,
    ShFileDomain domain,
    const char* path,
    uint64_t offset,
    void* destination,
    size_t size,
    size_t* out_read)
{
    MemoryHost* host = (MemoryHost*)userdata;
    const uint8_t* source = NULL;
    size_t source_size = 0u;
    size_t offset_size;
    size_t available;
    size_t copied;

    assert(host != NULL);
    assert(path != NULL);
    assert(destination != NULL);
    assert(out_read != NULL);

    if (domain == SH_FILE_DOMAIN_ASSET &&
        strcmp(path, "assets/test.bin") == 0)
    {
        source = g_asset_data;
        source_size = sizeof(g_asset_data);
    }
    else if (
        domain == SH_FILE_DOMAIN_SAVE &&
        strcmp(path, "slots/slot01.sav") == 0 &&
        host->save_exists)
    {
        source = host->save_data;
        source_size = host->save_size;
    }
    else
    {
        return SH_RESULT_NOT_FOUND;
    }

    if (offset > (uint64_t)SIZE_MAX)
    {
        return SH_RESULT_IO_ERROR;
    }

    offset_size = (size_t)offset;

    if (offset_size >= source_size)
    {
        *out_read = 0u;
        return SH_RESULT_OK;
    }

    available = source_size - offset_size;
    copied = size < available ? size : available;

    memcpy(destination, source + offset_size, copied);
    *out_read = copied;

    return SH_RESULT_OK;
}

static ShResult memory_storage_write_atomic(
    void* userdata,
    const char* path,
    const void* source,
    size_t size)
{
    MemoryHost* host = (MemoryHost*)userdata;

    assert(host != NULL);
    assert(path != NULL);

    if (strcmp(path, "slots/slot01.sav") != 0)
    {
        return SH_RESULT_NOT_FOUND;
    }

    if (size > sizeof(host->save_data))
    {
        return SH_RESULT_BUFFER_TOO_SMALL;
    }

    if (size != 0u)
    {
        assert(source != NULL);
        memcpy(host->save_data, source, size);
    }

    host->save_size = size;
    host->save_exists = true;

    return SH_RESULT_OK;
}

static ShResult memory_storage_remove(
    void* userdata,
    const char* path)
{
    MemoryHost* host = (MemoryHost*)userdata;

    assert(host != NULL);
    assert(path != NULL);

    if (strcmp(path, "slots/slot01.sav") != 0 ||
        !host->save_exists)
    {
        return SH_RESULT_NOT_FOUND;
    }

    host->save_size = 0u;
    host->save_exists = false;
    return SH_RESULT_OK;
}

static ShRuntime* create_runtime(
    MemoryHost* memory_host,
    bool with_io)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntime* runtime = NULL;

    host.userdata = memory_host;

    if (with_io)
    {
        host.file_stat = memory_file_stat;
        host.file_read = memory_file_read;
        host.storage_write_atomic =
            memory_storage_write_atomic;
        host.storage_remove =
            memory_storage_remove;
    }

    config.host = &host;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_OK);

    assert(runtime != NULL);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);

    return runtime;
}

static void test_asset_stat_and_partial_read(void)
{
    MemoryHost host = { { 0u }, 0u, false };
    ShRuntime* runtime = create_runtime(&host, true);
    ShFileInfo info = SH_FILE_INFO_INIT;
    uint8_t buffer[4] = { 0u, 0u, 0u, 0u };
    size_t read_size = 0u;

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "assets/test.bin",
            &info) == SH_RESULT_OK);

    assert(info.exists);
    assert(info.size == sizeof(g_asset_data));

    assert(
        sh_runtime_file_read(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "assets/test.bin",
            UINT64_C(2),
            buffer,
            sizeof(buffer),
            &read_size) == SH_RESULT_OK);

    assert(read_size == sizeof(buffer));
    assert(buffer[0] == 0x30u);
    assert(buffer[1] == 0x40u);
    assert(buffer[2] == 0x50u);
    assert(buffer[3] == 0x60u);

    info = (ShFileInfo)SH_FILE_INFO_INIT;

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "assets/missing.bin",
            &info) == SH_RESULT_OK);

    assert(!info.exists);
    assert(info.size == 0u);

    sh_runtime_destroy(runtime);
}

static void test_atomic_save_roundtrip(void)
{
    MemoryHost host = { { 0u }, 0u, false };
    ShRuntime* runtime = create_runtime(&host, true);
    static const uint8_t save_data[] = {
        1u,
        3u,
        3u,
        7u
    };
    uint8_t read_back[sizeof(save_data)] = { 0u };
    ShFileInfo info = SH_FILE_INFO_INIT;
    size_t read_size = 0u;

    assert(
        sh_runtime_storage_write_atomic(
            runtime,
            "slots/slot01.sav",
            save_data,
            sizeof(save_data)) == SH_RESULT_OK);

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_SAVE,
            "slots/slot01.sav",
            &info) == SH_RESULT_OK);

    assert(info.exists);
    assert(info.size == sizeof(save_data));

    assert(
        sh_runtime_file_read(
            runtime,
            SH_FILE_DOMAIN_SAVE,
            "slots/slot01.sav",
            0u,
            read_back,
            sizeof(read_back),
            &read_size) == SH_RESULT_OK);

    assert(read_size == sizeof(read_back));
    assert(memcmp(read_back, save_data, sizeof(save_data)) == 0);

    assert(
        sh_runtime_storage_remove(
            runtime,
            "slots/slot01.sav") == SH_RESULT_OK);

    info = (ShFileInfo)SH_FILE_INFO_INIT;

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_SAVE,
            "slots/slot01.sav",
            &info) == SH_RESULT_OK);

    assert(!info.exists);

    assert(
        sh_runtime_storage_remove(
            runtime,
            "slots/slot01.sav") == SH_RESULT_NOT_FOUND);

    sh_runtime_destroy(runtime);
}

static void test_validation_and_missing_services(void)
{
    MemoryHost host = { { 0u }, 0u, false };
    ShRuntime* runtime = create_runtime(&host, false);
    ShFileInfo info = SH_FILE_INFO_INIT;
    uint8_t byte = 0u;
    size_t read_size = 0u;

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "../secret",
            &info) == SH_RESULT_INVALID_ARGUMENT);

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "/absolute/path",
            &info) == SH_RESULT_INVALID_ARGUMENT);

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "assets/test.bin",
            &info) == SH_RESULT_UNSUPPORTED);

    assert(
        sh_runtime_file_read(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "assets/test.bin",
            0u,
            &byte,
            1u,
            &read_size) == SH_RESULT_UNSUPPORTED);

    assert(
        sh_runtime_storage_write_atomic(
            runtime,
            "slots/slot01.sav",
            &byte,
            1u) == SH_RESULT_UNSUPPORTED);

    assert(
        sh_runtime_storage_remove(
            runtime,
            "slots/slot01.sav") == SH_RESULT_UNSUPPORTED);

    sh_runtime_destroy(runtime);
}

int main(void)
{
    test_asset_stat_and_partial_read();
    test_atomic_save_roundtrip();
    test_validation_and_missing_services();

    return 0;
}
