#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stdint.h>

typedef struct TickRecorder
{
    uint64_t count;
    uint64_t last_tick;
} TickRecorder;

static void record_tick(
    void* userdata,
    uint64_t tick_index)
{
    TickRecorder* recorder = (TickRecorder*)userdata;

    assert(recorder != NULL);
    assert(tick_index == recorder->last_tick + 1u);

    recorder->count++;
    recorder->last_tick = tick_index;
}

static ShRuntime* create_runtime(
    TickRecorder* recorder,
    bool start_paused)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntime* runtime = NULL;

    timing.start_paused = start_paused;
    timing.tick = record_tick;
    timing.tick_userdata = recorder;

    config.host = &host;
    config.timing = &timing;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_OK);

    assert(runtime != NULL);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);

    return runtime;
}

static void test_exact_sixty_ticks_per_second(void)
{
    TickRecorder recorder = { 0u, 0u };
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime = create_runtime(&recorder, false);
    uint32_t idx;

    for (idx = 0u; idx < 40u; idx++)
    {
        assert(
            sh_runtime_advance(
                runtime,
                UINT64_C(16667),
                NULL) == SH_RESULT_OK);
    }

    for (idx = 0u; idx < 20u; idx++)
    {
        assert(
            sh_runtime_advance(
                runtime,
                UINT64_C(16666),
                NULL) == SH_RESULT_OK);
    }

    assert(
        sh_runtime_get_stats(runtime, &stats) ==
        SH_RESULT_OK);

    assert(stats.update_count == UINT64_C(60));
    assert(stats.total_elapsed_us == UINT64_C(1000000));
    assert(stats.accepted_elapsed_us == UINT64_C(1000000));
    assert(stats.dropped_elapsed_us == UINT64_C(0));
    assert(stats.tick_count == UINT64_C(60));
    assert(stats.interpolation_units == 0u);

    assert(recorder.count == UINT64_C(60));
    assert(recorder.last_tick == UINT64_C(60));

    sh_runtime_destroy(runtime);
}

static void test_subdivision_equivalence(void)
{
    TickRecorder recorder_a = { 0u, 0u };
    TickRecorder recorder_b = { 0u, 0u };
    ShRuntimeStats stats_a = SH_RUNTIME_STATS_INIT;
    ShRuntimeStats stats_b = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime_a = create_runtime(&recorder_a, false);
    ShRuntime* runtime_b = create_runtime(&recorder_b, false);
    static const uint64_t irregular[] = {
        UINT64_C(1000),
        UINT64_C(19000),
        UINT64_C(7000),
        UINT64_C(41000),
        UINT64_C(32000)
    };
    size_t idx;

    for (idx = 0u;
         idx < (sizeof(irregular) / sizeof(irregular[0]));
         idx++)
    {
        assert(
            sh_runtime_advance(
                runtime_a,
                irregular[idx],
                NULL) == SH_RESULT_OK);
    }

    for (idx = 0u; idx < 100u; idx++)
    {
        assert(
            sh_runtime_advance(
                runtime_b,
                UINT64_C(1000),
                NULL) == SH_RESULT_OK);
    }

    assert(
        sh_runtime_get_stats(runtime_a, &stats_a) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_get_stats(runtime_b, &stats_b) ==
        SH_RESULT_OK);

    assert(stats_a.total_elapsed_us == UINT64_C(100000));
    assert(stats_b.total_elapsed_us == UINT64_C(100000));

    assert(stats_a.tick_count == stats_b.tick_count);
    assert(
        stats_a.interpolation_units ==
        stats_b.interpolation_units);

    assert(stats_a.tick_count == UINT64_C(6));
    assert(stats_a.interpolation_units == 0u);

    assert(recorder_a.count == recorder_b.count);
    assert(recorder_a.last_tick == recorder_b.last_tick);

    sh_runtime_destroy(runtime_a);
    sh_runtime_destroy(runtime_b);
}

static void test_long_frame_clamp(void)
{
    TickRecorder recorder = { 0u, 0u };
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime = create_runtime(&recorder, false);

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(1000000),
            &advance) == SH_RESULT_OK);

    assert(advance.input_elapsed_us == UINT64_C(1000000));
    assert(advance.accepted_elapsed_us == UINT64_C(133333));
    assert(advance.dropped_elapsed_us == UINT64_C(866667));
    assert(advance.paused_elapsed_us == UINT64_C(0));
    assert(advance.ticks_executed == 7u);
    assert(advance.interpolation_units == 999980u);
    assert(advance.tick_count_before == UINT64_C(0));
    assert(advance.tick_count_after == UINT64_C(7));
    assert(!advance.paused);

    advance = (ShAdvanceInfo)SH_ADVANCE_INFO_INIT;

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(1),
            &advance) == SH_RESULT_OK);

    assert(advance.ticks_executed == 1u);
    assert(advance.interpolation_units == 40u);
    assert(advance.tick_count_before == UINT64_C(7));
    assert(advance.tick_count_after == UINT64_C(8));

    assert(
        sh_runtime_get_stats(runtime, &stats) ==
        SH_RESULT_OK);

    assert(stats.total_elapsed_us == UINT64_C(1000001));
    assert(stats.accepted_elapsed_us == UINT64_C(133334));
    assert(stats.dropped_elapsed_us == UINT64_C(866667));
    assert(stats.tick_count == UINT64_C(8));
    assert(stats.interpolation_units == 40u);

    sh_runtime_destroy(runtime);
}

static void test_pause_and_single_step(void)
{
    TickRecorder recorder = { 0u, 0u };
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime = create_runtime(&recorder, true);

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(50000),
            &advance) == SH_RESULT_OK);

    assert(advance.ticks_executed == 0u);
    assert(advance.accepted_elapsed_us == UINT64_C(0));
    assert(advance.dropped_elapsed_us == UINT64_C(0));
    assert(advance.paused_elapsed_us == UINT64_C(50000));
    assert(advance.paused);
    assert(recorder.count == UINT64_C(0));

    advance = (ShAdvanceInfo)SH_ADVANCE_INFO_INIT;

    assert(
        sh_runtime_step(runtime, &advance) ==
        SH_RESULT_OK);

    assert(advance.ticks_executed == 1u);
    assert(advance.tick_count_before == UINT64_C(0));
    assert(advance.tick_count_after == UINT64_C(1));
    assert(advance.paused);
    assert(recorder.count == UINT64_C(1));

    assert(
        sh_runtime_set_paused(runtime, false) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_step(runtime, NULL) ==
        SH_RESULT_INVALID_STATE);

    advance = (ShAdvanceInfo)SH_ADVANCE_INFO_INIT;

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(16667),
            &advance) == SH_RESULT_OK);

    assert(advance.ticks_executed == 1u);
    assert(advance.interpolation_units == 20u);
    assert(!advance.paused);

    assert(
        sh_runtime_get_stats(runtime, &stats) ==
        SH_RESULT_OK);

    assert(stats.update_count == UINT64_C(3));
    assert(stats.total_elapsed_us == UINT64_C(66667));
    assert(stats.accepted_elapsed_us == UINT64_C(16667));
    assert(stats.paused_elapsed_us == UINT64_C(50000));
    assert(stats.tick_count == UINT64_C(2));
    assert(stats.interpolation_units == 20u);
    assert(!stats.paused);

    sh_runtime_destroy(runtime);
}

static void test_overflow_is_reported_without_second_update(void)
{
    TickRecorder recorder = { 0u, 0u };
    ShRuntimeStats before = SH_RUNTIME_STATS_INIT;
    ShRuntimeStats after = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime = create_runtime(&recorder, false);

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_MAX,
            NULL) == SH_RESULT_OK);

    assert(
        sh_runtime_get_stats(runtime, &before) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(1),
            NULL) == SH_RESULT_OVERFLOW);

    assert(
        sh_runtime_get_stats(runtime, &after) ==
        SH_RESULT_OK);

    assert(after.update_count == before.update_count);
    assert(after.total_elapsed_us == before.total_elapsed_us);
    assert(after.tick_count == before.tick_count);
    assert(
        after.interpolation_units ==
        before.interpolation_units);

    sh_runtime_destroy(runtime);
}

static void test_advance_info_validation(void)
{
    TickRecorder recorder = { 0u, 0u };
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime = create_runtime(&recorder, false);

    advance.struct_size = 1u;

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(1000),
            &advance) == SH_RESULT_INVALID_ARGUMENT);

    advance = (ShAdvanceInfo)SH_ADVANCE_INFO_INIT;
    advance.abi_version = UINT32_C(0xFFFFFFFF);

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(1000),
            &advance) == SH_RESULT_UNSUPPORTED_VERSION);

    assert(
        sh_runtime_get_stats(runtime, &stats) ==
        SH_RESULT_OK);

    assert(stats.update_count == UINT64_C(0));
    assert(stats.total_elapsed_us == UINT64_C(0));
    assert(stats.tick_count == UINT64_C(0));

    sh_runtime_destroy(runtime);
}

int main(void)
{
    test_exact_sixty_ticks_per_second();
    test_subdivision_equivalence();
    test_long_frame_clamp();
    test_pause_and_single_step();
    test_overflow_is_reported_without_second_update();
    test_advance_info_validation();

    return 0;
}
