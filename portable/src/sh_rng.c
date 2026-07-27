#include "silent_hill/sh_rng.h"

void sh_rng_init(ShRng* rng, uint32_t seed)
{
    if (rng != NULL)
    {
        rng->seed = seed;
    }
}

uint32_t sh_rng_get_seed(const ShRng* rng)
{
    return rng != NULL ? rng->seed : 0u;
}

void sh_rng_set_seed(ShRng* rng, uint32_t seed)
{
    if (rng != NULL)
    {
        rng->seed = seed;
    }
}

uint32_t sh_rng_next_u32(ShRng* rng)
{
    if (rng == NULL)
    {
        return 0u;
    }

    rng->seed =
        (rng->seed * UINT32_C(1664525)) +
        UINT32_C(1013904223);

    return rng->seed;
}

uint16_t sh_rng_next_u15(ShRng* rng)
{
    return (uint16_t)(sh_rng_next_u32(rng) >> 17u);
}

uint16_t sh_rng_next_u12(ShRng* rng)
{
    return (uint16_t)(sh_rng_next_u32(rng) >> 20u);
}
