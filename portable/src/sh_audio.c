#include "sh_runtime_internal.h"

#include <string.h>

void sh_audio_queue_init(ShAudioQueue* queue)
{
    if (queue != NULL)
    {
        memset(queue, 0, sizeof(*queue));
    }
}

const char* sh_audio_command_name(ShAudioCommandType type)
{
    switch (type)
    {
        case SH_AUDIO_COMMAND_NONE:
            return "none";
        case SH_AUDIO_COMMAND_TASK:
            return "task";
        default:
            return "unknown";
    }
}

ShResult sh_audio_emit(
    ShRuntime* runtime,
    const ShAudioCommand* command)
{
    ShAudioQueue* queue;
    uint32_t index;

    if (runtime == NULL || command == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    queue = &runtime->audio;
    queue->emitted_count++;

    if (queue->count >= SH_AUDIO_QUEUE_CAPACITY)
    {
        queue->dropped_count++;
        return SH_RESULT_BUFFER_TOO_SMALL;
    }

    index = (queue->head + queue->count) % SH_AUDIO_QUEUE_CAPACITY;
    queue->commands[index] = *command;
    queue->commands[index].struct_size = (uint32_t)sizeof(ShAudioCommand);
    queue->commands[index].abi_version = SH_ABI_VERSION_CURRENT;
    queue->count++;
    return SH_RESULT_OK;
}

ShResult sh_runtime_audio_pop(
    ShRuntime* runtime,
    ShAudioCommand* out_command)
{
    ShAudioQueue* queue;

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
            sizeof(ShAudioCommand)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_command->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    queue = &runtime->audio;

    if (queue->count == 0u)
    {
        return SH_RESULT_NOT_FOUND;
    }

    *out_command = queue->commands[queue->head];
    queue->head = (queue->head + 1u) % SH_AUDIO_QUEUE_CAPACITY;
    queue->count--;
    queue->popped_count++;
    return SH_RESULT_OK;
}

ShResult sh_runtime_audio_get_stats(
    const ShRuntime* runtime,
    ShAudioStats* out_stats)
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
            sizeof(ShAudioStats)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_stats->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    out_stats->struct_size = (uint32_t)sizeof(ShAudioStats);
    out_stats->abi_version = SH_ABI_VERSION_CURRENT;
    out_stats->pending_count = runtime->audio.count;
    out_stats->capacity = SH_AUDIO_QUEUE_CAPACITY;
    out_stats->emitted_count = runtime->audio.emitted_count;
    out_stats->popped_count = runtime->audio.popped_count;
    out_stats->dropped_count = runtime->audio.dropped_count;
    return SH_RESULT_OK;
}
