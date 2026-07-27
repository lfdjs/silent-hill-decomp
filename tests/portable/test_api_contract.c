#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stdint.h>
#include <string.h>

typedef struct TestHost
{
    uint32_t log_count;
    ShLogLevel last_level;
    const char* last_message;
} TestHost;

static uint64_t test_time_now_us(void* userdata)
{
    (void)userdata;
    return UINT64_C(123456);
}

static void test_log(
    void* userdata,
    ShLogLevel level,
    const char* message)
{
    TestHost* host = (TestHost*)userdata;

    assert(host != NULL);
    assert(message != NULL);

    host->log_count++;
    host->last_level = level;
    host->last_message = message;
}

static void test_invalid_arguments(void)
{
    ShRuntime* runtime = (ShRuntime*)(uintptr_t)1u;
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;

    config.host = &host;

    assert(
        sh_runtime_create(NULL, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);

    assert(runtime == NULL);

    assert(
        sh_runtime_create(&config, NULL) ==
        SH_RESULT_INVALID_ARGUMENT);

    config.host = NULL;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);

    assert(runtime == NULL);
}

static void test_version_size_and_input_validation(void)
{
    ShRuntime* runtime = NULL;
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShInputConfig input = SH_INPUT_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;

    config.host = &host;

    config.struct_size = 1u;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);

    config = (ShRuntimeConfig)SH_RUNTIME_CONFIG_INIT;
    config.host = &host;
    config.abi_version = UINT32_C(0xFFFFFFFF);

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_UNSUPPORTED_VERSION);

    config = (ShRuntimeConfig)SH_RUNTIME_CONFIG_INIT;
    host = (ShHostServices)SH_HOST_SERVICES_INIT;
    config.host = &host;
    host.struct_size = 1u;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);

    host = (ShHostServices)SH_HOST_SERVICES_INIT;
    config.host = &host;
    host.abi_version = UINT32_C(0xFFFFFFFF);

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_UNSUPPORTED_VERSION);

    host = (ShHostServices)SH_HOST_SERVICES_INIT;
    config = (ShRuntimeConfig)SH_RUNTIME_CONFIG_INIT;
    config.host = &host;
    config.timing = &timing;
    timing.max_ticks_per_advance = 1u;
    timing.max_frame_us = UINT64_C(16667);

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);

    timing = (ShTimingConfig)SH_TIMING_CONFIG_INIT;
    config.timing = &timing;
    config.input = &input;
    input.analog_deadzone = UINT16_C(32767);

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);
}

static void test_runtime_lifecycle(void)
{
    TestHost test_host = { 0u, SH_LOG_LEVEL_DEBUG, NULL };
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime = NULL;

    host.userdata = &test_host;
    host.time_now_us = test_time_now_us;
    host.log = test_log;

    config.host = &host;
    config.initial_rng_seed = UINT32_C(0x12345678);

    assert(sh_api_version() == SH_ABI_VERSION_CURRENT);

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_OK);

    assert(runtime != NULL);

    assert(
        sh_runtime_update(runtime, UINT64_C(16667)) ==
        SH_RESULT_NOT_READY);

    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);

    assert(test_host.log_count == 1u);
    assert(test_host.last_level == SH_LOG_LEVEL_INFO);
    assert(test_host.last_message != NULL);

    assert(
        strcmp(
            test_host.last_message,
            "silent_hill_core: runtime booted") == 0);

    assert(
        sh_runtime_update(runtime, UINT64_C(16667)) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_update(runtime, UINT64_C(33333)) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_get_stats(runtime, &stats) ==
        SH_RESULT_OK);

    assert(stats.struct_size == (uint32_t)sizeof(stats));
    assert(stats.abi_version == SH_ABI_VERSION_CURRENT);
    assert(stats.update_count == UINT64_C(2));
    assert(stats.total_elapsed_us == UINT64_C(50000));
    assert(stats.tick_count == UINT64_C(3));
    assert(stats.accepted_elapsed_us == UINT64_C(50000));
    assert(stats.dropped_elapsed_us == UINT64_C(0));
    assert(stats.paused_elapsed_us == UINT64_C(0));
    assert(stats.interpolation_units == 0u);
    assert(stats.last_advance_ticks == 2u);
    assert(stats.booted);
    assert(!stats.paused);

    sh_runtime_destroy(runtime);
    sh_runtime_destroy(NULL);
}

static void test_result_strings(void)
{
    assert(strcmp(sh_result_string(SH_RESULT_OK), "ok") == 0);

    assert(
        strcmp(
            sh_result_string(SH_RESULT_UNSUPPORTED),
            "unsupported") == 0);

    assert(
        strcmp(
            sh_result_string(SH_RESULT_NOT_FOUND),
            "not found") == 0);

    assert(
        strcmp(
            sh_result_string(SH_RESULT_IO_ERROR),
            "I/O error") == 0);

    assert(
        strcmp(
            sh_result_string((ShResult)9999),
            "unknown result") == 0);
}

int main(void)
{
    test_invalid_arguments();
    test_version_size_and_input_validation();
    test_runtime_lifecycle();
    test_result_strings();

    return 0;
}
