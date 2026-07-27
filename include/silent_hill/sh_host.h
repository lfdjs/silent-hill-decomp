#ifndef SILENT_HILL_SH_HOST_H
#define SILENT_HILL_SH_HOST_H

#include "silent_hill/sh_io.h"
#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum ShLogLevel
{
    SH_LOG_LEVEL_DEBUG = 0,
    SH_LOG_LEVEL_INFO = 1,
    SH_LOG_LEVEL_WARNING = 2,
    SH_LOG_LEVEL_ERROR = 3
} ShLogLevel;

typedef uint64_t (*ShTimeNowUsFn)(void* userdata);

typedef void (*ShLogFn)(
    void* userdata,
    ShLogLevel level,
    const char* message);

typedef struct ShHostServices
{
    uint32_t struct_size;
    uint32_t abi_version;
    void* userdata;

    ShTimeNowUsFn time_now_us;
    ShLogFn log;

    ShFileStatFn file_stat;
    ShFileReadFn file_read;
    ShStorageWriteAtomicFn storage_write_atomic;
    ShStorageRemoveFn storage_remove;
} ShHostServices;

#define SH_HOST_SERVICES_INIT \
    { \
        (uint32_t)sizeof(ShHostServices), \
        SH_ABI_VERSION_CURRENT, \
        NULL, \
        NULL, \
        NULL, \
        NULL, \
        NULL, \
        NULL, \
        NULL \
    }

#ifdef __cplusplus
}
#endif

#endif
