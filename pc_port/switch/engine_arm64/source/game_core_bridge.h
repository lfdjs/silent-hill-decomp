/* SPDX-License-Identifier: GPL-3.0-or-later
 * Boundary between libnx and the original decompiled Silent Hill headers.
 * Keep libnx's <switch.h> out of translation units that include the PSX types.
 */
#ifndef SH_SWITCH_GAME_CORE_BRIDGE_H
#define SH_SWITCH_GAME_CORE_BRIDGE_H
#include <stdint.h>

uint32_t ShGameCore_Rng_Rand32(void);
int32_t  ShGameCore_Rng_Rand16(void);
uint16_t ShGameCore_Rng_Rand12(void);
uint32_t ShGameCore_Rng_GetSeed(void);
void ShGameCore_Rng_SetSeed(uint32_t seed);
void ShGameCore_Mem_Move32(uint32_t* dest, uint32_t* src, int32_t byte_count);

#endif
