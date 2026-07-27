#ifndef SILENT_HILL_SH_RNG_H
#define SILENT_HILL_SH_RNG_H

#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ShRng
{
    uint32_t seed;
} ShRng;

SH_API void sh_rng_init(ShRng* rng, uint32_t seed);
SH_API uint32_t sh_rng_get_seed(const ShRng* rng);
SH_API void sh_rng_set_seed(ShRng* rng, uint32_t seed);
SH_API uint32_t sh_rng_next_u32(ShRng* rng);
SH_API uint16_t sh_rng_next_u15(ShRng* rng);
SH_API uint16_t sh_rng_next_u12(ShRng* rng);

#ifdef __cplusplus
}
#endif

#endif
