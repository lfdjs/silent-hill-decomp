#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stdint.h>

static ShRuntime* create_runtime(uint16_t deadzone)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShInputConfig input = SH_INPUT_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntime* runtime = NULL;

    input.analog_deadzone = deadzone;

    config.host = &host;
    config.input = &input;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_OK);

    assert(runtime != NULL);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);

    return runtime;
}

static void run_one_tick(ShRuntime* runtime)
{
    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(16667),
            NULL) == SH_RESULT_OK);
}

static void test_deadzone_function(void)
{
    assert(
        sh_input_apply_deadzone(
            INT16_C(4096),
            UINT16_C(4096)) == 0);

    assert(
        sh_input_apply_deadzone(
            INT16_C(-4096),
            UINT16_C(4096)) == 0);

    assert(
        sh_input_apply_deadzone(
            INT16_C(32767),
            UINT16_C(4096)) == INT16_C(32767));

    assert(
        sh_input_apply_deadzone(
            INT16_C(-32768),
            UINT16_C(4096)) == INT16_C(-32767));

    assert(
        sh_input_apply_deadzone(
            INT16_C(10000),
            UINT16_C(4096)) > 0);
}

static void test_pressed_held_and_released(void)
{
    ShRuntime* runtime = create_runtime(0u);
    ShInputState input = SH_INPUT_STATE_INIT;
    ShInputSnapshot snapshot = SH_INPUT_SNAPSHOT_INIT;

    input.connected = true;
    input.buttons =
        SH_INPUT_BUTTON_CROSS |
        SH_INPUT_BUTTON_UP;

    assert(
        sh_runtime_submit_input(runtime, &input) ==
        SH_RESULT_OK);

    run_one_tick(runtime);

    assert(
        sh_runtime_get_input(runtime, &snapshot) ==
        SH_RESULT_OK);

    assert(snapshot.tick_index == UINT64_C(1));
    assert(snapshot.connected);
    assert(snapshot.buttons == input.buttons);
    assert(snapshot.pressed == input.buttons);
    assert(snapshot.released == 0u);

    run_one_tick(runtime);

    snapshot = (ShInputSnapshot)SH_INPUT_SNAPSHOT_INIT;

    assert(
        sh_runtime_get_input(runtime, &snapshot) ==
        SH_RESULT_OK);

    assert(snapshot.tick_index == UINT64_C(2));
    assert(snapshot.buttons == input.buttons);
    assert(snapshot.pressed == 0u);
    assert(snapshot.released == 0u);

    input.buttons = SH_INPUT_BUTTON_UP;

    assert(
        sh_runtime_submit_input(runtime, &input) ==
        SH_RESULT_OK);

    run_one_tick(runtime);

    snapshot = (ShInputSnapshot)SH_INPUT_SNAPSHOT_INIT;

    assert(
        sh_runtime_get_input(runtime, &snapshot) ==
        SH_RESULT_OK);

    assert(snapshot.tick_index == UINT64_C(3));
    assert(snapshot.buttons == SH_INPUT_BUTTON_UP);
    assert(snapshot.pressed == 0u);
    assert(
        snapshot.released ==
        SH_INPUT_BUTTON_CROSS);

    input.connected = false;
    input.buttons = SH_INPUT_BUTTON_SQUARE;
    input.left_x = INT16_C(20000);

    assert(
        sh_runtime_submit_input(runtime, &input) ==
        SH_RESULT_OK);

    run_one_tick(runtime);

    snapshot = (ShInputSnapshot)SH_INPUT_SNAPSHOT_INIT;

    assert(
        sh_runtime_get_input(runtime, &snapshot) ==
        SH_RESULT_OK);

    assert(!snapshot.connected);
    assert(snapshot.buttons == 0u);
    assert(snapshot.left_x == 0);
    assert(
        snapshot.released ==
        SH_INPUT_BUTTON_UP);

    sh_runtime_destroy(runtime);
}

static void test_analog_filtering_and_validation(void)
{
    ShRuntime* runtime =
        create_runtime(SH_INPUT_DEFAULT_DEADZONE);

    ShInputState input = SH_INPUT_STATE_INIT;
    ShInputSnapshot snapshot = SH_INPUT_SNAPSHOT_INIT;

    input.connected = true;
    input.left_x = INT16_C(4096);
    input.left_y = INT16_C(20000);
    input.right_x = INT16_C(-20000);
    input.right_y = INT16_C(32767);

    assert(
        sh_runtime_submit_input(runtime, &input) ==
        SH_RESULT_OK);

    run_one_tick(runtime);

    assert(
        sh_runtime_get_input(runtime, &snapshot) ==
        SH_RESULT_OK);

    assert(snapshot.left_x == 0);
    assert(snapshot.left_y > 0);
    assert(snapshot.right_x < 0);
    assert(snapshot.right_y == INT16_C(32767));

    input.buttons = UINT64_C(1) << 63u;

    assert(
        sh_runtime_submit_input(runtime, &input) ==
        SH_RESULT_INVALID_ARGUMENT);

    input = (ShInputState)SH_INPUT_STATE_INIT;
    input.abi_version = UINT32_C(0xFFFFFFFF);

    assert(
        sh_runtime_submit_input(runtime, &input) ==
        SH_RESULT_UNSUPPORTED_VERSION);

    sh_runtime_destroy(runtime);
}

static void test_deterministic_replay(void)
{
    ShRuntime* runtime_a = create_runtime(2048u);
    ShRuntime* runtime_b = create_runtime(2048u);
    ShInputState input = SH_INPUT_STATE_INIT;
    ShInputSnapshot a = SH_INPUT_SNAPSHOT_INIT;
    ShInputSnapshot b = SH_INPUT_SNAPSHOT_INIT;
    uint32_t tick;

    input.connected = true;

    for (tick = 0u; tick < 120u; tick++)
    {
        input.buttons =
            (tick % 3u) == 0u ?
            SH_INPUT_BUTTON_CROSS :
            0u;

        input.left_x =
            (int16_t)((int32_t)tick * 200 - 12000);

        assert(
            sh_runtime_submit_input(runtime_a, &input) ==
            SH_RESULT_OK);

        assert(
            sh_runtime_submit_input(runtime_b, &input) ==
            SH_RESULT_OK);

        run_one_tick(runtime_a);
        run_one_tick(runtime_b);

        a = (ShInputSnapshot)SH_INPUT_SNAPSHOT_INIT;
        b = (ShInputSnapshot)SH_INPUT_SNAPSHOT_INIT;

        assert(
            sh_runtime_get_input(runtime_a, &a) ==
            SH_RESULT_OK);

        assert(
            sh_runtime_get_input(runtime_b, &b) ==
            SH_RESULT_OK);

        assert(a.tick_index == b.tick_index);
        assert(a.connected == b.connected);
        assert(a.buttons == b.buttons);
        assert(a.pressed == b.pressed);
        assert(a.released == b.released);
        assert(a.left_x == b.left_x);
        assert(a.left_y == b.left_y);
        assert(a.right_x == b.right_x);
        assert(a.right_y == b.right_y);
    }

    sh_runtime_destroy(runtime_a);
    sh_runtime_destroy(runtime_b);
}

int main(void)
{
    test_deadzone_function();
    test_pressed_held_and_released();
    test_analog_filtering_and_validation();
    test_deterministic_replay();

    return 0;
}
