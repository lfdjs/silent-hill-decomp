#include "sh_runtime_internal.h"

#include <string.h>

static bool sh_file_domain_is_valid(ShFileDomain domain)
{
    return
        domain == SH_FILE_DOMAIN_ASSET ||
        domain == SH_FILE_DOMAIN_SAVE;
}

static bool sh_logical_path_is_valid(const char* path)
{
    const char* cursor;
    const char* component;

    if (path == NULL || path[0] == '\0')
    {
        return false;
    }

    if (path[0] == '/' || path[0] == '\\')
    {
        return false;
    }

    component = path;

    for (cursor = path; ; cursor++)
    {
        char ch = *cursor;

        if (ch == '\\' || ch == ':')
        {
            return false;
        }

        if (ch == '/' || ch == '\0')
        {
            size_t component_length =
                (size_t)(cursor - component);

            if (component_length == 0u)
            {
                return false;
            }

            if (component_length == 1u &&
                component[0] == '.')
            {
                return false;
            }

            if (component_length == 2u &&
                component[0] == '.' &&
                component[1] == '.')
            {
                return false;
            }

            if (ch == '\0')
            {
                return true;
            }

            component = cursor + 1;
        }
    }
}

static ShResult sh_file_info_validate(
    const ShFileInfo* info)
{
    if (info == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_runtime_size_is_supported(
            info->struct_size,
            sizeof(ShFileInfo)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (info->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    return SH_RESULT_OK;
}

ShResult sh_runtime_file_stat(
    const ShRuntime* runtime,
    ShFileDomain domain,
    const char* path,
    ShFileInfo* out_info)
{
    ShResult result;
    uint64_t size = 0u;

    if (!sh_runtime_is_ready(runtime))
    {
        return runtime == NULL ?
            SH_RESULT_INVALID_ARGUMENT :
            SH_RESULT_NOT_READY;
    }

    if (!sh_file_domain_is_valid(domain) ||
        !sh_logical_path_is_valid(path))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    result = sh_file_info_validate(out_info);

    if (result != SH_RESULT_OK)
    {
        return result;
    }

    out_info->exists = false;
    out_info->size = 0u;

    if (runtime->host.file_stat == NULL)
    {
        return SH_RESULT_UNSUPPORTED;
    }

    result = runtime->host.file_stat(
        runtime->host.userdata,
        domain,
        path,
        &size);

    if (result == SH_RESULT_NOT_FOUND)
    {
        out_info->struct_size =
            (uint32_t)sizeof(ShFileInfo);
        out_info->abi_version =
            SH_ABI_VERSION_CURRENT;
        return SH_RESULT_OK;
    }

    if (result != SH_RESULT_OK)
    {
        return result;
    }

    out_info->struct_size =
        (uint32_t)sizeof(ShFileInfo);
    out_info->abi_version =
        SH_ABI_VERSION_CURRENT;
    out_info->exists = true;
    out_info->size = size;

    return SH_RESULT_OK;
}

ShResult sh_runtime_file_read(
    const ShRuntime* runtime,
    ShFileDomain domain,
    const char* path,
    uint64_t offset,
    void* destination,
    size_t size,
    size_t* out_read)
{
    ShResult result;
    size_t read_size = 0u;

    if (!sh_runtime_is_ready(runtime))
    {
        return runtime == NULL ?
            SH_RESULT_INVALID_ARGUMENT :
            SH_RESULT_NOT_READY;
    }

    if (!sh_file_domain_is_valid(domain) ||
        !sh_logical_path_is_valid(path) ||
        out_read == NULL ||
        (destination == NULL && size != 0u))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    *out_read = 0u;

    if (size == 0u)
    {
        return SH_RESULT_OK;
    }

    if (runtime->host.file_read == NULL)
    {
        return SH_RESULT_UNSUPPORTED;
    }

    result = runtime->host.file_read(
        runtime->host.userdata,
        domain,
        path,
        offset,
        destination,
        size,
        &read_size);

    if (read_size > size)
    {
        return SH_RESULT_HOST_ERROR;
    }

    *out_read = read_size;
    return result;
}

ShResult sh_runtime_storage_write_atomic(
    const ShRuntime* runtime,
    const char* path,
    const void* source,
    size_t size)
{
    if (!sh_runtime_is_ready(runtime))
    {
        return runtime == NULL ?
            SH_RESULT_INVALID_ARGUMENT :
            SH_RESULT_NOT_READY;
    }

    if (!sh_logical_path_is_valid(path) ||
        (source == NULL && size != 0u))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (runtime->host.storage_write_atomic == NULL)
    {
        return SH_RESULT_UNSUPPORTED;
    }

    return runtime->host.storage_write_atomic(
        runtime->host.userdata,
        path,
        source,
        size);
}

ShResult sh_runtime_storage_remove(
    const ShRuntime* runtime,
    const char* path)
{
    if (!sh_runtime_is_ready(runtime))
    {
        return runtime == NULL ?
            SH_RESULT_INVALID_ARGUMENT :
            SH_RESULT_NOT_READY;
    }

    if (!sh_logical_path_is_valid(path))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (runtime->host.storage_remove == NULL)
    {
        return SH_RESULT_UNSUPPORTED;
    }

    return runtime->host.storage_remove(
        runtime->host.userdata,
        path);
}
