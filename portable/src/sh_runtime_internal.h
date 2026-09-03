#ifndef SILENT_HILL_SH_RUNTIME_INTERNAL_H
#define SILENT_HILL_SH_RUNTIME_INTERNAL_H

#include "silent_hill/sh_api.h"

#include "sh_audio_internal.h"
#include "sh_clock.h"
#include "sh_game_internal.h"
#include "sh_memory_internal.h"
#include "sh_overlay_internal.h"
#include "sh_presentation_internal.h"

struct ShRuntime
{
    ShHostServices host;
    ShRng rng;
    ShClock clock;
    ShGameController game;
    ShAudioQueue audio;
    ShPresentationQueue presentation;
    ShMemory memory;
    ShOverlayManager overlays;
    ShTickFn tick;
    void* tick_userdata;

    ShInputConfig input_config;
    ShInputState submitted_input;
    ShInputSnapshot input_snapshot;

    uint64_t update_count;
    uint64_t total_elapsed_us;
    uint64_t tick_count;
    uint64_t accepted_elapsed_us;
    uint64_t dropped_elapsed_us;
    uint64_t paused_elapsed_us;
    uint32_t last_advance_ticks;
    bool booted;
};

bool sh_runtime_size_is_supported(
    uint32_t supplied,
    size_t required);

bool sh_runtime_is_ready(
    const ShRuntime* runtime);

#endif
