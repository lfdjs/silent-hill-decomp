#ifndef SILENT_HILL_SH_IO_H
#define SILENT_HILL_SH_IO_H

#include "silent_hill/sh_result.h"
#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum ShFileDomain
{
    SH_FILE_DOMAIN_ASSET = 0,
    SH_FILE_DOMAIN_SAVE = 1
} ShFileDomain;

typedef struct ShFileInfo
{
    uint32_t struct_size;
    uint32_t abi_version;
    bool exists;
    uint64_t size;
} ShFileInfo;

#define SH_FILE_INFO_INIT \
    { \
        (uint32_t)sizeof(ShFileInfo), \
        SH_ABI_VERSION_CURRENT, \
        false, \
        0u \
    }

typedef ShResult (*ShFileStatFn)(
    void* userdata,
    ShFileDomain domain,
    const char* path,
    uint64_t* out_size);

typedef ShResult (*ShFileReadFn)(
    void* userdata,
    ShFileDomain domain,
    const char* path,
    uint64_t offset,
    void* destination,
    size_t size,
    size_t* out_read);

typedef ShResult (*ShStorageWriteAtomicFn)(
    void* userdata,
    const char* path,
    const void* source,
    size_t size);

typedef ShResult (*ShStorageRemoveFn)(
    void* userdata,
    const char* path);

#ifdef __cplusplus
}
#endif

#endif
