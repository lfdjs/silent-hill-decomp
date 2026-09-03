#ifndef SILENT_HILL_SH_MEMORY_INTERNAL_H
#define SILENT_HILL_SH_MEMORY_INTERNAL_H

#include "silent_hill/sh_memory.h"

typedef struct ShMemory
{
    uint8_t* bytes;
    ShPsxAddress psx_base;
    uint32_t size_bytes;
    uint64_t read_operations;
    uint64_t write_operations;
    uint64_t fill_operations;
    uint64_t bytes_read;
    uint64_t bytes_written;
    uint64_t bytes_filled;
} ShMemory;

ShResult sh_memory_init(
    ShMemory* memory,
    const ShMemoryConfig* config);

void sh_memory_destroy(ShMemory* memory);

bool sh_memory_range_valid(
    const ShMemory* memory,
    ShPsxAddress address,
    size_t size);

ShResult sh_memory_fill_internal(
    ShMemory* memory,
    ShPsxAddress address,
    uint8_t value,
    size_t size);

#endif
