#ifndef SILENT_HILL_SH_AUDIO_INTERNAL_H
#define SILENT_HILL_SH_AUDIO_INTERNAL_H

#include "silent_hill/sh_audio.h"

#define SH_AUDIO_QUEUE_CAPACITY 32u

typedef struct ShAudioQueue
{
    ShAudioCommand commands[SH_AUDIO_QUEUE_CAPACITY];
    uint32_t head;
    uint32_t count;
    uint64_t emitted_count;
    uint64_t popped_count;
    uint64_t dropped_count;
} ShAudioQueue;

void sh_audio_queue_init(ShAudioQueue* queue);

ShResult sh_audio_emit(
    ShRuntime* runtime,
    const ShAudioCommand* command);

#endif
