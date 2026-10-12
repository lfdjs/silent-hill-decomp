#ifndef SILENT_HILL_PC_APP_H
#define SILENT_HILL_PC_APP_H

#include "silent_hill/sh_api.h"

typedef void (*ShPcVideoFn)(void* userdata, const ShPresentationCommand* command);
typedef void (*ShPcAudioFn)(void* userdata, const ShAudioCommand* command);

typedef struct ShPcApp
{
    ShRuntime* runtime;
    ShGameSnapshot snapshot;
    uint64_t ticks;
    uint64_t frames;
    uint64_t video_commands;
    uint64_t audio_commands;
    uint64_t audio_160_count;
    uint64_t audio_162_count;
    uint64_t fade_out_tick;
    bool fade_out_seen;
    bool reached_unsupported;
    ShPcVideoFn video_fn;
    ShPcAudioFn audio_fn;
    void* sink_userdata;
} ShPcApp;

ShResult sh_pc_app_init(ShPcApp* app, ShPcVideoFn video_fn,
                         ShPcAudioFn audio_fn, void* sink_userdata);
ShResult sh_pc_app_tick(ShPcApp* app, ShInputButtons buttons);
void sh_pc_app_destroy(ShPcApp* app);

#endif
