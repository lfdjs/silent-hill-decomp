#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Safely gather candidate emulator logs; review before sharing.
set -Eeuo pipefail
RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
BASE="${SH_SWITCH_REPORT_DIR:-$HOME/Documentos/projetos_decompilacao/_silent_hill_playable_pilot}"
OUT="$BASE/report-ryubing-runtime-$RUN_ID"
mkdir -p "$OUT"
printf 'Ryubing runtime logs, collected at %s UTC\n' "$RUN_ID" > "$OUT/readme.txt"
found=0
for dir in \
    "$HOME/.config/Ryubing/Logs" \
    "$HOME/.config/Ryujinx/Logs" \
    "$HOME/.local/share/Ryubing/Logs" \
    "$HOME/.local/share/Ryujinx/Logs" \
    "$HOME/.config/ryubing/Logs" \
    "$HOME/.config/ryujinx/Logs"; do
    if [ -d "$dir" ]; then
        echo "LOG DIRECTORY: $dir" >> "$OUT/readme.txt"
        path="$(find "$dir" -maxdepth 1 -type f \( -name '*.log' -o -name '*.txt' \) -printf '%T@ %p\n' | sort -nr | sed -n '1p' | cut -d' ' -f2-)"
        if [ -n "$path" ]; then
            cp "$path" "$OUT/ryubing-$(printf '%02d' "$found").log"
            found=$((found + 1))
        fi
    fi
done
printf 'Files copied: %s\n' "$found" >> "$OUT/readme.txt"
if [ "$found" -eq 0 ]; then echo 'Nenhum log automatico localizado nos diretorios comuns.'; fi
tar -czf "$OUT.tar.gz" -C "$BASE" "$(basename "$OUT")"
echo "RELATORIO=$OUT.tar.gz"
echo 'ATENCAO: revise logs antes de compartilhar; podem conter caminhos locais.'
