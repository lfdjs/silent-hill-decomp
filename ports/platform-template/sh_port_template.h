#ifndef SILENT_HILL_SH_PORT_TEMPLATE_H
#define SILENT_HILL_SH_PORT_TEMPLATE_H

/* Example host adapter only: this header is NOT part of the stable core ABI. */
#include "silent_hill/sh_api.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef ShInputButtons (*ShPortButtonsFn)(void* userdata);
typedef void (*ShPortVideoFn)(
    void* userdata, const ShPresentationCommand* command);
typedef void (*ShPortAudioFn)(
    void* userdata, const ShAudioCommand* command);
typedef void (*ShPortTransitionFn)(
    void* userdata, ShGameState from, ShGameState to);

typedef struct ShPortHooks
{
    void* userdata;
    ShPortButtonsFn poll_buttons;
    ShPortVideoFn on_video;
    ShPortAudioFn on_audio;
    ShPortTransitionFn on_transition;
} ShPortHooks;

typedef struct ShPortTemplate
{
    ShRuntime* runtime;
    ShPortHooks hooks;
    ShGameSnapshot snapshot;
    uint64_t ticks;
    uint64_t video_commands;
    uint64_t frames;
    uint64_t audio_commands;
    uint64_t fade_out_tick;
    bool fade_out_seen;
    bool reached_unsupported;
} ShPortTemplate;

/* Caller must zero-initialize the instance before first init. */
ShResult sh_port_template_init(ShPortTemplate* port, const ShPortHooks* hooks);
ShResult sh_port_template_tick(ShPortTemplate* port);
void sh_port_template_destroy(ShPortTemplate* port);

#ifdef __cplusplus
}
#endif

#endif
