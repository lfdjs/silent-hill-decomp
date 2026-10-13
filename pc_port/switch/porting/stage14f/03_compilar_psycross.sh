#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${SH_PILOT_ROOT:-$HOME/Documentos/projetos_decompilacao/_silent_hill_playable_pilot}"
OUT="$ROOT/switch-14f-psycross-build"
LOGS="$ROOT/switch-14f-logs"
mkdir -p "$LOGS"
[[ -f "$OUT/Makefile" ]] || { echo 'Configure PsyCross primeiro'; exit 10; }
set +e
cmake --build "$OUT" --parallel 2 --target psycross_static 2>&1 | tee "$LOGS/psycross-build.log"
RC=${PIPESTATUS[0]}; set -e
printf 'phase=psycross-build exit=%d\n' "$RC" | tee "$LOGS/psycross-build.status"
exit "$RC"
