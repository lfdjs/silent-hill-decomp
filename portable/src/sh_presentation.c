#include "sh_runtime_internal.h"

#include <string.h>

void sh_presentation_queue_init(ShPresentationQueue* queue)
{
    if (queue != NULL)
    {
        memset(queue, 0, sizeof(*queue));
    }
}

const char* sh_presentation_command_name(
    ShPresentationCommandType type)
{
    switch (type)
    {
        case SH_PRESENTATION_COMMAND_NONE:
            return "none";
        case SH_PRESENTATION_COMMAND_CONFIGURE_DISPLAY:
            return "configure-display";
        case SH_PRESENTATION_COMMAND_FADE_START:
            return "fade-start";
        case SH_PRESENTATION_COMMAND_DRAW_BOOT_LOGO:
            return "draw-boot-logo";
        case SH_PRESENTATION_COMMAND_PRESENT_FRAME:
            return "present-frame";
        default:
            return "unknown";
    }
}

ShResult sh_presentation_emit(
    ShRuntime* runtime,
    const ShPresentationCommand* command)
{
    ShPresentationQueue* queue;
    uint32_t index;

    if (runtime == NULL || command == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    queue = &runtime->presentation;
    queue->emitted_count++;

    if (queue->count >= SH_PRESENTATION_QUEUE_CAPACITY)
    {
        queue->dropped_count++;
        return SH_RESULT_BUFFER_TOO_SMALL;
    }

    index =
        (queue->head + queue->count) %
        SH_PRESENTATION_QUEUE_CAPACITY;
    queue->commands[index] = *command;
    queue->commands[index].struct_size =
        (uint32_t)sizeof(ShPresentationCommand);
    queue->commands[index].abi_version =
        SH_ABI_VERSION_CURRENT;
    queue->count++;
    return SH_RESULT_OK;
}

ShResult sh_runtime_presentation_pop(
    ShRuntime* runtime,
    ShPresentationCommand* out_command)
{
    ShPresentationQueue* queue;

    if (runtime == NULL || out_command == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_runtime_is_ready(runtime))
    {
        return SH_RESULT_NOT_READY;
    }

    if (!sh_runtime_size_is_supported(
            out_command->struct_size,
            sizeof(ShPresentationCommand)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_command->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    queue = &runtime->presentation;

    if (queue->count == 0u)
    {
        return SH_RESULT_NOT_FOUND;
    }

    *out_command = queue->commands[queue->head];
    queue->head =
        (queue->head + 1u) % SH_PRESENTATION_QUEUE_CAPACITY;
    queue->count--;
    queue->popped_count++;
    return SH_RESULT_OK;
}

ShResult sh_runtime_presentation_get_stats(
    const ShRuntime* runtime,
    ShPresentationStats* out_stats)
{
    if (runtime == NULL || out_stats == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_runtime_is_ready(runtime))
    {
        return SH_RESULT_NOT_READY;
    }

    if (!sh_runtime_size_is_supported(
            out_stats->struct_size,
            sizeof(ShPresentationStats)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_stats->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    out_stats->struct_size =
        (uint32_t)sizeof(ShPresentationStats);
    out_stats->abi_version = SH_ABI_VERSION_CURRENT;
    out_stats->pending_count = runtime->presentation.count;
    out_stats->capacity = SH_PRESENTATION_QUEUE_CAPACITY;
    out_stats->emitted_count = runtime->presentation.emitted_count;
    out_stats->popped_count = runtime->presentation.popped_count;
    out_stats->dropped_count = runtime->presentation.dropped_count;
    return SH_RESULT_OK;
}
