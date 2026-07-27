#ifndef SILENT_HILL_SH_RESULT_H
#define SILENT_HILL_SH_RESULT_H

#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum ShResult
{
    SH_RESULT_OK = 0,
    SH_RESULT_INVALID_ARGUMENT = 1,
    SH_RESULT_UNSUPPORTED_VERSION = 2,
    SH_RESULT_HOST_ERROR = 3,
    SH_RESULT_OUT_OF_MEMORY = 4,
    SH_RESULT_NOT_READY = 5,
    SH_RESULT_OVERFLOW = 6,
    SH_RESULT_INVALID_STATE = 7,
    SH_RESULT_UNSUPPORTED = 8,
    SH_RESULT_NOT_FOUND = 9,
    SH_RESULT_IO_ERROR = 10,
    SH_RESULT_BUFFER_TOO_SMALL = 11
} ShResult;

SH_API const char* sh_result_string(ShResult result);

#ifdef __cplusplus
}
#endif

#endif
