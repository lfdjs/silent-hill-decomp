/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "sh_switch_profile.h"

ShSwitchProfile ShSwitch_ProfileForMode(int docked)
{
    ShSwitchProfile profile;
    profile.width         = docked ? 1920 : 1280;
    profile.height        = docked ? 1080 : 720;
    profile.target_fps    = 60;
    profile.vsync         = 1;
    /* 8x MSAA at 1080p is not a defensible 60-FPS default on Tegra X1.
     * Start at 4x docked, 2x handheld; actual support is backend-dependent.
     */
    profile.msaa_samples  = docked ? 4 : 2;
    /* The playable port disables PGXP at compile time because of render
     * regressions. Enabling a config flag alone cannot correct this. */
    profile.pgxp_enabled  = 0;
    return profile;
}

#ifdef SH_SWITCH
#include <switch.h>
#include "pc_config.h"
#include <stdio.h>

/* Exported by the current PsyCross desktop port. Switch support for its
 * context/resize path must be implemented before the whole game will link. */
extern void PsyX_ApplyWindowState(int width, int height, int fullscreen);

static int s_last_docked = -1;
static unsigned s_poll_counter = 0;
static int s_startup_msaa = 0;

static int ShSwitch_IsDocked(void)
{
    return appletGetOperationMode() == AppletOperationMode_Console;
}

void ShSwitch_ApplyStartupConfig(void)
{
    const int docked = ShSwitch_IsDocked();
    const ShSwitchProfile profile = ShSwitch_ProfileForMode(docked);
    s_last_docked = docked;
    s_startup_msaa = profile.msaa_samples;
    g_PcConfig.windowWidth    = profile.width;
    g_PcConfig.windowHeight   = profile.height;
    g_PcConfig.fullscreen     = 0; /* No desktop-exclusive fullscreen. */
    g_PcConfig.vsync          = profile.vsync;
    g_PcConfig.refreshRate    = 60;
    g_PcConfig.fpsCap         = profile.target_fps;
    g_PcConfig.menuFpsUnlock  = 0; /* Keep original UI cadence. */
    g_PcConfig.msaaSamples    = s_startup_msaa;
    g_PcConfig.usePgxp        = profile.pgxp_enabled;
    g_PcConfig.nativeResolution = 0;
    g_PcConfig.enableDebugLog = 1;
    g_PcConfig.allowDebugControls = 0;
    g_PcConfig.showConsole    = 0;
    g_PcConfig.mouseCursor    = 0;
    fprintf(stderr, "[SH-SWITCH] startup %s %dx%d vsync=1 target=60 msaa=%dx pgxp=OFF(unavailable)\n",
            docked ? "docked" : "handheld", profile.width,
            profile.height, s_startup_msaa);
}

void ShSwitch_PollDisplayMode(void)
{
    /* Low-cost polling on the main game thread. No SD/GPU access here. */
    int docked;
    ShSwitchProfile profile;
    if ((++s_poll_counter & 31u) != 0)
        return;
    docked = ShSwitch_IsDocked();
    if (docked == s_last_docked)
        return;
    profile = ShSwitch_ProfileForMode(docked);
    s_last_docked = docked;
    g_PcConfig.windowWidth = profile.width;
    g_PcConfig.windowHeight = profile.height;
    /* Does not recreate the GL context, switch MSAA or restart gameplay.
     * The Switch-specific PsyCross backend must implement resize safely. */
    PsyX_ApplyWindowState(profile.width, profile.height, 0);
    fprintf(stderr, "[SH-SWITCH] operation mode=%s presentation=%dx%d (MSAA remains %dx until restart)\n",
            docked ? "docked" : "handheld", profile.width,
            profile.height, s_startup_msaa);
}
#endif
