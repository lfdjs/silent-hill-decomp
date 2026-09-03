#ifndef SILENT_HILL_SH_GAME_INTERNAL_H
#define SILENT_HILL_SH_GAME_INTERNAL_H

#include "silent_hill/sh_game.h"
#include "silent_hill/sh_overlay.h"

struct ShRuntime;

typedef struct ShGameController
{
    ShGameBootSignals boot_signals;
    ShGameKonamiSignals konami_signals;
    ShGameSnapshot snapshot;
    bool reference_registered;
} ShGameController;

void sh_game_controller_init(ShGameController* controller);
void sh_game_controller_reset(ShGameController* controller);

ShResult sh_reference_game_overlay_init(
    ShRuntime* runtime,
    ShOverlayId overlay_id,
    void* userdata);

void sh_reference_game_overlay_tick(
    ShRuntime* runtime,
    ShOverlayId overlay_id,
    uint64_t tick_index,
    void* userdata);

void sh_reference_game_overlay_shutdown(
    ShRuntime* runtime,
    ShOverlayId overlay_id,
    void* userdata);

#endif
