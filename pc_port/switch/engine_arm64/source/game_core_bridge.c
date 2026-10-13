/* SPDX-License-Identifier: GPL-3.0-or-later
 * Compile the original Silent Hill headers here, WITHOUT <switch.h>.
 * The game code is compiled unmodified by game_rng.c/game_memmove32.c.
 */
#include "main/rng.h"
#include "main/mem.h"
#include "game_core_bridge.h"

_Static_assert(sizeof(u32) == sizeof(uint32_t), "game u32 must be 32-bit");
_Static_assert(sizeof(s32) == sizeof(int32_t), "game s32 must be 32-bit");
_Static_assert(sizeof(u16) == sizeof(uint16_t), "game u16 must be 16-bit");

uint32_t ShGameCore_Rng_Rand32(void) { return (uint32_t)Rng_Rand32(); }
int32_t ShGameCore_Rng_Rand16(void) { return (int32_t)Rng_Rand16(); }
uint16_t ShGameCore_Rng_Rand12(void) { return (uint16_t)Rng_Rand12(); }
uint32_t ShGameCore_Rng_GetSeed(void) { return (uint32_t)Rng_GetSeed(); }
void ShGameCore_Rng_SetSeed(uint32_t seed) { Rng_SetSeed((u32)seed); }
void ShGameCore_Mem_Move32(uint32_t* dest, uint32_t* src, int32_t byte_count)
{
    Mem_Move32((u32*)dest, (u32*)src, (s32)byte_count);
}
