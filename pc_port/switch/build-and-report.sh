#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the Switch homebrew diagnostic and capture all output in one archive.
set -Eeuo pipefail

SWITCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SWITCH_DIR/../.." && pwd)"
PROJECT_REPORTS="${SH_SWITCH_REPORT_DIR:-$HOME/Documentos/projetos_decompilacao/_silent_hill_playable_pilot}"
RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
REPORT="$PROJECT_REPORTS/report-switch-auto-$RUN_ID"
ARCHIVE="$REPORT.tar.gz"
PHASE=initial
mkdir -p "$REPORT"

finish() {
    local rc=$?
    trap - EXIT
    set +e
    {
        printf 'Etapa: 14A.2 Ryubing log probe\nResultado: %s\nFase: %s\n' "$rc" "$PHASE"
        printf 'Projeto: %s\n' "$REPO_ROOT"
        printf 'Commit: '; git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null
        printf 'NRO: %s\n' "$SWITCH_DIR/SilentHillSwitchProbe.nro"
        printf 'Gameplay do Silent Hill: NAO incluido\n'
    } > "$REPORT/summary.txt"
    git -C "$REPO_ROOT" status -sb > "$REPORT/git-status.txt" 2>&1
    tar -czf "$ARCHIVE" -C "$PROJECT_REPORTS" "$(basename "$REPORT")" 2>/dev/null
    echo
    echo "RESULTADO=$rc FASE=$PHASE"
    echo "RELATORIO=$ARCHIVE"
    if [ -s "$SWITCH_DIR/SilentHillSwitchProbe.nro" ]; then
        echo "EXECUTAVEL=$SWITCH_DIR/SilentHillSwitchProbe.nro"
    fi
    exit "$rc"
}
trap finish EXIT

{
    PHASE=checkpoints
    echo '=== ETAPA 14A.2 — PREPARACAO ==='
    git -C "$REPO_ROOT" rev-parse HEAD
    if [ ! -f "$SWITCH_DIR/Makefile" ] || [ ! -f "$SWITCH_DIR/source/main.c" ]; then
        echo 'ERRO: o pacote do probe nao foi aplicado corretamente'
        exit 10
    fi

    PHASE=devkitpro
    export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
    export DEVKITA64="${DEVKITA64:-$DEVKITPRO/devkitA64}"
    export PATH="$DEVKITA64/bin:$DEVKITPRO/tools/bin:$PATH"
    echo "DEVKITPRO=$DEVKITPRO"
    echo "DEVKITA64=$DEVKITA64"
    echo "dkp-pacman=$(command -v dkp-pacman || echo AUSENTE)"
    for f in "$DEVKITPRO/switchvars.sh" "$DEVKITPRO/libnx/switch_rules" "$DEVKITA64/bin/aarch64-none-elf-gcc"; do
        if [ ! -f "$f" ]; then
            echo "FALTA FERRAMENTA: $f"
            echo 'Instale o devkitPro seguindo devkitpro.org e depois os pacotes:'
            echo 'sudo dkp-pacman -S --needed switch-dev switch-sdl2 switch-mesa switch-openal-soft'
            exit 11
        fi
    done
    # shellcheck source=/dev/null
    source "$DEVKITPRO/switchvars.sh"
    echo "PREFIX=${PREFIX:-NAO_DEFINIDO}"
    echo "PORTLIBS=${PORTLIBS:-NAO_DEFINIDO}"
    aarch64-none-elf-gcc --version | head -n 1
    if ! command -v aarch64-none-elf-pkg-config >/dev/null 2>&1; then
        echo 'FALTA: aarch64-none-elf-pkg-config (pacote switch-pkg-config)'
        exit 12
    fi
    if ! aarch64-none-elf-pkg-config --modversion sdl2; then
        echo 'FALTA SDL2 do Switch (switch-sdl2)'
        exit 13
    fi

    PHASE=build
    echo '=== COMPILANDO .NRO ==='
    make -C "$SWITCH_DIR" -j2

    PHASE=artifacts
    ELF="$SWITCH_DIR/SilentHillSwitchProbe.elf"
    NRO="$SWITCH_DIR/SilentHillSwitchProbe.nro"
    test -s "$ELF"
    test -s "$NRO"
    file "$ELF" "$NRO"
    sha256sum "$ELF" "$NRO"
    ls -lh "$ELF" "$NRO"
    mkdir -p "$HOME/Downloads"
    cp -f "$NRO" "$HOME/Downloads/SilentHillSwitchProbe.nro"
    echo "COPIADO PARA: $HOME/Downloads/SilentHillSwitchProbe.nro"
    echo 'RYUBING: File > Load Application From File > selecione o .nro'
    echo 'APP: 30 segundos de teste; A altera cor, + encerra; SDL/SD log automatico'
    PHASE=success
    echo 'BUILD APROVADO: executavel NRO gerado.'
} 2>&1 | tee "$REPORT/build.log"
