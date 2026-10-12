# Stage 14A: Nintendo Switch Homebrew Preflight

**Status:** experimental platform probe only; not a port of Silent Hill gameplay.

This directory lives in the **playable PsyCross fork** to validate the Switch
hardware/toolchain before changing the existing PC engine. The Linux build
continues to use `pc_port/CMakeLists.txt` and is untouched.

## What it exercises

- `libnx` applet lifecycle + SD card mount;
- SDL2 video and its Switch EGL/OpenGL ES renderer (colored bars);
- joystick 0 / paired Joy-Con input (A changes colors and sounds; PLUS exits);
- optional SDL2 audio output at 48 kHz;
- optional *read-only visibility check* of a game disc image at
  `sdmc:/switch/SilentHillSwitch/gamedata/Silent Hill (USA).bin`.

No game data is embedded or distributed. A disc image is **not required** for
the probe and is **not decoded** here.

## Build (Linux host with devkitPro installed)

Install devkitPro through its official instructions. Then install:

```bash
sudo dkp-pacman -S --needed switch-dev switch-sdl2 switch-mesa switch-openal-soft
export DEVKITPRO=/opt/devkitpro
export DEVKITA64=$DEVKITPRO/devkitA64
export PATH="$DEVKITA64/bin:$DEVKITPRO/tools/bin:$PATH"
source "$DEVKITPRO/switchvars.sh"
make -C pc_port/switch -j2
```

Output: `pc_port/switch/SilentHillSwitchProbe.nro`. We have **not yet cross-compiled
this probe in the AI environment**; results must be confirmed with devkitPro.

## Running (homebrew environment only)

Copy `SilentHillSwitchProbe.nro` to `sdmc:/switch/SilentHillSwitch/` on your own
homebrew-enabled Switch. Run from the Homebrew Menu. The app writes:

`sdmc:/switch/SilentHillSwitch/probe.log`

The screen shows five horizontal bars (video / controller / audio / SD / optional
image). Green = functional; red = failed; grey = optional/not evaluated. Press
**A** to change the large panel color and play a brief sound; press **+** to exit.

If a console cannot run homebrew, this software does not change that; no
instructions or code for bypassing device security are provided.

## Why this is not the complete port

The game is currently native x86-64 code relying on desktop PsyCross renderer,
OpenAL, filesystem APIs, dynamic map overlays and 32->64 bit data conversions.
The Switch needs ARM64 Horizon binaries (`.nro`), GLES-compatible PsyCross,
static map overlays (`SH_STATIC_MAPS`), Switch filesystem, save handling and
platform input/audio validation. None of these are claimed solved by this probe.

**Next gate (14B):** compile the existing game engine + PsyCross for ARM64,
record cross-compiler errors and replace only the unsupported platform calls.
Preserve the existing Linux build as a regression baseline and the original
`portability/core-api` branch intact.

Licensing: port-specific source is GPL-3.0-or-later; follow the repo's
`COPYRIGHT.md`. Original Konami game data is never included.
