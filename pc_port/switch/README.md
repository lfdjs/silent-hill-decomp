# Stage 14A.2 — Ryubing logging executable (Nintendo Switch homebrew)

This is an **ARM64 / Horizon `.nro` diagnostic**, not a playable Silent Hill build.
It tests rendering, SDL2 controller input, audio, and writable `sdmc:` from Ryubing
or a homebrew-enabled Nintendo Switch. It does not contain or read game assets;
checking the optional game image just attempts read-only `fopen`.

## Requirements

Install [devkitPro](https://devkitpro.org/wiki/devkitPro_pacman) with the Switch
package group and `switch-sdl2`, `switch-mesa`, and `switch-openal-soft`.
On an already configured Linux machine:

```bash
sudo dkp-pacman -S --needed switch-dev switch-sdl2 switch-mesa switch-openal-soft
```

The developer machine **must** contain `/opt/devkitpro/switchvars.sh`,
`/opt/devkitpro/libnx/switch_rules` and `aarch64-none-elf-gcc`. This is independent
of whether you own a console. The previous trial halted during toolchain checking,
so no working `.nro` has been observed yet.

## One-command build and report

From the repository root:

```bash
./pc_port/switch/build-and-report.sh
```

The script captures the full output, produces a report tarball and, on success,
copies `SilentHillSwitchProbe.nro` into `~/Downloads/` ready to load in Ryubing.
It does **not** commit or push changes and doesn't build the full game.

## Ryubing

Select **File → Load Application From File** (or your version's equivalent),
then open `~/Downloads/SilentHillSwitchProbe.nro`. The program displays five
labeled status bars and automatically stops after approximately **30 seconds**,
so no controller is required to finish a diagnostic run. Use **A / Enter** to
change the background and test audio; **+ / Escape** exits early. It writes a
heartbeat every five seconds, input events and initialization results.

Persistent log path, **if `sdmc:` is writable in this emulator setup**:

`sdmc:/switch/SilentHillSwitch/probe.log`

If Ryubing does not mount or expose a writable SD virtual filesystem for a
standalone NRO, the on-screen **SD LOG** bar displays `FAIL`. In that case the
app duplicates diagnostics to `SDL_Log` (look in Ryubing logs). Writing a log to
`sdmc:` cannot be guaranteed where the emulator does not provide that service.
To gather recent emulator logs for review:

```bash
./pc_port/switch/collect-ryubing-logs.sh
```

Do not share game disc images, keys or other copyrighted/security-sensitive files.
Review any emulator log before sharing: it may contain your filesystem paths.

## What this validates

- ARM64 Switch app can start in Ryubing;
- accelerated SDL2 video **or explicitly logged software fallback**;
- SDL2 controller recognition (and keyboard events if forwarded);
- optional 48 kHz stereo SDL2 audio;
- optional SD log output, with SDL fallback;
- startup, periodic heartbeats, exit and status reporting.

**Not yet validated:** PsyCross, GTE/GPU engine, static overlays, original maps,
loading a disc, menus, or controlling Harry in an ARM64 build.

Licensing: GPL-3.0-or-later for this port-specific code. Follow the repository
`COPYRIGHT.md`; Konami's original game assets are not distributed.
