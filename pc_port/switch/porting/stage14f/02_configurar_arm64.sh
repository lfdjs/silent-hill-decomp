#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${SH_PILOT_ROOT:-$HOME/Documentos/projetos_decompilacao/_silent_hill_playable_pilot}"
REPO="${SH_REPO:-$ROOT/source-20261012T230037Z}"
OVERLAY="$ROOT/switch-14f-psycross-overlay"
WRAPPER="$ROOT/switch-14f-psycross-wrapper"
OUT="$ROOT/switch-14f-psycross-build"
LOGS="$ROOT/switch-14f-logs"
mkdir -p "$LOGS"
[[ -f "$OVERLAY/.stage14f-overlay.json" && -f "$WRAPPER/CMakeLists.txt" ]] || { echo 'Execute o preparo do overlay primeiro'; exit 10; }
export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
export DEVKITA64="${DEVKITA64:-$DEVKITPRO/devkitA64}"
export PATH="$DEVKITA64/bin:$DEVKITPRO/tools/bin:$PATH"
[[ -f "$DEVKITPRO/switchvars.sh" ]] || { echo 'Faltando switchvars.sh'; exit 11; }
source "$DEVKITPRO/switchvars.sh"
command -v aarch64-none-elf-cmake >/dev/null || { echo 'Faltando aarch64-none-elf-cmake'; exit 12; }
PKG="$(command -v aarch64-none-elf-pkg-config)"
"$PKG" --modversion sdl2 | tee "$LOGS/sdl2-version.txt"
"$PKG" --modversion openal | tee "$LOGS/openal-version.txt"
set +e
aarch64-none-elf-cmake -S "$WRAPPER" -B "$OUT" -G 'Unix Makefiles' \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=OFF \
  -DPKG_CONFIG_EXECUTABLE="$PKG" \
  -DCMAKE_PREFIX_PATH="${PORTLIBS:-$DEVKITPRO/portlibs/switch}" \
  2>&1 | tee "$LOGS/psycross-configure.log"
RC=${PIPESTATUS[0]}; set -e
printf 'phase=psycross-configure exit=%d\n' "$RC" | tee "$LOGS/psycross-configure.status"
exit "$RC"
