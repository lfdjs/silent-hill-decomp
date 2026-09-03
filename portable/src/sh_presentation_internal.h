#ifndef SILENT_HILL_SH_PRESENTATION_INTERNAL_H
#define SILENT_HILL_SH_PRESENTATION_INTERNAL_H

#include "silent_hill/sh_presentation.h"

#define SH_PRESENTATION_QUEUE_CAPACITY 64u

typedef struct ShPresentationQueue
{
    ShPresentationCommand commands[SH_PRESENTATION_QUEUE_CAPACITY];
    uint32_t head;
    uint32_t count;
    uint64_t emitted_count;
    uint64_t popped_count;
    uint64_t dropped_count;
} ShPresentationQueue;

void sh_presentation_queue_init(ShPresentationQueue* queue);

ShResult sh_presentation_emit(
    ShRuntime* runtime,
    const ShPresentationCommand* command);

#endif
