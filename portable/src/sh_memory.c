#include "sh_runtime_internal.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define SH_MEMORY_MAX_BYTES UINT32_C(0x04000000)

static bool sh_memory_config_valid(const ShMemoryConfig* config)
{
    uint64_t end_address;

    if (config == NULL)
    {
        return false;
    }

    if (!sh_runtime_size_is_supported(
            config->struct_size,
            sizeof(ShMemoryConfig)))
    {
        return false;
    }

    if (config->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return false;
    }

    if (config->size_bytes == 0u ||
        config->size_bytes > SH_MEMORY_MAX_BYTES)
    {
        return false;
    }

    end_address =
        (uint64_t)config->psx_base +
        (uint64_t)config->size_bytes;

    return end_address <= UINT64_C(0x100000000);
}

ShResult sh_memory_init(
    ShMemory* memory,
    const ShMemoryConfig* config)
{
    if (memory == NULL || !sh_memory_config_valid(config))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    memset(memory, 0, sizeof(*memory));

    memory->bytes =
        (uint8_t*)calloc((size_t)config->size_bytes, 1u);

    if (memory->bytes == NULL)
    {
        return SH_RESULT_OUT_OF_MEMORY;
    }

    memory->psx_base = config->psx_base;
    memory->size_bytes = config->size_bytes;

    return SH_RESULT_OK;
}

void sh_memory_destroy(ShMemory* memory)
{
    if (memory == NULL)
    {
        return;
    }

    free(memory->bytes);
    memset(memory, 0, sizeof(*memory));
}

bool sh_memory_range_valid(
    const ShMemory* memory,
    ShPsxAddress address,
    size_t size)
{
    uint64_t base;
    uint64_t end;
    uint64_t request_begin;
    uint64_t request_end;

    if (memory == NULL || memory->bytes == NULL)
    {
        return false;
    }

    base = (uint64_t)memory->psx_base;
    end = base + (uint64_t)memory->size_bytes;
    request_begin = (uint64_t)address;

    if (request_begin < base || request_begin > end)
    {
        return false;
    }

    if ((uint64_t)size > UINT64_MAX - request_begin)
    {
        return false;
    }

    request_end = request_begin + (uint64_t)size;

    if (size == 0u)
    {
        return request_begin <= end;
    }

    return request_begin < end && request_end <= end;
}

static size_t sh_memory_offset(
    const ShMemory* memory,
    ShPsxAddress address)
{
    return (size_t)(address - memory->psx_base);
}

static bool sh_memory_counter_can_add(
    uint64_t current,
    size_t amount)
{
    return (uint64_t)amount <= UINT64_MAX - current;
}

ShResult sh_memory_fill_internal(
    ShMemory* memory,
    ShPsxAddress address,
    uint8_t value,
    size_t size)
{
    if (memory == NULL ||
        !sh_memory_range_valid(memory, address, size))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (memory->fill_operations == UINT64_MAX ||
        !sh_memory_counter_can_add(memory->bytes_filled, size))
    {
        return SH_RESULT_OVERFLOW;
    }

    if (size > 0u)
    {
        memset(
            memory->bytes + sh_memory_offset(memory, address),
            (int)value,
            size);
    }

    memory->fill_operations++;
    memory->bytes_filled += (uint64_t)size;

    return SH_RESULT_OK;
}

ShResult sh_runtime_memory_validate(
    const ShRuntime* runtime,
    ShPsxAddress address,
    size_t size)
{
    if (!sh_runtime_is_ready(runtime))
    {
        return runtime == NULL ?
            SH_RESULT_INVALID_ARGUMENT :
            SH_RESULT_NOT_READY;
    }

    return sh_memory_range_valid(
        &runtime->memory,
        address,
        size) ?
        SH_RESULT_OK :
        SH_RESULT_INVALID_ARGUMENT;
}

ShResult sh_runtime_memory_address_to_offset(
    const ShRuntime* runtime,
    ShPsxAddress address,
    uint32_t* out_offset)
{
    if (out_offset == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    *out_offset = 0u;

    if (!sh_runtime_is_ready(runtime))
    {
        return runtime == NULL ?
            SH_RESULT_INVALID_ARGUMENT :
            SH_RESULT_NOT_READY;
    }

    if (!sh_memory_range_valid(&runtime->memory, address, 1u))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    *out_offset = address - runtime->memory.psx_base;
    return SH_RESULT_OK;
}

ShResult sh_runtime_memory_offset_to_address(
    const ShRuntime* runtime,
    uint32_t offset,
    ShPsxAddress* out_address)
{
    uint64_t address;

    if (out_address == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    *out_address = 0u;

    if (!sh_runtime_is_ready(runtime))
    {
        return runtime == NULL ?
            SH_RESULT_INVALID_ARGUMENT :
            SH_RESULT_NOT_READY;
    }

    if (offset >= runtime->memory.size_bytes)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    address =
        (uint64_t)runtime->memory.psx_base +
        (uint64_t)offset;

    if (address > UINT32_MAX)
    {
        return SH_RESULT_OVERFLOW;
    }

    *out_address = (ShPsxAddress)address;
    return SH_RESULT_OK;
}

ShResult sh_runtime_memory_read(
    const ShRuntime* runtime,
    ShPsxAddress address,
    void* destination,
    size_t size)
{
    ShMemory* memory;

    if (runtime == NULL || (destination == NULL && size > 0u))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    memory = (ShMemory*)&runtime->memory;

    if (!sh_memory_range_valid(memory, address, size))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (memory->read_operations == UINT64_MAX ||
        !sh_memory_counter_can_add(memory->bytes_read, size))
    {
        return SH_RESULT_OVERFLOW;
    }

    if (size > 0u)
    {
        memcpy(
            destination,
            memory->bytes + sh_memory_offset(memory, address),
            size);
    }

    memory->read_operations++;
    memory->bytes_read += (uint64_t)size;

    return SH_RESULT_OK;
}

ShResult sh_runtime_memory_write(
    ShRuntime* runtime,
    ShPsxAddress address,
    const void* source,
    size_t size)
{
    ShMemory* memory;

    if (runtime == NULL || (source == NULL && size > 0u))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    memory = &runtime->memory;

    if (!sh_memory_range_valid(memory, address, size))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (memory->write_operations == UINT64_MAX ||
        !sh_memory_counter_can_add(memory->bytes_written, size))
    {
        return SH_RESULT_OVERFLOW;
    }

    if (size > 0u)
    {
        memcpy(
            memory->bytes + sh_memory_offset(memory, address),
            source,
            size);
    }

    memory->write_operations++;
    memory->bytes_written += (uint64_t)size;

    return SH_RESULT_OK;
}

ShResult sh_runtime_memory_fill(
    ShRuntime* runtime,
    ShPsxAddress address,
    uint8_t value,
    size_t size)
{
    if (runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    return sh_memory_fill_internal(
        &runtime->memory,
        address,
        value,
        size);
}

ShResult sh_runtime_memory_get_stats(
    const ShRuntime* runtime,
    ShMemoryStats* out_stats)
{
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
            sizeof(ShMemoryStats)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_stats->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    out_stats->struct_size = (uint32_t)sizeof(ShMemoryStats);
    out_stats->abi_version = SH_ABI_VERSION_CURRENT;
    out_stats->psx_base = runtime->memory.psx_base;
    out_stats->size_bytes = runtime->memory.size_bytes;
    out_stats->read_operations = runtime->memory.read_operations;
    out_stats->write_operations = runtime->memory.write_operations;
    out_stats->fill_operations = runtime->memory.fill_operations;
    out_stats->bytes_read = runtime->memory.bytes_read;
    out_stats->bytes_written = runtime->memory.bytes_written;
    out_stats->bytes_filled = runtime->memory.bytes_filled;

    return SH_RESULT_OK;
}
