#!/usr/bin/env bash
# Explicit source-only Git checkpoint; no merge, reset, force push, or ROM inclusion.
set -Eeuo pipefail
ROOT="${SH_PILOT_ROOT:-$HOME/Documentos/projetos_decompilacao/_silent_hill_playable_pilot}"
REPO="${SH_REPO:-$ROOT/source-20261012T230037Z}"
BRANCH='playable/switch-experimental'
BASE='bd8d8842f6aeeb38659c21c190857120dd19236c'
DEST='https://github.com/lfdjs/silent-hill-decomp.git'
cd "$REPO"
[[ "$(git symbolic-ref --short HEAD)" == "$BRANCH" ]] || { echo 'ERRO: branch incorreta'; exit 2; }
git merge-base --is-ancestor "$BASE" HEAD || { echo 'ERRO: base inesperada'; exit 3; }
git diff --cached --quiet || { echo 'ERRO: existem outros arquivos previamente staged. Revise git diff --cached --name-only'; exit 4; }
# The Switch-only checkpoint deliberately stages EXACT FILES, never the entire
# engine_arm64 dir: it contains built ELF/NRO/objects and possibly user's assets.
FILES=(
  pc_port/CMakeLists.txt
  pc_port/src/main_pc.c
  pc_port/include/sh_switch_profile.h
  pc_port/src/sh_switch_profile.c
  src/bodyprog/sys/game_main.c
  src/screens/options/options.c
  pc_port/switch/Makefile
  pc_port/switch/README.md
  pc_port/switch/source/main.c
  pc_port/switch/build-and-report.sh
  pc_port/switch/collect-ryubing-logs.sh
  pc_port/switch/engine_arm64/Makefile
  pc_port/switch/engine_arm64/source/main.c
  pc_port/switch/engine_arm64/source/game_core_bridge.c
  pc_port/switch/engine_arm64/source/game_core_bridge.h
  pc_port/switch/engine_arm64/source/sh_tim.c
  pc_port/switch/engine_arm64/source/sh_tim.h
  pc_port/switch/porting/stage14f/README.md
  pc_port/switch/porting/stage14f/NEXT_SESSION.md
  pc_port/switch/porting/stage14f/prepare_overlay.py
  pc_port/switch/porting/stage14f/02_configurar_arm64.sh
  pc_port/switch/porting/stage14f/03_compilar_psycross.sh
  pc_port/switch/porting/stage14f/04_configurar_jogo.sh
  pc_port/switch/porting/stage14f/05_compilar_jogo.sh
  pc_port/switch/porting/stage14f/06_relatorio.sh
  pc_port/switch/porting/stage14f/07_checkpoint_github.sh
  pc_port/switch/porting/stage14f/08_test_host.py
)
existing=()
for f in "${FILES[@]}"; do
    if [[ -f "$f" ]]; then
        existing+=("$f")
    else
        echo "NOTA: arquivo opcional nao presente: $f"
    fi
done
[[ -f pc_port/switch/porting/stage14f/prepare_overlay.py ]] || { echo 'ERRO: 14F nao foi instalada'; exit 5; }
[[ -f pc_port/include/sh_switch_profile.h ]] || { echo 'ERRO: configuracao 14C nao encontrada'; exit 6; }
[[ -f pc_port/switch/engine_arm64/source/main.c ]] || { echo 'ERRO: fonte 14B nao encontrado'; exit 7; }
# First verify remote HEAD. A stale checkout should not attempt to overwrite it.
remote_line="$(git ls-remote --heads "$DEST" "refs/heads/$BRANCH")" || { echo 'ERRO: remoto inacessivel'; exit 8; }
remote_sha="$(awk '{print $1}' <<<"$remote_line")"
local_head="$(git rev-parse HEAD)"
[[ -n "$remote_sha" ]] || { echo 'ERRO: branch remota ausente'; exit 9; }
[[ "$remote_sha" == "$local_head" ]] || { echo "ERRO: branch remota avancou: $remote_sha (local: $local_head); fetch/rebase manual antes"; exit 10; }
git add -- "${existing[@]}"
git diff --cached --check
# Fail closed if unexpected paths were staged (including assets or binaries).
mapfile -t staged < <(git diff --cached --name-only)
for f in "${staged[@]}"; do
    match=0
    for allow in "${FILES[@]}"; do [[ "$f" == "$allow" ]] && { match=1; break; }; done
    [[ "$match" == 1 ]] || { echo "ERRO: staged inesperado $f"; exit 11; }
    if [[ -f "$f" ]]; then
        bytes="$(stat -c %s -- "$f")"
        (( bytes < 1024 * 1024 )) || { echo "ERRO: arquivo excessivamente grande $f ($bytes)"; exit 12; }
    fi
done
[[ ${#staged[@]} -gt 0 ]] || { echo 'Nenhuma nova mudanca para commit'; exit 13; }
echo; echo '=== ALTERACOES QUE SERAO PUBLICADAS ==='
git diff --cached --stat
echo; echo '=== NAO PUBLICADOS (verifique depois) ==='
git status --short | grep '^??' || true
echo; echo 'Criando checkpoint LOCAL...'
git commit -m 'wip(switch): checkpoint ARM64 core and isolated PsyCross GLES3 port'
commit_sha="$(git rev-parse HEAD)"
echo "Checkpoint local: $commit_sha"
echo; echo 'Publicando no fork (sem --force)...'
git push "$DEST" "HEAD:refs/heads/$BRANCH"
verify="$(git ls-remote --heads "$DEST" "refs/heads/$BRANCH" | awk '{print $1}')"
[[ "$verify" == "$commit_sha" ]] || { echo 'ERRO: push nao confirmado'; exit 14; }
echo; echo 'CHECKPOINT PUBLICADO E VERIFICADO'
echo "URL: https://github.com/lfdjs/silent-hill-decomp/tree/$BRANCH"
echo "SHA: $commit_sha"
echo 'OBS: compilacao total/gameplay Switch continuam pendentes.'
