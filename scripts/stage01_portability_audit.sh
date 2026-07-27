#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

SCRIPT_NAME="$(basename "$0")"
OUTPUT_DIR="stage01-portability-audit"
CLEAN_OUTPUT=0

usage() {
    cat <<EOF
Uso:
  $SCRIPT_NAME [--output DIRETORIO] [--clean]

Opções:
  --output DIRETORIO  Diretório dos relatórios.
                      Padrão: stage01-portability-audit
  --clean             Remove o diretório de saída antes da auditoria.
  -h, --help          Exibe esta ajuda.

Execute o script a partir de qualquer subdiretório de um clone Git.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ $# -ge 2 ]] || {
                echo "Erro: --output exige um diretório." >&2
                exit 2
            }
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --clean)
            CLEAN_OUTPUT=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Erro: argumento desconhecido: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Erro: comando obrigatório não encontrado: $1" >&2
        exit 1
    fi
}

for command_name in git find grep sed awk sort uniq wc date uname sha256sum; do
    require_command "$command_name"
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Erro: execute dentro de um clone Git do projeto." >&2
    exit 1
}

cd "$REPO_ROOT"

case "$OUTPUT_DIR" in
    /*) ;;
    *) OUTPUT_DIR="$REPO_ROOT/$OUTPUT_DIR" ;;
esac

if [[ "$CLEAN_OUTPUT" -eq 1 ]]; then
    rm -rf -- "$OUTPUT_DIR"
fi

mkdir -p -- "$OUTPUT_DIR"

# O diretório de saída nunca deve ser analisado pela própria auditoria.
OUTPUT_RELATIVE="${OUTPUT_DIR#"$REPO_ROOT"/}"

COMMON_GREP_EXCLUDES=(
    --exclude-dir=.git
    --exclude-dir=build
    --exclude-dir=expected
    --exclude-dir=permuter
    --exclude-dir=rom
    --exclude-dir=assets
    --exclude-dir="$OUTPUT_RELATIVE"
    --exclude='*.o'
    --exclude='*.a'
    --exclude='*.so'
    --exclude='*.dll'
    --exclude='*.exe'
    --exclude='*.elf'
    --exclude='*.bin'
    --exclude='*.iso'
    --exclude='*.img'
    --exclude='*.map'
)

grep_repo() {
    local pattern="$1"
    shift || true

    grep -RInE \
        "${COMMON_GREP_EXCLUDES[@]}" \
        "$@" \
        -- "$pattern" . 2>/dev/null || true
}

write_header() {
    local title="$1"
    {
        printf '%s\n' "$title"
        printf '%*s\n' "${#title}" '' | tr ' ' '='
        printf '\n'
    }
}

git_value_or_unknown() {
    local value
    value="$("$@" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "(indisponível)"
    fi
}

count_report_lines() {
    local file="$1"
    if [[ -f "$file" ]]; then
        wc -l < "$file" | tr -d ' '
    else
        printf '0'
    fi
}

echo "Gerando auditoria em: $OUTPUT_DIR"

# ---------------------------------------------------------------------------
# 01 - Metadados do repositório e ambiente
# ---------------------------------------------------------------------------
{
    write_header "SILENT HILL DECOMP — ETAPA 01 — REPOSITÓRIO E AMBIENTE"

    printf 'Data UTC: '
    date -u '+%Y-%m-%dT%H:%M:%SZ'

    printf 'Raiz: %s\n' "$REPO_ROOT"
    printf 'Commit: '
    git_value_or_unknown git rev-parse HEAD

    printf 'Branch: '
    git_value_or_unknown git branch --show-current

    printf 'Describe: '
    git_value_or_unknown git describe --always --dirty --tags

    printf '\nSistema:\n'
    uname -a

    printf '\nRemotes:\n'
    git remote -v 2>/dev/null || true

    printf '\nStatus:\n'
    git status --short --branch 2>/dev/null || true

    printf '\nSubmódulos:\n'
    if [[ -f .gitmodules ]]; then
        cat .gitmodules
        printf '\nEstado:\n'
        git submodule status --recursive 2>/dev/null || true
    else
        printf '(nenhum .gitmodules encontrado)\n'
    fi

    printf '\nFerramentas detectadas:\n'
    for tool in \
        make cmake ninja python3 \
        mips-linux-gnu-as mips-linux-gnu-ld \
        mips-linux-gnu-objcopy mips-linux-gnu-objdump \
        clang gcc cc ctags tree; do
        if command -v "$tool" >/dev/null 2>&1; then
            printf '%-26s %s\n' "$tool" "$(command -v "$tool")"
        else
            printf '%-26s %s\n' "$tool" "(não encontrado)"
        fi
    done
} > "$OUTPUT_DIR/01-repository-and-environment.txt"

# ---------------------------------------------------------------------------
# 02 - Árvore rastreada pelo Git
# ---------------------------------------------------------------------------
{
    write_header "ÁRVORE DE ARQUIVOS RASTREADOS PELO GIT"
    git ls-files | sort
} > "$OUTPUT_DIR/02-repository-tree.txt"

# ---------------------------------------------------------------------------
# 03 - Contagens por extensão e área
# ---------------------------------------------------------------------------
{
    printf 'extensao\tarquivos\tlinhas\n'

    git ls-files -z |
        while IFS= read -r -d '' file; do
            [[ -f "$file" ]] || continue

            case "$file" in
                *.c)    ext="c" ;;
                *.h)    ext="h" ;;
                *.s|*.S) ext="asm" ;;
                *.py)   ext="py" ;;
                *.sh)   ext="sh" ;;
                *.yaml|*.yml) ext="yaml" ;;
                *.ld)   ext="ld" ;;
                *.inc)  ext="inc" ;;
                *.md)   ext="md" ;;
                Makefile|*.mk) ext="make" ;;
                *)      continue ;;
            esac

            lines="$(wc -l < "$file" 2>/dev/null || printf '0')"
            printf '%s\t1\t%s\n' "$ext" "$lines"
        done |
        awk -F '\t' '
            {
                files[$1] += $2;
                lines[$1] += $3;
            }
            END {
                for (ext in files) {
                    printf "%s\t%d\t%d\n", ext, files[ext], lines[ext];
                }
            }
        ' |
        sort
} > "$OUTPUT_DIR/03-source-counts.tsv"

{
    printf 'area\tarquivos\n'
    git ls-files |
        awk -F/ '
            {
                if (NF == 1) area = "(raiz)";
                else area = $1;
                count[area]++;
            }
            END {
                for (area in count) {
                    printf "%s\t%d\n", area, count[area];
                }
            }
        ' |
        sort
} > "$OUTPUT_DIR/03b-files-by-area.tsv"

# ---------------------------------------------------------------------------
# 04 - Sistema de build
# ---------------------------------------------------------------------------
{
    write_header "ARQUIVOS E SÍMBOLOS DO SISTEMA DE BUILD"

    printf '[Arquivos de build]\n'
    git ls-files |
        grep -E '(^|/)(Makefile|CMakeLists\.txt|meson\.build|build\.ninja)$|\.mk$|\.cmake$|\.ld$|\.ya?ml$' |
        sort || true

    printf '\n[Compiladores, flags e ferramentas]\n'
    grep_repo \
        '(^|[[:space:]])(CC|CXX|AS|LD|AR|OBJCOPY|OBJDUMP|CROSS|CPP)[[:space:]]*[:?+]?=|mips-linux-gnu|gcc-2\.[0-9]|-mips1|-mcpu=3000|-march=r3000|MASPSX|SPLAT|psxiso|objdiff' \
        --include='Makefile' --include='*.mk' --include='*.sh' --include='*.py' --include='*.yml' --include='*.yaml'

    printf '\n[Defines relevantes]\n'
    grep_repo \
        'NON_MATCHING|SKIP_ASM|USE_INCLUDE_ASM|VERSION_IS|VERSION_REGION_IS|GAME_VERSION|BUILD_(EXE|ENGINE|SCREENS|MAPS|ITEMS)' \
        --include='Makefile' --include='*.mk' --include='*.c' --include='*.h'
} > "$OUTPUT_DIR/04-build-system.txt"

# ---------------------------------------------------------------------------
# 05 - Includes Psy-Q e SDK do PS1
# ---------------------------------------------------------------------------
{
    write_header "INCLUDES PSY-Q / SDK DO PLAYSTATION"
    grep_repo \
        '^[[:space:]]*#[[:space:]]*include[[:space:]]*[<"][^>"]*(psyq|libapi|libetc|libgpu|libgte|libcd|libsnd|libspu|libpad|libmcrd|libpress|libsn)[^>"]*[>"]' \
        --include='*.c' --include='*.h'
} > "$OUTPUT_DIR/05-psyq-includes.txt"

# ---------------------------------------------------------------------------
# 06 - Chamadas conhecidas de plataforma PS1
# ---------------------------------------------------------------------------
{
    write_header "CHAMADAS DIRETAS DE PLATAFORMA PS1"

    grep_repo \
        '\b(ResetCallback|StopCallback|VSync|DrawSync|ResetGraph|SetGraphDebug|SetDispMask|PutDispEnv|PutDrawEnv|SetDefDispEnv|SetDefDrawEnv|DrawPrim|DrawOTag|DrawOTagEnv|ClearImage2?|LoadImage|StoreImage|MoveImage|GetClut|GetTPage|CdInit|CdRead|CdReadSync|CdControl|CdControlB|CdSync|CdPosToInt|CdIntToPos|SpuInit|SpuSetCommonAttr|SpuSetVoiceAttr|SpuSetTransferMode|SpuSetTransferStartAddr|SpuWrite|SpuIsTransferCompleted|PadInit|PadInitDirect|PadStartCom|PadStopCom|MemCard|OpenEvent|CloseEvent|EnableEvent|DisableEvent|TestEvent|DeliverEvent|EnterCriticalSection|ExitCriticalSection|FlushCache|LoadExec|SetRCnt|StartRCnt|StopRCnt|GetRCnt|GPU_[A-Za-z0-9_]+|Gs[A-Za-z0-9_]+)\b' \
        --include='*.c' --include='*.h'
} > "$OUTPUT_DIR/06-ps1-platform-calls.txt"

# ---------------------------------------------------------------------------
# 07 - Endereços fixos e acesso a memória mapeada
# ---------------------------------------------------------------------------
{
    write_header "ENDEREÇOS FIXOS E ACESSOS A MEMÓRIA MAPEADA"

    printf '[Faixas típicas de KSEG0/KSEG1, RAM e registradores PS1]\n'
    grep_repo \
        '0x(800[0-9A-Fa-f]{5}|801[0-9A-Fa-f]{5}|A00[0-9A-Fa-f]{5}|A01[0-9A-Fa-f]{5}|1F80[0-9A-Fa-f]{3}|1F801[0-9A-Fa-f]{3})' \
        --include='*.c' --include='*.h' --include='*.s' --include='*.S' --include='*.ld' --include='*.yaml' --include='*.yml'

    printf '\n[Casts de inteiros para ponteiros]\n'
    grep_repo \
        '\([[:space:]]*(void|u8|s8|u16|s16|u32|s32|char|unsigned|int|long|short)[[:space:]]*\*+[[:space:]]*\)[[:space:]]*0x[0-9A-Fa-f]+' \
        --include='*.c' --include='*.h'

    printf '\n[Macros e símbolos de memória do PS1]\n'
    grep_repo \
        '\b(PSX_[A-Z0-9_]+|KSEG0|KSEG1|SCRATCH|SCRATCHPAD|_ramsize|_stacksize)\b' \
        --include='*.c' --include='*.h' --include='*.s' --include='*.S'
} > "$OUTPUT_DIR/07-fixed-addresses.txt"

# ---------------------------------------------------------------------------
# 08 - Overlays, carregamento e linker layout
# ---------------------------------------------------------------------------
{
    write_header "OVERLAYS, CARREGAMENTO DINÂMICO E LAYOUT"

    printf '[Referências a overlays]\n'
    grep_repo \
        '\b(overlay|Overlay|OVERLAY|OVL|Ovl|BODYPROG|B_KONAMI|SAVELOAD|STF_ROLL|OPTION\.BIN|STREAM\.BIN|MAP[0-9X]_S[0-9X]{2}|g_Ovl[A-Za-z0-9_]*)\b' \
        --include='*.c' --include='*.h' --include='*.ld' --include='*.yaml' --include='*.yml' --include='Makefile' --include='*.mk'

    printf '\n[Carregamento, descriptografia e cópia]\n'
    grep_repo \
        '\b(Fs_DecryptOverlay|Fs_QueueStartRead|Fs_QueueStartReadTim|memcpy|bcopy|LoadOverlay|Overlay_Load|LoadMap|Map_Load|SysState_LoadOverlay|ProcessFlag_OverlayTransition)\b' \
        --include='*.c' --include='*.h'

    printf '\n[Endereços e seções de linker]\n'
    grep_repo \
        '(^|[[:space:]])(SECTIONS|MEMORY|ORIGIN|ENTRY|OVERLAY)[[:space:]]|\.(text|data|rodata|bss|sbss|sdata)[[:space:]]|0x80[0-9A-Fa-f]{6}' \
        --include='*.ld'
} > "$OUTPUT_DIR/08-overlays-and-layout.txt"

# ---------------------------------------------------------------------------
# 09 - Estado global e símbolos externos
# ---------------------------------------------------------------------------
{
    write_header "ESTADO GLOBAL, EXTERNS E SINGLETONS"

    printf '[Declarações extern em headers]\n'
    grep_repo \
        '^[[:space:]]*extern[[:space:]].*;' \
        --include='*.h'

    printf '\n[Variáveis globais com prefixo g_]\n'
    grep_repo \
        '^[[:space:]]*(static[[:space:]]+)?(const[[:space:]]+)?[A-Za-z_][A-Za-z0-9_[:space:]\*]*[[:space:]]+g_[A-Za-z0-9_]+([[:space:]]*\[[^]]*\])?[[:space:]]*(=|;)' \
        --include='*.c' --include='*.h'

    printf '\n[Acessos ao estado global principal]\n'
    grep_repo \
        '\bg_(SysWork|GameWork|GameState|GameStateUpdateFuncs|Main|Map|Save|Player|Screen|Audio|Sound|Fs|Joy|Pad)[A-Za-z0-9_]*\b' \
        --include='*.c' --include='*.h'
} > "$OUTPUT_DIR/09-global-state.txt"

# ---------------------------------------------------------------------------
# 10 - Grafo textual de includes internos
# ---------------------------------------------------------------------------
{
    printf 'arquivo\tinclude\n'

    git ls-files '*.c' '*.h' |
        while IFS= read -r file; do
            [[ -f "$file" ]] || continue

            sed -nE \
                's/^[[:space:]]*#[[:space:]]*include[[:space:]]*"([^"]+)".*/\1/p' \
                "$file" |
                while IFS= read -r include; do
                    printf '%s\t%s\n' "$file" "$include"
                done
        done
} > "$OUTPUT_DIR/10-internal-includes.tsv"

# ---------------------------------------------------------------------------
# 11 - Assembly e funções ainda não migradas
# ---------------------------------------------------------------------------
{
    write_header "ASSEMBLY, INCLUDE_ASM E TRECHOS NÃO MATCHING"

    grep_repo \
        '\b(INCLUDE_ASM|INCLUDE_RODATA|GLOBAL_ASM|asm volatile|__asm__|NON_MATCHING|SKIP_ASM|#if[[:space:]]+0)\b' \
        --include='*.c' --include='*.h' --include='*.s' --include='*.S'

    printf '\n[Arquivos assembly rastreados]\n'
    git ls-files '*.s' '*.S' | sort
} > "$OUTPUT_DIR/11-assembly-and-nonmatching.txt"

# ---------------------------------------------------------------------------
# 12 - Riscos de portabilidade C
# ---------------------------------------------------------------------------
{
    write_header "RISCOS DE PORTABILIDADE C"

    printf '[Suposições sobre tamanho/alinhamento]\n'
    grep_repo \
        '\b(STATIC_ASSERT_SIZEOF|sizeof[[:space:]]*\(|PACKED|ALIGNED|__attribute__|#pragma[[:space:]]+pack|SECTION[[:space:]]*\()\b' \
        --include='*.c' --include='*.h'

    printf '\n[Conversões entre ponteiros e inteiros]\n'
    grep_repo \
        '\((u32|s32|unsigned[[:space:]]+int|int|uintptr_t|intptr_t)\)[[:space:]]*[A-Za-z_][A-Za-z0-9_]*|\([A-Za-z_][A-Za-z0-9_]*[[:space:]]*\*+\)[[:space:]]*[A-Za-z_][A-Za-z0-9_]*' \
        --include='*.c' --include='*.h'

    printf '\n[Dependência de endianness ou representação binária]\n'
    grep_repo \
        '\b(little[ _-]?endian|big[ _-]?endian|ENDIAN|SWAP16|SWAP32|bswap|union[[:space:]]*\{|bitfield|BITFIELD)\b' \
        --include='*.c' --include='*.h' --include='Makefile' --include='*.mk'

    printf '\n[Funções inseguras ou não portáveis]\n'
    grep_repo \
        '\b(sprintf|vsprintf|strcpy|strcat|gets|alloca|setjmp|longjmp|bcopy|bzero)\b' \
        --include='*.c' --include='*.h'
} > "$OUTPUT_DIR/12-portability-hazards.txt"

# ---------------------------------------------------------------------------
# 13 - Entradas, loops e máquinas de estado
# ---------------------------------------------------------------------------
{
    write_header "PONTOS DE ENTRADA, LOOPS E MÁQUINAS DE ESTADO"

    grep_repo \
        '^[[:space:]]*(int|s32|void)[[:space:]]+(main|MainLoop|GameState_[A-Za-z0-9_]+|SysState_[A-Za-z0-9_]+|Bodyprog[A-Za-z0-9_]*|Map[A-Za-z0-9_]*|Screen[A-Za-z0-9_]*)[[:space:]]*\(' \
        --include='*.c' --include='*.h'

    printf '\n[Enums e tabelas de estado]\n'
    grep_repo \
        '\b(GameState_[A-Za-z0-9_]+|SysState_[A-Za-z0-9_]+|ProcessFlag_[A-Za-z0-9_]+|g_GameStateUpdateFuncs)\b' \
        --include='*.c' --include='*.h'
} > "$OUTPUT_DIR/13-entry-points-and-state-machines.txt"

# ---------------------------------------------------------------------------
# 14 - Timing, renderização, áudio, entrada e arquivos
# ---------------------------------------------------------------------------
{
    write_header "FRONTEIRAS CANDIDATAS DA CAMADA DE PLATAFORMA"

    printf '[Timing e sincronização]\n'
    grep_repo \
        '\b(VSync|DrawSync|TICKS_PER_SECOND|TIMESTEP_[0-9]+_FPS|delta|timestep|frame|frames|timer|counter|RCnt)\b' \
        --include='*.c' --include='*.h'

    printf '\n[Renderização e GPU]\n'
    grep_repo \
        '\b(DrawPrim|DrawOTag|PutDispEnv|PutDrawEnv|DISPENV|DRAWENV|POLY_|SPRT|TILE|DR_TPAGE|OT_TAG|ordering[ _]?table|VRAM|tPage|clut)\b' \
        --include='*.c' --include='*.h'

    printf '\n[Áudio e SPU]\n'
    grep_repo \
        '\b(Spu[A-Za-z0-9_]*|Ss[A-Za-z0-9_]*|Vab[A-Za-z0-9_]*|Bgm[A-Za-z0-9_]*|Sfx[A-Za-z0-9_]*|Sound[A-Za-z0-9_]*)\b' \
        --include='*.c' --include='*.h'

    printf '\n[Entrada e controles]\n'
    grep_repo \
        '\b(Pad[A-Za-z0-9_]*|Joy[A-Za-z0-9_]*|Kpad[A-Za-z0-9_]*|libkpad|controller|button|analog)\b' \
        --include='*.c' --include='*.h'

    printf '\n[Arquivos, CD e memory card]\n'
    grep_repo \
        '\b(Fs_[A-Za-z0-9_]*|Cd[A-Za-z0-9_]*|MemCard[A-Za-z0-9_]*|FILE_[A-Za-z0-9_]+|savegame|Savegame)\b' \
        --include='*.c' --include='*.h'
} > "$OUTPUT_DIR/14-platform-boundaries.txt"

# ---------------------------------------------------------------------------
# 15 - Candidatos a núcleo inicialmente headless
# ---------------------------------------------------------------------------
{
    write_header "CANDIDATOS A NÚCLEO PORTÁTIL / HEADLESS"

    printf '[Matemática, colisão, estado, eventos e gameplay]\n'
    git ls-files |
        grep -Ei '(^|/)(math|collision|chara|player|event|inventory|items|savegame|map|camera|game|bodyprog)(/|\.|_)' |
        grep -E '\.(c|h)$' |
        sort || true

    printf '\n[Arquivos sem include Psy-Q direto]\n'
    git ls-files '*.c' |
        while IFS= read -r file; do
            [[ -f "$file" ]] || continue
            if ! grep -Eq \
                '^[[:space:]]*#[[:space:]]*include[[:space:]]*[<"][^>"]*(psyq|libapi|libetc|libgpu|libgte|libcd|libsnd|libspu|libpad|libmcrd)' \
                "$file"; then
                printf '%s\n' "$file"
            fi
        done |
        sort
} > "$OUTPUT_DIR/15-headless-core-candidates.txt"

# ---------------------------------------------------------------------------
# 16 - TODOs relacionados a portabilidade/decompilação
# ---------------------------------------------------------------------------
{
    write_header "TODO, FIXME, HACK E BUG"

    grep_repo \
        '\b(TODO|FIXME|HACK|BUG|XXX|portability|portable|shiftable|hardcoded|hard-coded|address)\b' \
        --include='*.c' --include='*.h' --include='*.py' --include='*.sh' --include='*.md' --include='Makefile' --include='*.mk'
} > "$OUTPUT_DIR/16-todos-and-hacks.txt"

# ---------------------------------------------------------------------------
# Resumo e manifesto
# ---------------------------------------------------------------------------
{
    write_header "RESUMO DA AUDITORIA"

    printf 'Repositório: %s\n' "$REPO_ROOT"
    printf 'Commit: %s\n' "$(git rev-parse HEAD)"
    printf 'Saída: %s\n\n' "$OUTPUT_DIR"

    printf '%-42s %10s\n' "Relatório" "Linhas"
    printf '%-42s %10s\n' "----------" "------"

    for report in "$OUTPUT_DIR"/*.txt "$OUTPUT_DIR"/*.tsv; do
        [[ -f "$report" ]] || continue
        printf '%-42s %10s\n' \
            "$(basename "$report")" \
            "$(count_report_lines "$report")"
    done

    printf '\nContagens rápidas:\n'
    printf 'Includes Psy-Q: %s\n' \
        "$(count_report_lines "$OUTPUT_DIR/05-psyq-includes.txt")"
    printf 'Chamadas PS1: %s\n' \
        "$(count_report_lines "$OUTPUT_DIR/06-ps1-platform-calls.txt")"
    printf 'Endereços fixos: %s\n' \
        "$(count_report_lines "$OUTPUT_DIR/07-fixed-addresses.txt")"
    printf 'Referências de overlay/layout: %s\n' \
        "$(count_report_lines "$OUTPUT_DIR/08-overlays-and-layout.txt")"
    printf 'Estado global: %s\n' \
        "$(count_report_lines "$OUTPUT_DIR/09-global-state.txt")"
    printf 'Hooks de assembly/non-matching: %s\n' \
        "$(count_report_lines "$OUTPUT_DIR/11-assembly-and-nonmatching.txt")"
    printf 'Riscos de portabilidade: %s\n' \
        "$(count_report_lines "$OUTPUT_DIR/12-portability-hazards.txt")"
} > "$OUTPUT_DIR/00-summary.txt"

(
    cd "$OUTPUT_DIR"
    find . -maxdepth 1 -type f \
        ! -name 'SHA256SUMS.txt' \
        -printf '%P\0' |
        sort -z |
        xargs -0 sha256sum
) > "$OUTPUT_DIR/SHA256SUMS.txt"

echo
echo "Auditoria concluída."
echo "Resumo: $OUTPUT_DIR/00-summary.txt"
echo "Manifesto: $OUTPUT_DIR/SHA256SUMS.txt"
echo
echo "Para compartilhar somente os relatórios:"
echo "  tar -czf stage01-portability-audit.tar.gz -C \"$(dirname "$OUTPUT_DIR")\" \"$(basename "$OUTPUT_DIR")\""
