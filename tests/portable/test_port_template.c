#include "../../ports/platform-template/sh_port_template.h"

#include <assert.h>
#include <stdint.h>

typedef struct Sink
{
    uint32_t video;
    uint32_t audio;
    uint32_t transitions;
    uint32_t audio_160;
    uint32_t audio_162;
    uint32_t frames;
} Sink;

static ShInputButtons read_buttons(void* userdata)
{
    (void)userdata;
    return 0u;
}

static void video(void* userdata, const ShPresentationCommand* command)
{
    Sink* sink = (Sink*)userdata;
    sink->video++;
    if (command->type == SH_PRESENTATION_COMMAND_PRESENT_FRAME)
    {
        sink->frames++;
    }
}

static void audio(void* userdata, const ShAudioCommand* command)
{
    Sink* sink = (Sink*)userdata;
    sink->audio++;
    if (command->type == SH_AUDIO_COMMAND_TASK && command->task_id == 160u)
    {
        sink->audio_160++;
    }
    if (command->type == SH_AUDIO_COMMAND_TASK && command->task_id == 162u)
    {
        sink->audio_162++;
    }
}

static void transition(void* userdata, ShGameState from, ShGameState to)
{
    Sink* sink = (Sink*)userdata;
    (void)from;
    (void)to;
    sink->transitions++;
}

static void check_lifecycle(void)
{
    ShPortTemplate port = {0};
    ShPortHooks hooks = {0};
    Sink sink = {0};
    ShResult result;
    uint32_t idx;

    hooks.userdata = &sink;
    hooks.poll_buttons = read_buttons;
    hooks.on_video = video;
    hooks.on_audio = audio;
    hooks.on_transition = transition;

    assert(sh_port_template_tick(NULL) == SH_RESULT_INVALID_ARGUMENT);
    assert(sh_port_template_tick(&port) == SH_RESULT_INVALID_ARGUMENT);
    assert(sh_port_template_init(NULL, &hooks) == SH_RESULT_INVALID_ARGUMENT);
    assert(sh_port_template_init(&port, &hooks) == SH_RESULT_OK);
    assert(sh_port_template_init(&port, &hooks) == SH_RESULT_INVALID_STATE);

    for (idx = 0u; idx < 300u && !port.reached_unsupported; idx++)
    {
        result = sh_port_template_tick(&port);
        assert(result == SH_RESULT_OK);
    }

    assert(port.reached_unsupported);
    assert(port.snapshot.state == SH_GAME_STATE_KCET_LOGO);
    assert(port.ticks == UINT64_C(213));
    assert(port.frames == UINT64_C(194));
    assert(port.audio_commands == UINT64_C(2));
    assert(sink.audio_160 == 1u && sink.audio_162 == 1u);
    assert(sink.transitions == 2u);
    assert(sink.video == port.video_commands);
    assert(sink.audio == port.audio_commands);
    assert(sink.frames == port.frames);
    assert(sh_port_template_tick(&port) == SH_RESULT_INVALID_STATE);

    sh_port_template_destroy(&port);
    assert(port.runtime == NULL);
    assert(sh_port_template_init(&port, NULL) == SH_RESULT_OK);
    sh_port_template_destroy(&port);
    sh_port_template_destroy(&port);
}

int main(void)
{
    check_lifecycle();
    return 0;
}
