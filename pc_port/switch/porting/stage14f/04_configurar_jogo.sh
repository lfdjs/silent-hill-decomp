#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${SH_PILOT_ROOT:-$HOME/Documentos/projetos_decompilacao/_silent_hill_playable_pilot}"
REPO="${SH_REPO:-$ROOT/source-20261012T230037Z}"
OVERLAY="$ROOT/switch-14f-psycross-overlay"
OUT="$ROOT/switch-14f-game-build"
LOGS="$ROOT/switch-14f-logs"; mkdir -p "$LOGS"
[[ -f "$OVERLAY/.stage14f-overlay.json" ]] || { echo 'Prepare overlay primeiro'; exit 10; }
[[ "$(git -C "$REPO" branch --show-current)" == 'playable/switch-experimental' ]] || { echo 'Branch incorreta'; exit 11; }
grep -q 'option(SH_SWITCH ' "$REPO/pc_port/CMakeLists.txt" || { echo 'Perfil 14C ausente'; exit 12; }
export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
export DEVKITA64="${DEVKITA64:-$DEVKITPRO/devkitA64}"
export PATH="$DEVKITA64/bin:$DEVKITPRO/tools/bin:$PATH"
source "$DEVKITPRO/switchvars.sh"
PKG="$(command -v aarch64-none-elf-pkg-config)"
set +e
aarch64-none-elf-cmake -S "$REPO/pc_port" -B "$OUT" -G 'Unix Makefiles' \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo -DPSYCROSS_DIR="$OVERLAY" \
  -DSH_SWITCH=ON -DSH_STATIC_MAPS=ON -DSH_BUILD_MAP_DLLS=OFF \
  -DSH_FMV_FFMPEG=OFF -DSH_ENABLE_RETROACHIEVEMENTS=ON \
  -DBUILD_TESTING=OFF -DPKG_CONFIG_EXECUTABLE="$PKG" \
  -DCMAKE_PREFIX_PATH="${PORTLIBS:-$DEVKITPRO/portlibs/switch}" \
  2>&1 | tee "$LOGS/game-configure.log"
RC=${PIPESTATUS[0]}; set -e
printf 'phase=game-configure exit=%d\n' "$RC" | tee "$LOGS/game-configure.status"
exit "$RC"
