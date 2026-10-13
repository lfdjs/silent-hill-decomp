#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${SH_PILOT_ROOT:-$HOME/Documentos/projetos_decompilacao/_silent_hill_playable_pilot}"
OUT="$ROOT/switch-14f-game-build"
LOGS="$ROOT/switch-14f-logs"; mkdir -p "$LOGS"
[[ -f "$OUT/Makefile" ]] || { echo 'Configure jogo primeiro'; exit 10; }
set +e
cmake --build "$OUT" --parallel 2 --target SilentHillPC 2>&1 | tee "$LOGS/game-build.log"
RC=${PIPESTATUS[0]}; set -e
printf 'phase=game-build exit=%d\n' "$RC" | tee "$LOGS/game-build.status"
if [[ "$RC" == 0 ]]; then
  echo 'AVISO: link ELF ainda nao significa um .nro jogavel; backend/contexto Switch pendentes.'
fi
exit "$RC"
