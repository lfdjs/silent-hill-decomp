#include "../../ports/pc/sh_pc_app.h"

#include <assert.h>
#include <stdint.h>

static void test_diagnostic_host(void)
{
    ShPcApp app;
    ShInputButtons button = 0u;
    uint32_t idx;

    assert(sh_pc_app_init(NULL, NULL, NULL, NULL) ==
        SH_RESULT_INVALID_ARGUMENT);
    assert(sh_pc_app_init(&app, NULL, NULL, NULL) == SH_RESULT_OK);
    assert(app.snapshot.state == SH_GAME_STATE_INIT);
    for (idx = 0u; idx < 300u && !app.reached_unsupported; idx++)
    {
        if (app.snapshot.state == SH_GAME_STATE_KONAMI_LOGO &&
            app.snapshot.state_steps[0] == 2u)
        {
            button = SH_INPUT_BUTTON_START;
        }
        assert(sh_pc_app_tick(&app, button) == SH_RESULT_OK);
    }
    assert(app.reached_unsupported);
    assert(app.snapshot.state == SH_GAME_STATE_KCET_LOGO);
    assert(app.audio_160_count == UINT64_C(1));
    assert(app.audio_162_count == UINT64_C(1));
    assert(app.audio_commands == UINT64_C(2));
    assert(app.frames > UINT64_C(0));
    assert(app.video_commands > app.frames);
    assert(sh_pc_app_tick(&app, 0u) == SH_RESULT_INVALID_STATE);
    sh_pc_app_destroy(&app);
    assert(app.runtime == NULL);
}

int main(void)
{
    test_diagnostic_host();
    return 0;
}
