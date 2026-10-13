#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${SH_PILOT_ROOT:-$HOME/Documentos/projetos_decompilacao/_silent_hill_playable_pilot}"
REPO="${SH_REPO:-$ROOT/source-20261012T230037Z}"
LOGS="$ROOT/switch-14f-logs"
NAME="report-switch-engine-14f-$(date -u +%Y%m%dT%H%M%SZ)"
DEST="$ROOT/$NAME"
mkdir -p "$DEST"
if [[ -d "$LOGS" ]]; then
  find "$LOGS" -maxdepth 1 -type f -exec cp -- {} "$DEST"/ \;
fi
{
  echo 'Etapa 14F: cross-build exploratory'
  echo 'NRO gameplay: NOT YET VALIDATED'
  git -C "$REPO" status --short
  git -C "$REPO" rev-parse HEAD
  git -C "$REPO" branch --show-current
  if [[ -f "$ROOT/switch-14f-psycross-overlay/.stage14f-overlay.json" ]]; then
    sha256sum "$ROOT/switch-14f-psycross-overlay/src/platform.h" \
      "$ROOT/switch-14f-psycross-overlay/include/PsyX/PsyX_render.h"
  fi
} > "$DEST/status.txt" 2>&1
for x in "$ROOT/switch-14f-psycross-build/CMakeCache.txt" "$ROOT/switch-14f-game-build/CMakeCache.txt"; do
  if [[ -f "$x" ]]; then cp -- "$x" "$DEST/$(basename "$(dirname "$x")")-CMakeCache.txt"; fi
done
tar -czf "$ROOT/$NAME.tar.gz" -C "$ROOT" "$NAME"
echo "RELATORIO: $ROOT/$NAME.tar.gz"
