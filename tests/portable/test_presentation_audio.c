#include "silent_hill/sh_api.h"

#include <assert.h>
#include <string.h>

static ShRuntime* create_runtime(void)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntime* runtime = NULL;

    timing.start_paused = true;
    config.host = &host;
    config.timing = &timing;
    assert(sh_runtime_create(&config, &runtime) == SH_RESULT_OK);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);
    assert(sh_runtime_game_enable_reference(runtime) == SH_RESULT_OK);
    return runtime;
}

static void step(ShRuntime* runtime)
{
    ShAdvanceInfo info = SH_ADVANCE_INFO_INIT;
    assert(sh_runtime_step(runtime, &info) == SH_RESULT_OK);
}

int main(void)
{
    ShRuntime* runtime = create_runtime();
    ShGameBootSignals boot = SH_GAME_BOOT_SIGNALS_INIT;
    ShPresentationCommand present = SH_PRESENTATION_COMMAND_INIT;
    ShAudioCommand audio = SH_AUDIO_COMMAND_INIT;
    ShPresentationStats present_stats = SH_PRESENTATION_STATS_INIT;
    ShAudioStats audio_stats = SH_AUDIO_STATS_INIT;

    assert(strcmp(sh_presentation_command_name(SH_PRESENTATION_COMMAND_FADE_START), "fade-start") == 0);
    assert(strcmp(sh_audio_command_name(SH_AUDIO_COMMAND_TASK), "task") == 0);

    boot.audio_streaming_idle = true;
    assert(sh_runtime_game_set_boot_signals(runtime, &boot) == SH_RESULT_OK);

    step(runtime);
    assert(sh_runtime_presentation_pop(runtime, &present) == SH_RESULT_OK);
    assert(present.type == SH_PRESENTATION_COMMAND_CONFIGURE_DISPLAY);
    assert(present.tick_index == 1u);
    assert(present.width == 320u);
    assert(present.height == 240u);
    assert(!present.interlaced);
    present = (ShPresentationCommand)SH_PRESENTATION_COMMAND_INIT;
    assert(sh_runtime_presentation_pop(runtime, &present) == SH_RESULT_NOT_FOUND);

    step(runtime);
    assert(sh_runtime_audio_pop(runtime, &audio) == SH_RESULT_OK);
    assert(audio.type == SH_AUDIO_COMMAND_TASK);
    assert(audio.tick_index == 2u);
    assert(audio.task_id == 160u);

    audio = (ShAudioCommand)SH_AUDIO_COMMAND_INIT;
    step(runtime);
    assert(sh_runtime_audio_pop(runtime, &audio) == SH_RESULT_OK);
    assert(audio.tick_index == 3u);
    assert(audio.task_id == 162u);

    step(runtime);
    step(runtime);
    present = (ShPresentationCommand)SH_PRESENTATION_COMMAND_INIT;
    assert(sh_runtime_presentation_pop(runtime, &present) == SH_RESULT_OK);
    assert(present.type == SH_PRESENTATION_COMMAND_FADE_START);
    assert(present.tick_index == 5u);
    assert(present.fade_arg0);
    assert(!present.fade_arg1);
    assert(!present.fade_arg2);
    assert(!present.fade_timestep_valid);

    boot.fade_finished = true;
    boot.file_queue_empty = true;
    assert(sh_runtime_game_set_boot_signals(runtime, &boot) == SH_RESULT_OK);
    step(runtime);
    step(runtime);

    present = (ShPresentationCommand)SH_PRESENTATION_COMMAND_INIT;
    assert(sh_runtime_presentation_pop(runtime, &present) == SH_RESULT_OK);
    assert(present.type == SH_PRESENTATION_COMMAND_CONFIGURE_DISPLAY);
    assert(present.tick_index == 7u);
    assert(present.width == 640u);
    assert(present.interlaced);

    present = (ShPresentationCommand)SH_PRESENTATION_COMMAND_INIT;
    assert(sh_runtime_presentation_pop(runtime, &present) == SH_RESULT_OK);
    assert(present.type == SH_PRESENTATION_COMMAND_FADE_START);
    assert(present.fade_arg0 && present.fade_arg1 && !present.fade_arg2);
    assert(present.fade_timestep_valid);
    assert(present.fade_timestep_q12 == 819);

    present = (ShPresentationCommand)SH_PRESENTATION_COMMAND_INIT;
    assert(sh_runtime_presentation_pop(runtime, &present) == SH_RESULT_OK);
    assert(present.type == SH_PRESENTATION_COMMAND_DRAW_BOOT_LOGO);
    assert(present.boot_logo == SH_BOOT_LOGO_KONAMI);

    present = (ShPresentationCommand)SH_PRESENTATION_COMMAND_INIT;
    assert(sh_runtime_presentation_pop(runtime, &present) == SH_RESULT_OK);
    assert(present.type == SH_PRESENTATION_COMMAND_PRESENT_FRAME);

    assert(sh_runtime_presentation_get_stats(runtime, &present_stats) == SH_RESULT_OK);
    assert(present_stats.pending_count == 0u);
    assert(present_stats.capacity == 64u);
    assert(present_stats.emitted_count == 6u);
    assert(present_stats.popped_count == 6u);
    assert(present_stats.dropped_count == 0u);

    assert(sh_runtime_audio_get_stats(runtime, &audio_stats) == SH_RESULT_OK);
    assert(audio_stats.pending_count == 0u);
    assert(audio_stats.capacity == 32u);
    assert(audio_stats.emitted_count == 2u);
    assert(audio_stats.popped_count == 2u);
    assert(audio_stats.dropped_count == 0u);

    sh_runtime_destroy(runtime);
    return 0;
}
