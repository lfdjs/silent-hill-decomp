#ifndef SILENT_HILL_SH_TYPES_H
#define SILENT_HILL_SH_TYPES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) && !defined(SH_STATIC)
    #if defined(SH_BUILDING_LIBRARY)
        #define SH_API __declspec(dllexport)
    #else
        #define SH_API __declspec(dllimport)
    #endif
#elif defined(__GNUC__) || defined(__clang__)
    #define SH_API __attribute__((visibility("default")))
#else
    #define SH_API
#endif

#define SH_VERSION_MAJOR 0u
#define SH_VERSION_MINOR 7u
#define SH_VERSION_PATCH 0u
#define SH_VERSION_STRING "0.7.0"

#define SH_ABI_VERSION_ENCODE(major, minor) \
    ((((uint32_t)(major)) << 16u) | ((uint32_t)(minor)))

#define SH_ABI_VERSION_CURRENT \
    SH_ABI_VERSION_ENCODE(SH_VERSION_MAJOR, SH_VERSION_MINOR)

typedef struct ShRuntime ShRuntime;

#endif
