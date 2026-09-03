#ifndef SILENT_HILL_SH_MEMORY_H
#define SILENT_HILL_SH_MEMORY_H

#include "silent_hill/sh_result.h"
#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SH_PSX_RAM_BASE UINT32_C(0x80000000)
#define SH_PSX_RAM_SIZE UINT32_C(0x00200000)

typedef uint32_t ShPsxAddress;

typedef struct ShMemoryConfig
{
    uint32_t struct_size;
    uint32_t abi_version;
    ShPsxAddress psx_base;
    uint32_t size_bytes;
} ShMemoryConfig;

#define SH_MEMORY_CONFIG_INIT \
    { \
        (uint32_t)sizeof(ShMemoryConfig), \
        SH_ABI_VERSION_CURRENT, \
        SH_PSX_RAM_BASE, \
        SH_PSX_RAM_SIZE \
    }

typedef struct ShMemoryStats
{
    uint32_t struct_size;
    uint32_t abi_version;
    ShPsxAddress psx_base;
    uint32_t size_bytes;
    uint64_t read_operations;
    uint64_t write_operations;
    uint64_t fill_operations;
    uint64_t bytes_read;
    uint64_t bytes_written;
    uint64_t bytes_filled;
} ShMemoryStats;

#define SH_MEMORY_STATS_INIT \
    { \
        (uint32_t)sizeof(ShMemoryStats), \
        SH_ABI_VERSION_CURRENT, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u \
    }

SH_API ShResult sh_runtime_memory_validate(
    const ShRuntime* runtime,
    ShPsxAddress address,
    size_t size);

SH_API ShResult sh_runtime_memory_address_to_offset(
    const ShRuntime* runtime,
    ShPsxAddress address,
    uint32_t* out_offset);

SH_API ShResult sh_runtime_memory_offset_to_address(
    const ShRuntime* runtime,
    uint32_t offset,
    ShPsxAddress* out_address);

SH_API ShResult sh_runtime_memory_read(
    const ShRuntime* runtime,
    ShPsxAddress address,
    void* destination,
    size_t size);

SH_API ShResult sh_runtime_memory_write(
    ShRuntime* runtime,
    ShPsxAddress address,
    const void* source,
    size_t size);

SH_API ShResult sh_runtime_memory_fill(
    ShRuntime* runtime,
    ShPsxAddress address,
    uint8_t value,
    size_t size);

SH_API ShResult sh_runtime_memory_get_stats(
    const ShRuntime* runtime,
    ShMemoryStats* out_stats);

#ifdef __cplusplus
}
#endif

#endif
