/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef SH_SWITCH_PROFILE_H
#define SH_SWITCH_PROFILE_H

/* Independent of libnx headers so policy is unit-testable on Linux. */
typedef struct ShSwitchProfile {
    int width;
    int height;
    int target_fps;
    int vsync;
    int msaa_samples;
    int pgxp_enabled;
} ShSwitchProfile;

/* docked = 0: 1280x720, docked != 0: 1920x1080.
 * Runtime MSAA changing requires context recreation; mode transitions only
 * update presentation resolution. This profile is aspirational, not a GPU
 * performance guarantee. PGXP is disabled because upstream USE_PGXP=0. */
ShSwitchProfile ShSwitch_ProfileForMode(int docked);

#ifdef SH_SWITCH
/* Call after PcConfig_Load, before PsyX_Initialise. */
void ShSwitch_ApplyStartupConfig(void);
/* Call from the original game loop once per frame on the main thread. */
void ShSwitch_PollDisplayMode(void);
#endif

#endif
