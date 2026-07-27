#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

REPO="${REPO:-$HOME/Documentos/projetos_decompilacao/silent-hill-decomp}"
TARGET_BRANCH="portability/core-api"

BUILD_DIR_REL="build-portable-stage04"
SANITIZER_BUILD_DIR_REL="build-portable-stage04-sanitizers"
REPORT_DIR_REL="stage04-deterministic-timing-report"
PACKAGE_REL="stage04-deterministic-timing-report.tar.gz"

DOC_DIR_REL="docs/portability"
PUBLIC_INCLUDE_DIR_REL="include/silent_hill"
PORTABLE_DIR_REL="portable"
TEST_DIR_REL="tests/portable"

BASELINE_DIR_REL="stage01-build-baseline"
BASELINE_ARCHIVE_REL="stage01-build-baseline.tar.gz"
STAGE03_ARCHIVE_REL="stage03-portable-core-report.tar.gz"

PHASE="inicialização"
FINAL_STATUS="falha"
TEMP_DIR=""
REPORT_ACTIVE=0

log() {
    printf '%s\n' "$*"
}

fail() {
    printf 'Erro: %s\n' "$*" >&2
    exit 1
}

cleanup_temp() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}

is_allowed_path() {
    case "$1" in
        "$DOC_DIR_REL"/*|\
        "$PUBLIC_INCLUDE_DIR_REL"/*|\
        "$PORTABLE_DIR_REL"/*|\
        "$TEST_DIR_REL"/*|\
        scripts/stage01_portability_audit.sh|\
        scripts/stage01_prepare_matching_build.sh|\
        scripts/stage02_create_portable_architecture.sh|\
        scripts/stage03_create_portable_core.sh|\
        scripts/stage04_create_deterministic_timing.sh)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

check_changed_paths() {
    local mode="$1"
    local changed_path
    local invalid=0

    if [[ "$mode" == "staged" ]]; then
        while IFS= read -r changed_path; do
            [[ -n "$changed_path" ]] || continue

            if ! is_allowed_path "$changed_path"; then
                printf 'Alteração preparada fora do escopo: %s\n' \
                    "$changed_path" >&2
                invalid=1
            fi
        done < <(git diff --cached --name-only)
    else
        while IFS= read -r changed_path; do
            [[ -n "$changed_path" ]] || continue

            if ! is_allowed_path "$changed_path"; then
                printf 'Alteração local fora do escopo: %s\n' \
                    "$changed_path" >&2
                invalid=1
            fi
        done < <(git diff --name-only)
    fi

    [[ "$invalid" -eq 0 ]]
}

ensure_required_tools() {
    local missing=0
    local tool

    for tool in cmake ctest cc make nm tar sha256sum; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'Ferramenta ausente: %s\n' "$tool" >&2
            missing=1
        fi
    done

    if [[ "$missing" -eq 0 ]]; then
        return 0
    fi

    log
    log "Instalando ferramentas de build ausentes..."
    sudo apt-get update
    sudo apt-get install -y cmake build-essential binutils

    for tool in cmake ctest cc make nm tar sha256sum; do
        command -v "$tool" >/dev/null 2>&1 || \
            fail "ferramenta obrigatória ainda ausente: $tool"
    done
}

write_local_excludes() {
    local exclude_file
    local entry

    exclude_file="$(git rev-parse --git-path info/exclude)"
    mkdir -p "$(dirname "$exclude_file")"
    touch "$exclude_file"

    for entry in \
        "/stage01-portability-audit/" \
        "/stage01-portability-audit.tar.gz" \
        "/stage01-build-baseline/" \
        "/stage01-build-baseline.tar.gz" \
        "/stage02-architecture-report/" \
        "/stage02-architecture-report.tar.gz" \
        "/stage03-portable-core-report/" \
        "/stage03-portable-core-report.tar.gz" \
        "/$BUILD_DIR_REL/" \
        "/$SANITIZER_BUILD_DIR_REL/" \
        "/$REPORT_DIR_REL/" \
        "/$PACKAGE_REL"; do

        if ! grep -qxF "$entry" "$exclude_file"; then
            printf '%s\n' "$entry" >> "$exclude_file"
        fi
    done
}

validate_text_files() {
    local file
    local failed=0

    for file in "$@"; do
        [[ -s "$file" ]] || {
            printf 'Arquivo ausente ou vazio: %s\n' "$file" >&2
            failed=1
            continue
        }

        if grep -nE '[[:blank:]]+$' "$file" >/dev/null; then
            printf 'Espaços finais em: %s\n' "$file" >&2
            grep -nE '[[:blank:]]+$' "$file" >&2 || true
            failed=1
        fi

        if grep -Il $'\r' "$file" | grep -q .; then
            printf 'Arquivo com CRLF: %s\n' "$file" >&2
            failed=1
        fi
    done

    [[ "$failed" -eq 0 ]]
}

create_relative_source_manifest() {
    (
        cd "$REPO_ROOT"

        find \
            "$DOC_DIR_REL" \
            "$PUBLIC_INCLUDE_DIR_REL" \
            "$PORTABLE_DIR_REL" \
            "$TEST_DIR_REL" \
            -type f \
            -print0

        printf '%s\0' scripts/stage04_create_deterministic_timing.sh
    ) |
        sort -z |
        while IFS= read -r -d '' path; do
            printf '%s\n' "$path"
        done > "$REPORT_DIR/source-manifest.txt"

    (
        cd "$REPO_ROOT"

        while IFS= read -r path; do
            sha256sum "$path"
        done < "$REPORT_DIR/source-manifest.txt"
    ) > "$REPORT_DIR/SOURCE_SHA256SUMS.txt"
}

finalize() {
    local result=$?

    trap - EXIT
    set +e

    if [[ "$REPORT_ACTIVE" -eq 1 ]]; then
        {
            echo "SILENT HILL DECOMP — ETAPA 04"
            echo "=============================="
            echo
            echo "Data UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
            echo "Repositório: $REPO_ROOT"
            echo "Branch: $(git branch --show-current 2>/dev/null)"
            echo "Commit: $(git rev-parse HEAD 2>/dev/null)"
            echo "Fase final: $PHASE"
            echo "Estado: $FINAL_STATUS"
            echo "Código de saída: $result"
            echo
            echo "Build nativo: $BUILD_DIR_REL"
            echo "Build sanitizado: $SANITIZER_BUILD_DIR_REL"
            echo
            echo "Git status:"
            git status --short --branch 2>/dev/null || true
        } > "$REPORT_DIR/summary.txt"

        {
            echo "Este pacote contém:"
            echo
            echo "- ABI C portátil atualizada para 0.2;"
            echo "- relógio determinístico de 60 Hz;"
            echo "- avanço por tempo decorrido;"
            echo "- clamp de frames longos;"
            echo "- pausa e avanço de um tick;"
            echo "- testes normais e sanitizados;"
            echo "- documentação e logs da etapa 04;"
            echo "- script persistente da etapa."
            echo
            echo "Não contém ROM, BIOS, executáveis do jogo ou assets extraídos."
            echo "Os diretórios temporários do CMake não foram incluídos."
        } > "$REPORT_DIR/CONTENTS.txt"

        {
            echo "Git status completo:"
            git status --short --branch 2>/dev/null || true
            echo
            echo "Arquivos no escopo:"
            git status \
                --short \
                --untracked-files=all \
                -- \
                "$DOC_DIR_REL" \
                "$PUBLIC_INCLUDE_DIR_REL" \
                "$PORTABLE_DIR_REL" \
                "$TEST_DIR_REL" \
                scripts/stage04_create_deterministic_timing.sh \
                2>/dev/null || true
        } > "$REPORT_DIR/git-state.txt"

        create_relative_source_manifest 2>/dev/null || true

        rm -f -- "$PACKAGE"

        tar_paths=()

        for path in \
            "$DOC_DIR_REL" \
            "$PUBLIC_INCLUDE_DIR_REL" \
            "$PORTABLE_DIR_REL" \
            "$TEST_DIR_REL" \
            scripts/stage04_create_deterministic_timing.sh \
            "$REPORT_DIR_REL"; do

            [[ -e "$REPO_ROOT/$path" ]] && tar_paths+=("$path")
        done

        if [[ "${#tar_paths[@]}" -gt 0 ]]; then
            tar -czf "$PACKAGE" \
                -C "$REPO_ROOT" \
                "${tar_paths[@]}" 2>/dev/null || true
        fi

        echo
        echo "Resumo:"
        echo "  $REPORT_DIR/summary.txt"
        echo
        echo "Pacote para envio:"
        echo "  $PACKAGE"
    fi

    cleanup_temp
    exit "$result"
}

trap finalize EXIT

[[ -d "$REPO" ]] || fail "diretório do projeto não encontrado: $REPO"

cd "$REPO"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || \
    fail "o diretório informado não é um repositório Git válido."

cd "$REPO_ROOT"

BUILD_DIR="$REPO_ROOT/$BUILD_DIR_REL"
SANITIZER_BUILD_DIR="$REPO_ROOT/$SANITIZER_BUILD_DIR_REL"
REPORT_DIR="$REPO_ROOT/$REPORT_DIR_REL"
PACKAGE="$REPO_ROOT/$PACKAGE_REL"
DOC_DIR="$REPO_ROOT/$DOC_DIR_REL"
PUBLIC_INCLUDE_DIR="$REPO_ROOT/$PUBLIC_INCLUDE_DIR_REL"
PORTABLE_DIR="$REPO_ROOT/$PORTABLE_DIR_REL"
TEST_DIR="$REPO_ROOT/$TEST_DIR_REL"

rm -rf -- "$REPORT_DIR"
mkdir -p "$REPORT_DIR"

REPORT_ACTIVE=1
exec > >(tee "$REPORT_DIR/run.log") 2>&1

log "============================================================"
log " SILENT HILL DECOMP — ETAPA 04 — TIMING DETERMINÍSTICO"
log "============================================================"
log
log "Repositório: $REPO_ROOT"
log "Branch atual: $(git branch --show-current)"
log "Commit atual: $(git rev-parse HEAD)"
log

PHASE="validação da etapa 03"

if [[ ! -s "$PUBLIC_INCLUDE_DIR/sh_api.h" ||
      ! -s "$PORTABLE_DIR/src/sh_runtime.c" ||
      ! -s "$TEST_DIR/test_rng.c" ]]; then

    if [[ -f "$REPO_ROOT/$STAGE03_ARCHIVE_REL" ]]; then
        log "Restaurando fontes da etapa 03 a partir do pacote local..."

        tar -xzf "$REPO_ROOT/$STAGE03_ARCHIVE_REL" \
            -C "$REPO_ROOT" \
            "$DOC_DIR_REL" \
            "$PUBLIC_INCLUDE_DIR_REL" \
            "$PORTABLE_DIR_REL" \
            "$TEST_DIR_REL"
    else
        fail "fontes da etapa 03 não encontradas."
    fi
fi

for required_file in \
    "$PUBLIC_INCLUDE_DIR/sh_api.h" \
    "$PUBLIC_INCLUDE_DIR/sh_host.h" \
    "$PUBLIC_INCLUDE_DIR/sh_result.h" \
    "$PUBLIC_INCLUDE_DIR/sh_rng.h" \
    "$PUBLIC_INCLUDE_DIR/sh_types.h" \
    "$PORTABLE_DIR/CMakeLists.txt" \
    "$PORTABLE_DIR/src/sh_runtime.c" \
    "$PORTABLE_DIR/src/sh_runtime_internal.h" \
    "$PORTABLE_DIR/src/sh_rng.c" \
    "$TEST_DIR/test_rng.c" \
    "$TEST_DIR/test_api_contract.c" \
    "$TEST_DIR/test_abi_layout.c"; do

    [[ -s "$required_file" ]] || \
        fail "arquivo obrigatório da etapa 03 ausente: $required_file"
done

PHASE="validação do baseline matching"

BASELINE_SUMMARY="$REPO_ROOT/$BASELINE_DIR_REL/summary.txt"

if [[ ! -f "$BASELINE_SUMMARY" ]]; then
    if [[ -f "$REPO_ROOT/$BASELINE_ARCHIVE_REL" ]]; then
        TEMP_DIR="$(mktemp -d)"

        tar -xzf "$REPO_ROOT/$BASELINE_ARCHIVE_REL" \
            -C "$TEMP_DIR" \
            "$BASELINE_DIR_REL/summary.txt"

        BASELINE_SUMMARY="$TEMP_DIR/$BASELINE_DIR_REL/summary.txt"
    else
        fail "baseline da etapa 01 não encontrado."
    fi
fi

grep -q '^Estado: baseline matching concluído com sucesso$' \
    "$BASELINE_SUMMARY" || \
    fail "o baseline matching não está confirmado."

BASELINE_COMMIT="$(
    awk -F': ' '
        /^Commit: / {
            print $2;
            exit;
        }
    ' "$BASELINE_SUMMARY"
)"

[[ "$BASELINE_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]] || \
    fail "commit do baseline inválido."

git cat-file -e "$BASELINE_COMMIT^{commit}" 2>/dev/null || \
    fail "commit do baseline não encontrado no clone."

PHASE="proteção das alterações locais"

check_changed_paths unstaged || \
    fail "existem alterações rastreadas fora do escopo de portabilidade."

check_changed_paths staged || \
    fail "existem alterações preparadas fora do escopo de portabilidade."

CURRENT_BRANCH="$(git branch --show-current)"

if [[ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        fail "não é seguro trocar de branch com alterações rastreadas."
    fi

    if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
        git switch "$TARGET_BRANCH"
    else
        git switch -c "$TARGET_BRANCH" "$BASELINE_COMMIT"
    fi
fi

git merge-base --is-ancestor "$BASELINE_COMMIT" HEAD || \
    fail "a branch não descende do baseline validado."

write_local_excludes
ensure_required_tools

PHASE="criação dos diretórios"

mkdir -p \
    "$PUBLIC_INCLUDE_DIR" \
    "$PORTABLE_DIR/src" \
    "$TEST_DIR" \
    "$DOC_DIR"

# ---------------------------------------------------------------------------
# ABI pública 0.2.
# ---------------------------------------------------------------------------

PHASE="atualização da ABI pública"

cat > "$PUBLIC_INCLUDE_DIR/sh_types.h" <<'EOF'
#ifndef SILENT_HILL_SH_TYPES_H
#define SILENT_HILL_SH_TYPES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) && !defined(SH_STATIC)
    #if defined(SH_BUILDING_LIBRARY)
        #define SH_API __declspec(dllexport)
    #else
        #define SH_API __declspec(dllimport)
    #endif
#elif defined(__GNUC__) || defined(__clang__)
    #define SH_API __attribute__((visibility("default")))
#else
    #define SH_API
#endif

#define SH_VERSION_MAJOR 0u
#define SH_VERSION_MINOR 2u
#define SH_VERSION_PATCH 0u
#define SH_VERSION_STRING "0.2.0"

#define SH_ABI_VERSION_ENCODE(major, minor) \
    ((((uint32_t)(major)) << 16u) | ((uint32_t)(minor)))

#define SH_ABI_VERSION_CURRENT \
    SH_ABI_VERSION_ENCODE(SH_VERSION_MAJOR, SH_VERSION_MINOR)

#endif
EOF

cat > "$PUBLIC_INCLUDE_DIR/sh_result.h" <<'EOF'
#ifndef SILENT_HILL_SH_RESULT_H
#define SILENT_HILL_SH_RESULT_H

#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum ShResult
{
    SH_RESULT_OK = 0,
    SH_RESULT_INVALID_ARGUMENT = 1,
    SH_RESULT_UNSUPPORTED_VERSION = 2,
    SH_RESULT_HOST_ERROR = 3,
    SH_RESULT_OUT_OF_MEMORY = 4,
    SH_RESULT_NOT_READY = 5,
    SH_RESULT_OVERFLOW = 6,
    SH_RESULT_INVALID_STATE = 7
} ShResult;

SH_API const char* sh_result_string(ShResult result);

#ifdef __cplusplus
}
#endif

#endif
EOF

cat > "$PUBLIC_INCLUDE_DIR/sh_timing.h" <<'EOF'
#ifndef SILENT_HILL_SH_TIMING_H
#define SILENT_HILL_SH_TIMING_H

#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SH_TICKS_PER_SECOND UINT32_C(60)
#define SH_INTERPOLATION_UNITS_PER_TICK UINT32_C(1000000)
#define SH_DEFAULT_MAX_TICKS_PER_ADVANCE UINT32_C(8)
#define SH_DEFAULT_MAX_FRAME_US UINT64_C(133333)

typedef void (*ShTickFn)(
    void* userdata,
    uint64_t tick_index);

typedef struct ShTimingConfig
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t max_frame_us;
    uint32_t max_ticks_per_advance;
    bool start_paused;
    ShTickFn tick;
    void* tick_userdata;
} ShTimingConfig;

#define SH_TIMING_CONFIG_INIT \
    { \
        (uint32_t)sizeof(ShTimingConfig), \
        SH_ABI_VERSION_CURRENT, \
        SH_DEFAULT_MAX_FRAME_US, \
        SH_DEFAULT_MAX_TICKS_PER_ADVANCE, \
        false, \
        NULL, \
        NULL \
    }

typedef struct ShAdvanceInfo
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t input_elapsed_us;
    uint64_t accepted_elapsed_us;
    uint64_t dropped_elapsed_us;
    uint64_t paused_elapsed_us;
    uint64_t tick_count_before;
    uint64_t tick_count_after;
    uint32_t ticks_executed;
    uint32_t interpolation_units;
    bool paused;
} ShAdvanceInfo;

#define SH_ADVANCE_INFO_INIT \
    { \
        (uint32_t)sizeof(ShAdvanceInfo), \
        SH_ABI_VERSION_CURRENT, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        false \
    }

#ifdef __cplusplus
}
#endif

#endif
EOF

cat > "$PUBLIC_INCLUDE_DIR/sh_api.h" <<'EOF'
#ifndef SILENT_HILL_SH_API_H
#define SILENT_HILL_SH_API_H

#include "silent_hill/sh_host.h"
#include "silent_hill/sh_result.h"
#include "silent_hill/sh_rng.h"
#include "silent_hill/sh_timing.h"
#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ShRuntime ShRuntime;

typedef struct ShRuntimeConfig
{
    uint32_t struct_size;
    uint32_t abi_version;
    const ShHostServices* host;
    uint32_t initial_rng_seed;
    const ShTimingConfig* timing;
} ShRuntimeConfig;

#define SH_RUNTIME_CONFIG_INIT \
    { \
        (uint32_t)sizeof(ShRuntimeConfig), \
        SH_ABI_VERSION_CURRENT, \
        NULL, \
        0u, \
        NULL \
    }

typedef struct ShRuntimeStats
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t update_count;
    uint64_t total_elapsed_us;
    bool booted;
    uint64_t tick_count;
    uint64_t accepted_elapsed_us;
    uint64_t dropped_elapsed_us;
    uint64_t paused_elapsed_us;
    uint32_t interpolation_units;
    uint32_t last_advance_ticks;
    bool paused;
} ShRuntimeStats;

#define SH_RUNTIME_STATS_INIT \
    { \
        (uint32_t)sizeof(ShRuntimeStats), \
        SH_ABI_VERSION_CURRENT, \
        0u, \
        0u, \
        false, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        0u, \
        false \
    }

SH_API uint32_t sh_api_version(void);

SH_API ShResult sh_runtime_create(
    const ShRuntimeConfig* config,
    ShRuntime** out_runtime);

SH_API void sh_runtime_destroy(ShRuntime* runtime);

SH_API ShResult sh_runtime_boot(ShRuntime* runtime);

SH_API ShResult sh_runtime_advance(
    ShRuntime* runtime,
    uint64_t elapsed_us,
    ShAdvanceInfo* out_info);

SH_API ShResult sh_runtime_update(
    ShRuntime* runtime,
    uint64_t elapsed_us);

SH_API ShResult sh_runtime_set_paused(
    ShRuntime* runtime,
    bool paused);

SH_API ShResult sh_runtime_step(
    ShRuntime* runtime,
    ShAdvanceInfo* out_info);

SH_API ShResult sh_runtime_get_stats(
    const ShRuntime* runtime,
    ShRuntimeStats* out_stats);

#ifdef __cplusplus
}
#endif

#endif
EOF

# ---------------------------------------------------------------------------
# Relógio interno e runtime.
# ---------------------------------------------------------------------------

PHASE="implementação do relógio determinístico"

cat > "$PORTABLE_DIR/src/sh_clock.h" <<'EOF'
#ifndef SILENT_HILL_SH_CLOCK_H
#define SILENT_HILL_SH_CLOCK_H

#include "silent_hill/sh_timing.h"

typedef struct ShClock
{
    uint64_t accumulator_units;
    uint64_t max_frame_us;
    uint32_t max_ticks_per_advance;
    bool paused;
} ShClock;

typedef struct ShClockAdvance
{
    uint64_t input_elapsed_us;
    uint64_t accepted_elapsed_us;
    uint64_t dropped_elapsed_us;
    uint64_t paused_elapsed_us;
    uint32_t ticks;
    uint32_t interpolation_units;
    bool paused;
} ShClockAdvance;

bool sh_clock_configure(
    ShClock* clock,
    const ShTimingConfig* config);

void sh_clock_set_paused(
    ShClock* clock,
    bool paused);

bool sh_clock_is_paused(
    const ShClock* clock);

void sh_clock_advance(
    ShClock* clock,
    uint64_t elapsed_us,
    ShClockAdvance* advance);

#endif
EOF

cat > "$PORTABLE_DIR/src/sh_clock.c" <<'EOF'
#include "sh_clock.h"

#include <limits.h>

#define SH_CLOCK_UNITS_PER_SECOND UINT64_C(1000000)
#define SH_CLOCK_TICKS_PER_SECOND UINT64_C(60)

static bool sh_clock_limits_are_valid(
    uint64_t max_frame_us,
    uint32_t max_ticks_per_advance)
{
    uint64_t frame_units;
    uint64_t tick_capacity_units;

    if (max_frame_us == 0u || max_ticks_per_advance == 0u)
    {
        return false;
    }

    if (max_frame_us > (UINT64_MAX / SH_CLOCK_TICKS_PER_SECOND))
    {
        return false;
    }

    frame_units = max_frame_us * SH_CLOCK_TICKS_PER_SECOND;
    tick_capacity_units =
        (uint64_t)max_ticks_per_advance *
        SH_CLOCK_UNITS_PER_SECOND;

    return frame_units <= tick_capacity_units;
}

bool sh_clock_configure(
    ShClock* clock,
    const ShTimingConfig* config)
{
    ShTimingConfig defaults = SH_TIMING_CONFIG_INIT;
    const ShTimingConfig* selected = config != NULL ? config : &defaults;

    if (clock == NULL)
    {
        return false;
    }

    if (!sh_clock_limits_are_valid(
            selected->max_frame_us,
            selected->max_ticks_per_advance))
    {
        return false;
    }

    clock->accumulator_units = 0u;
    clock->max_frame_us = selected->max_frame_us;
    clock->max_ticks_per_advance =
        selected->max_ticks_per_advance;
    clock->paused = selected->start_paused;

    return true;
}

void sh_clock_set_paused(
    ShClock* clock,
    bool paused)
{
    if (clock != NULL)
    {
        clock->paused = paused;
    }
}

bool sh_clock_is_paused(
    const ShClock* clock)
{
    return clock != NULL && clock->paused;
}

void sh_clock_advance(
    ShClock* clock,
    uint64_t elapsed_us,
    ShClockAdvance* advance)
{
    uint64_t accepted_us;
    uint64_t total_units;

    if (clock == NULL || advance == NULL)
    {
        return;
    }

    advance->input_elapsed_us = elapsed_us;
    advance->accepted_elapsed_us = 0u;
    advance->dropped_elapsed_us = 0u;
    advance->paused_elapsed_us = 0u;
    advance->ticks = 0u;
    advance->interpolation_units =
        (uint32_t)clock->accumulator_units;
    advance->paused = clock->paused;

    if (clock->paused)
    {
        advance->paused_elapsed_us = elapsed_us;
        return;
    }

    accepted_us =
        elapsed_us > clock->max_frame_us ?
        clock->max_frame_us :
        elapsed_us;

    advance->accepted_elapsed_us = accepted_us;
    advance->dropped_elapsed_us = elapsed_us - accepted_us;

    total_units =
        clock->accumulator_units +
        (accepted_us * SH_CLOCK_TICKS_PER_SECOND);

    advance->ticks =
        (uint32_t)(total_units / SH_CLOCK_UNITS_PER_SECOND);

    clock->accumulator_units =
        total_units % SH_CLOCK_UNITS_PER_SECOND;

    advance->interpolation_units =
        (uint32_t)clock->accumulator_units;
}
EOF

cat > "$PORTABLE_DIR/src/sh_runtime_internal.h" <<'EOF'
#ifndef SILENT_HILL_SH_RUNTIME_INTERNAL_H
#define SILENT_HILL_SH_RUNTIME_INTERNAL_H

#include "silent_hill/sh_api.h"

#include "sh_clock.h"

struct ShRuntime
{
    ShHostServices host;
    ShRng rng;
    ShClock clock;
    ShTickFn tick;
    void* tick_userdata;
    uint64_t update_count;
    uint64_t total_elapsed_us;
    uint64_t tick_count;
    uint64_t accepted_elapsed_us;
    uint64_t dropped_elapsed_us;
    uint64_t paused_elapsed_us;
    uint32_t last_advance_ticks;
    bool booted;
};

#endif
EOF

cat > "$PORTABLE_DIR/src/sh_runtime.c" <<'EOF'
#include "sh_runtime_internal.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

static bool sh_size_is_supported(uint32_t supplied, size_t required)
{
    if (required > (size_t)UINT32_MAX)
    {
        return false;
    }

    return supplied >= (uint32_t)required;
}

static bool sh_u64_add_would_overflow(
    uint64_t lhs,
    uint64_t rhs)
{
    return UINT64_MAX - lhs < rhs;
}

static void sh_runtime_log(
    const ShRuntime* runtime,
    ShLogLevel level,
    const char* message)
{
    if (runtime != NULL && runtime->host.log != NULL)
    {
        runtime->host.log(runtime->host.userdata, level, message);
    }
}

static ShResult sh_advance_info_validate(
    const ShAdvanceInfo* info)
{
    if (info == NULL)
    {
        return SH_RESULT_OK;
    }

    if (!sh_size_is_supported(
            info->struct_size,
            sizeof(ShAdvanceInfo)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (info->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    return SH_RESULT_OK;
}

static void sh_advance_info_write(
    ShAdvanceInfo* info,
    const ShClockAdvance* clock_advance,
    uint64_t tick_count_before,
    uint64_t tick_count_after)
{
    if (info == NULL)
    {
        return;
    }

    info->struct_size = (uint32_t)sizeof(ShAdvanceInfo);
    info->abi_version = SH_ABI_VERSION_CURRENT;
    info->input_elapsed_us = clock_advance->input_elapsed_us;
    info->accepted_elapsed_us =
        clock_advance->accepted_elapsed_us;
    info->dropped_elapsed_us =
        clock_advance->dropped_elapsed_us;
    info->paused_elapsed_us =
        clock_advance->paused_elapsed_us;
    info->tick_count_before = tick_count_before;
    info->tick_count_after = tick_count_after;
    info->ticks_executed = clock_advance->ticks;
    info->interpolation_units =
        clock_advance->interpolation_units;
    info->paused = clock_advance->paused;
}

static void sh_runtime_execute_ticks(
    ShRuntime* runtime,
    uint32_t tick_count)
{
    uint32_t idx;

    for (idx = 0u; idx < tick_count; idx++)
    {
        runtime->tick_count++;

        if (runtime->tick != NULL)
        {
            runtime->tick(
                runtime->tick_userdata,
                runtime->tick_count);
        }
    }
}

uint32_t sh_api_version(void)
{
    return SH_ABI_VERSION_CURRENT;
}

const char* sh_result_string(ShResult result)
{
    switch (result)
    {
        case SH_RESULT_OK:
            return "ok";

        case SH_RESULT_INVALID_ARGUMENT:
            return "invalid argument";

        case SH_RESULT_UNSUPPORTED_VERSION:
            return "unsupported version";

        case SH_RESULT_HOST_ERROR:
            return "host error";

        case SH_RESULT_OUT_OF_MEMORY:
            return "out of memory";

        case SH_RESULT_NOT_READY:
            return "not ready";

        case SH_RESULT_OVERFLOW:
            return "overflow";

        case SH_RESULT_INVALID_STATE:
            return "invalid state";

        default:
            return "unknown result";
    }
}

ShResult sh_runtime_create(
    const ShRuntimeConfig* config,
    ShRuntime** out_runtime)
{
    ShRuntime* runtime;
    ShTimingConfig default_timing = SH_TIMING_CONFIG_INIT;
    const ShTimingConfig* timing;

    if (out_runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    *out_runtime = NULL;

    if (config == NULL || config->host == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_size_is_supported(
            config->struct_size,
            sizeof(ShRuntimeConfig)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (config->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    if (!sh_size_is_supported(
            config->host->struct_size,
            sizeof(ShHostServices)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (config->host->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    timing =
        config->timing != NULL ?
        config->timing :
        &default_timing;

    if (!sh_size_is_supported(
            timing->struct_size,
            sizeof(ShTimingConfig)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (timing->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    runtime = (ShRuntime*)calloc(1u, sizeof(*runtime));

    if (runtime == NULL)
    {
        return SH_RESULT_OUT_OF_MEMORY;
    }

    if (!sh_clock_configure(&runtime->clock, timing))
    {
        free(runtime);
        return SH_RESULT_INVALID_ARGUMENT;
    }

    memcpy(&runtime->host, config->host, sizeof(runtime->host));
    sh_rng_init(&runtime->rng, config->initial_rng_seed);

    runtime->tick = timing->tick;
    runtime->tick_userdata = timing->tick_userdata;

    *out_runtime = runtime;
    return SH_RESULT_OK;
}

void sh_runtime_destroy(ShRuntime* runtime)
{
    free(runtime);
}

ShResult sh_runtime_boot(ShRuntime* runtime)
{
    if (runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        runtime->booted = true;

        sh_runtime_log(
            runtime,
            SH_LOG_LEVEL_INFO,
            "silent_hill_core: runtime booted");
    }

    return SH_RESULT_OK;
}

ShResult sh_runtime_advance(
    ShRuntime* runtime,
    uint64_t elapsed_us,
    ShAdvanceInfo* out_info)
{
    ShClockAdvance advance;
    ShResult info_result;
    uint64_t accumulator_before;
    uint64_t tick_count_before;

    if (runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    info_result = sh_advance_info_validate(out_info);

    if (info_result != SH_RESULT_OK)
    {
        return info_result;
    }

    accumulator_before = runtime->clock.accumulator_units;
    sh_clock_advance(&runtime->clock, elapsed_us, &advance);

    if (sh_u64_add_would_overflow(
            runtime->total_elapsed_us,
            advance.input_elapsed_us) ||
        sh_u64_add_would_overflow(
            runtime->accepted_elapsed_us,
            advance.accepted_elapsed_us) ||
        sh_u64_add_would_overflow(
            runtime->dropped_elapsed_us,
            advance.dropped_elapsed_us) ||
        sh_u64_add_would_overflow(
            runtime->paused_elapsed_us,
            advance.paused_elapsed_us) ||
        sh_u64_add_would_overflow(
            runtime->tick_count,
            (uint64_t)advance.ticks) ||
        runtime->update_count == UINT64_MAX)
    {
        runtime->clock.accumulator_units = accumulator_before;
        return SH_RESULT_OVERFLOW;
    }

    tick_count_before = runtime->tick_count;

    runtime->update_count++;
    runtime->total_elapsed_us += advance.input_elapsed_us;
    runtime->accepted_elapsed_us +=
        advance.accepted_elapsed_us;
    runtime->dropped_elapsed_us +=
        advance.dropped_elapsed_us;
    runtime->paused_elapsed_us +=
        advance.paused_elapsed_us;
    runtime->last_advance_ticks = advance.ticks;

    sh_runtime_execute_ticks(runtime, advance.ticks);

    sh_advance_info_write(
        out_info,
        &advance,
        tick_count_before,
        runtime->tick_count);

    return SH_RESULT_OK;
}

ShResult sh_runtime_update(
    ShRuntime* runtime,
    uint64_t elapsed_us)
{
    return sh_runtime_advance(runtime, elapsed_us, NULL);
}

ShResult sh_runtime_set_paused(
    ShRuntime* runtime,
    bool paused)
{
    if (runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    sh_clock_set_paused(&runtime->clock, paused);

    return SH_RESULT_OK;
}

ShResult sh_runtime_step(
    ShRuntime* runtime,
    ShAdvanceInfo* out_info)
{
    ShClockAdvance advance = {
        0u,
        0u,
        0u,
        0u,
        1u,
        0u,
        true
    };
    ShResult info_result;
    uint64_t tick_count_before;

    if (runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    if (!sh_clock_is_paused(&runtime->clock))
    {
        return SH_RESULT_INVALID_STATE;
    }

    info_result = sh_advance_info_validate(out_info);

    if (info_result != SH_RESULT_OK)
    {
        return info_result;
    }

    if (runtime->update_count == UINT64_MAX ||
        runtime->tick_count == UINT64_MAX)
    {
        return SH_RESULT_OVERFLOW;
    }

    advance.interpolation_units =
        (uint32_t)runtime->clock.accumulator_units;

    tick_count_before = runtime->tick_count;

    runtime->update_count++;
    runtime->last_advance_ticks = 1u;

    sh_runtime_execute_ticks(runtime, 1u);

    sh_advance_info_write(
        out_info,
        &advance,
        tick_count_before,
        runtime->tick_count);

    return SH_RESULT_OK;
}

ShResult sh_runtime_get_stats(
    const ShRuntime* runtime,
    ShRuntimeStats* out_stats)
{
    if (runtime == NULL || out_stats == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_size_is_supported(
            out_stats->struct_size,
            sizeof(ShRuntimeStats)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_stats->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    out_stats->struct_size = (uint32_t)sizeof(ShRuntimeStats);
    out_stats->abi_version = SH_ABI_VERSION_CURRENT;
    out_stats->update_count = runtime->update_count;
    out_stats->total_elapsed_us = runtime->total_elapsed_us;
    out_stats->booted = runtime->booted;
    out_stats->tick_count = runtime->tick_count;
    out_stats->accepted_elapsed_us =
        runtime->accepted_elapsed_us;
    out_stats->dropped_elapsed_us =
        runtime->dropped_elapsed_us;
    out_stats->paused_elapsed_us =
        runtime->paused_elapsed_us;
    out_stats->interpolation_units =
        (uint32_t)runtime->clock.accumulator_units;
    out_stats->last_advance_ticks =
        runtime->last_advance_ticks;
    out_stats->paused =
        sh_clock_is_paused(&runtime->clock);

    return SH_RESULT_OK;
}
EOF

# ---------------------------------------------------------------------------
# CMake 0.2.
# ---------------------------------------------------------------------------

PHASE="atualização do build CMake"

cat > "$PORTABLE_DIR/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)

project(
    silent_hill_portable
    VERSION 0.2.0
    LANGUAGES C)

include(CTest)

option(
    SH_ENABLE_WERROR
    "Treat warnings as errors in portable targets."
    ON)

option(
    SH_ENABLE_SANITIZERS
    "Enable AddressSanitizer and UndefinedBehaviorSanitizer."
    OFF)

set(SH_PUBLIC_INCLUDE_DIR "${CMAKE_CURRENT_LIST_DIR}/../include")
set(SH_TEST_DIR "${CMAKE_CURRENT_LIST_DIR}/../tests/portable")

function(sh_configure_target target)
    target_compile_features("${target}" PRIVATE c_std_11)

    if(MSVC)
        target_compile_options("${target}" PRIVATE /W4)

        if(SH_ENABLE_WERROR)
            target_compile_options("${target}" PRIVATE /WX)
        endif()
    elseif(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(
            "${target}"
            PRIVATE
                -Wall
                -Wextra
                -Wpedantic
                -Wconversion
                -Wshadow
                -Wstrict-prototypes)

        if(SH_ENABLE_WERROR)
            target_compile_options("${target}" PRIVATE -Werror)
        endif()

        if(SH_ENABLE_SANITIZERS)
            target_compile_options(
                "${target}"
                PRIVATE
                    -fsanitize=address,undefined
                    -fno-omit-frame-pointer)

            target_link_options(
                "${target}"
                PRIVATE
                    -fsanitize=address,undefined)
        endif()
    endif()
endfunction()

add_library(
    silent_hill_core_objects
    OBJECT
        src/sh_clock.c
        src/sh_rng.c
        src/sh_runtime.c)

set_target_properties(
    silent_hill_core_objects
    PROPERTIES
        POSITION_INDEPENDENT_CODE ON
        C_VISIBILITY_PRESET hidden)

target_compile_definitions(
    silent_hill_core_objects
    PRIVATE
        SH_BUILDING_LIBRARY=1)

target_include_directories(
    silent_hill_core_objects
    PUBLIC
        "${SH_PUBLIC_INCLUDE_DIR}"
    PRIVATE
        "${CMAKE_CURRENT_LIST_DIR}/src")

sh_configure_target(silent_hill_core_objects)

add_library(
    silent_hill_core
    STATIC
        $<TARGET_OBJECTS:silent_hill_core_objects>)

target_include_directories(
    silent_hill_core
    PUBLIC
        "${SH_PUBLIC_INCLUDE_DIR}")

target_compile_definitions(
    silent_hill_core
    PUBLIC
        SH_STATIC=1)

set_target_properties(
    silent_hill_core
    PROPERTIES
        OUTPUT_NAME silent_hill_core)

add_library(
    silent_hill_core_shared
    SHARED
        $<TARGET_OBJECTS:silent_hill_core_objects>)

target_include_directories(
    silent_hill_core_shared
    PUBLIC
        "${SH_PUBLIC_INCLUDE_DIR}")

target_compile_definitions(
    silent_hill_core_shared
    PRIVATE
        SH_BUILDING_LIBRARY=1)

set_target_properties(
    silent_hill_core_shared
    PROPERTIES
        OUTPUT_NAME silent_hill_core
        VERSION "${PROJECT_VERSION}"
        SOVERSION "${PROJECT_VERSION_MAJOR}"
        C_VISIBILITY_PRESET hidden)

if(SH_ENABLE_SANITIZERS AND
   CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_link_options(
        silent_hill_core_shared
        PRIVATE
            -fsanitize=address,undefined)
endif()

if(BUILD_TESTING)
    add_executable(
        sh_rng_tests
        "${SH_TEST_DIR}/test_rng.c")

    target_link_libraries(
        sh_rng_tests
        PRIVATE
            silent_hill_core)

    sh_configure_target(sh_rng_tests)

    add_test(
        NAME sh_rng_tests
        COMMAND sh_rng_tests)

    add_executable(
        sh_api_contract_tests
        "${SH_TEST_DIR}/test_api_contract.c")

    target_link_libraries(
        sh_api_contract_tests
        PRIVATE
            silent_hill_core)

    sh_configure_target(sh_api_contract_tests)

    add_test(
        NAME sh_api_contract_tests
        COMMAND sh_api_contract_tests)

    add_executable(
        sh_abi_layout_tests
        "${SH_TEST_DIR}/test_abi_layout.c")

    target_link_libraries(
        sh_abi_layout_tests
        PRIVATE
            silent_hill_core)

    sh_configure_target(sh_abi_layout_tests)

    add_test(
        NAME sh_abi_layout_tests
        COMMAND sh_abi_layout_tests)

    add_executable(
        sh_timing_tests
        "${SH_TEST_DIR}/test_timing.c")

    target_link_libraries(
        sh_timing_tests
        PRIVATE
            silent_hill_core)

    sh_configure_target(sh_timing_tests)

    add_test(
        NAME sh_timing_tests
        COMMAND sh_timing_tests)
endif()
EOF

# ---------------------------------------------------------------------------
# Testes atualizados.
# ---------------------------------------------------------------------------

PHASE="criação dos testes determinísticos"

cat > "$TEST_DIR/test_api_contract.c" <<'EOF'
#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stdint.h>
#include <string.h>

typedef struct TestHost
{
    uint32_t log_count;
    ShLogLevel last_level;
    const char* last_message;
} TestHost;

static uint64_t test_time_now_us(void* userdata)
{
    (void)userdata;
    return UINT64_C(123456);
}

static void test_log(
    void* userdata,
    ShLogLevel level,
    const char* message)
{
    TestHost* host = (TestHost*)userdata;

    assert(host != NULL);
    assert(message != NULL);

    host->log_count++;
    host->last_level = level;
    host->last_message = message;
}

static bool test_file_read(
    void* userdata,
    const char* path,
    uint64_t offset,
    void* destination,
    size_t size)
{
    (void)userdata;
    (void)path;
    (void)offset;
    (void)destination;
    (void)size;

    return false;
}

static void test_invalid_arguments(void)
{
    ShRuntime* runtime = (ShRuntime*)(uintptr_t)1u;
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;

    config.host = &host;

    assert(
        sh_runtime_create(NULL, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);

    assert(runtime == NULL);

    assert(
        sh_runtime_create(&config, NULL) ==
        SH_RESULT_INVALID_ARGUMENT);

    config.host = NULL;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);

    assert(runtime == NULL);
}

static void test_version_size_and_timing_validation(void)
{
    ShRuntime* runtime = NULL;
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;

    config.host = &host;

    config.struct_size = 1u;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);

    config = (ShRuntimeConfig)SH_RUNTIME_CONFIG_INIT;
    config.host = &host;
    config.abi_version = UINT32_C(0xFFFFFFFF);

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_UNSUPPORTED_VERSION);

    config = (ShRuntimeConfig)SH_RUNTIME_CONFIG_INIT;
    host = (ShHostServices)SH_HOST_SERVICES_INIT;
    config.host = &host;
    host.struct_size = 1u;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);

    host = (ShHostServices)SH_HOST_SERVICES_INIT;
    config.host = &host;
    host.abi_version = UINT32_C(0xFFFFFFFF);

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_UNSUPPORTED_VERSION);

    host = (ShHostServices)SH_HOST_SERVICES_INIT;
    config = (ShRuntimeConfig)SH_RUNTIME_CONFIG_INIT;
    config.host = &host;
    config.timing = &timing;
    timing.struct_size = 1u;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);

    timing = (ShTimingConfig)SH_TIMING_CONFIG_INIT;
    config.timing = &timing;
    timing.abi_version = UINT32_C(0xFFFFFFFF);

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_UNSUPPORTED_VERSION);

    timing = (ShTimingConfig)SH_TIMING_CONFIG_INIT;
    config.timing = &timing;
    timing.max_ticks_per_advance = 1u;
    timing.max_frame_us = UINT64_C(16667);

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);
}

static void test_runtime_lifecycle(void)
{
    TestHost test_host = { 0u, SH_LOG_LEVEL_DEBUG, NULL };
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime = NULL;

    host.userdata = &test_host;
    host.time_now_us = test_time_now_us;
    host.log = test_log;
    host.file_read = test_file_read;

    config.host = &host;
    config.initial_rng_seed = UINT32_C(0x12345678);

    assert(sh_api_version() == SH_ABI_VERSION_CURRENT);

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_OK);

    assert(runtime != NULL);

    assert(
        sh_runtime_update(runtime, UINT64_C(16667)) ==
        SH_RESULT_NOT_READY);

    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);

    assert(test_host.log_count == 1u);
    assert(test_host.last_level == SH_LOG_LEVEL_INFO);
    assert(test_host.last_message != NULL);

    assert(
        strcmp(
            test_host.last_message,
            "silent_hill_core: runtime booted") == 0);

    assert(
        sh_runtime_update(runtime, UINT64_C(16667)) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_update(runtime, UINT64_C(33333)) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_get_stats(runtime, &stats) ==
        SH_RESULT_OK);

    assert(stats.struct_size == (uint32_t)sizeof(stats));
    assert(stats.abi_version == SH_ABI_VERSION_CURRENT);
    assert(stats.update_count == UINT64_C(2));
    assert(stats.total_elapsed_us == UINT64_C(50000));
    assert(stats.tick_count == UINT64_C(3));
    assert(stats.accepted_elapsed_us == UINT64_C(50000));
    assert(stats.dropped_elapsed_us == UINT64_C(0));
    assert(stats.paused_elapsed_us == UINT64_C(0));
    assert(stats.interpolation_units == 0u);
    assert(stats.last_advance_ticks == 2u);
    assert(stats.booted);
    assert(!stats.paused);

    sh_runtime_destroy(runtime);
    sh_runtime_destroy(NULL);
}

static void test_result_strings(void)
{
    assert(strcmp(sh_result_string(SH_RESULT_OK), "ok") == 0);

    assert(
        strcmp(
            sh_result_string(SH_RESULT_NOT_READY),
            "not ready") == 0);

    assert(
        strcmp(
            sh_result_string(SH_RESULT_INVALID_STATE),
            "invalid state") == 0);

    assert(
        strcmp(
            sh_result_string((ShResult)9999),
            "unknown result") == 0);
}

int main(void)
{
    test_invalid_arguments();
    test_version_size_and_timing_validation();
    test_runtime_lifecycle();
    test_result_strings();

    return 0;
}
EOF

cat > "$TEST_DIR/test_abi_layout.c" <<'EOF'
#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stddef.h>
#include <stdint.h>

_Static_assert(sizeof(uint8_t) == 1u, "uint8_t must be 8-bit");
_Static_assert(sizeof(uint16_t) == 2u, "uint16_t must be 16-bit");
_Static_assert(sizeof(uint32_t) == 4u, "uint32_t must be 32-bit");
_Static_assert(sizeof(uint64_t) == 8u, "uint64_t must be 64-bit");

_Static_assert(
    offsetof(ShHostServices, struct_size) == 0u,
    "struct_size must be the first host field");

_Static_assert(
    offsetof(ShHostServices, abi_version) == sizeof(uint32_t),
    "abi_version must follow struct_size");

_Static_assert(
    offsetof(ShTimingConfig, struct_size) == 0u,
    "struct_size must be the first timing field");

_Static_assert(
    offsetof(ShTimingConfig, abi_version) == sizeof(uint32_t),
    "abi_version must follow struct_size");

_Static_assert(
    offsetof(ShRuntimeConfig, struct_size) == 0u,
    "struct_size must be the first config field");

_Static_assert(
    offsetof(ShRuntimeConfig, abi_version) == sizeof(uint32_t),
    "abi_version must follow struct_size");

_Static_assert(
    offsetof(ShAdvanceInfo, struct_size) == 0u,
    "struct_size must be the first advance field");

_Static_assert(
    offsetof(ShRuntimeStats, struct_size) == 0u,
    "struct_size must be the first stats field");

_Static_assert(
    sizeof(ShRng) == sizeof(uint32_t),
    "ShRng must contain exactly one 32-bit seed");

int main(void)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;

    assert(host.struct_size == (uint32_t)sizeof(host));
    assert(timing.struct_size == (uint32_t)sizeof(timing));
    assert(config.struct_size == (uint32_t)sizeof(config));
    assert(advance.struct_size == (uint32_t)sizeof(advance));
    assert(stats.struct_size == (uint32_t)sizeof(stats));

    assert(host.abi_version == SH_ABI_VERSION_CURRENT);
    assert(timing.abi_version == SH_ABI_VERSION_CURRENT);
    assert(config.abi_version == SH_ABI_VERSION_CURRENT);
    assert(advance.abi_version == SH_ABI_VERSION_CURRENT);
    assert(stats.abi_version == SH_ABI_VERSION_CURRENT);

    assert(SH_TICKS_PER_SECOND == 60u);
    assert(SH_INTERPOLATION_UNITS_PER_TICK == 1000000u);

    return 0;
}
EOF

cat > "$TEST_DIR/test_timing.c" <<'EOF'
#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stdint.h>

typedef struct TickRecorder
{
    uint64_t count;
    uint64_t last_tick;
} TickRecorder;

static void record_tick(
    void* userdata,
    uint64_t tick_index)
{
    TickRecorder* recorder = (TickRecorder*)userdata;

    assert(recorder != NULL);
    assert(tick_index == recorder->last_tick + 1u);

    recorder->count++;
    recorder->last_tick = tick_index;
}

static ShRuntime* create_runtime(
    TickRecorder* recorder,
    bool start_paused)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntime* runtime = NULL;

    timing.start_paused = start_paused;
    timing.tick = record_tick;
    timing.tick_userdata = recorder;

    config.host = &host;
    config.timing = &timing;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_OK);

    assert(runtime != NULL);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);

    return runtime;
}

static void test_exact_sixty_ticks_per_second(void)
{
    TickRecorder recorder = { 0u, 0u };
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime = create_runtime(&recorder, false);
    uint32_t idx;

    for (idx = 0u; idx < 40u; idx++)
    {
        assert(
            sh_runtime_advance(
                runtime,
                UINT64_C(16667),
                NULL) == SH_RESULT_OK);
    }

    for (idx = 0u; idx < 20u; idx++)
    {
        assert(
            sh_runtime_advance(
                runtime,
                UINT64_C(16666),
                NULL) == SH_RESULT_OK);
    }

    assert(
        sh_runtime_get_stats(runtime, &stats) ==
        SH_RESULT_OK);

    assert(stats.update_count == UINT64_C(60));
    assert(stats.total_elapsed_us == UINT64_C(1000000));
    assert(stats.accepted_elapsed_us == UINT64_C(1000000));
    assert(stats.dropped_elapsed_us == UINT64_C(0));
    assert(stats.tick_count == UINT64_C(60));
    assert(stats.interpolation_units == 0u);

    assert(recorder.count == UINT64_C(60));
    assert(recorder.last_tick == UINT64_C(60));

    sh_runtime_destroy(runtime);
}

static void test_subdivision_equivalence(void)
{
    TickRecorder recorder_a = { 0u, 0u };
    TickRecorder recorder_b = { 0u, 0u };
    ShRuntimeStats stats_a = SH_RUNTIME_STATS_INIT;
    ShRuntimeStats stats_b = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime_a = create_runtime(&recorder_a, false);
    ShRuntime* runtime_b = create_runtime(&recorder_b, false);
    static const uint64_t irregular[] = {
        UINT64_C(1000),
        UINT64_C(19000),
        UINT64_C(7000),
        UINT64_C(41000),
        UINT64_C(32000)
    };
    size_t idx;

    for (idx = 0u;
         idx < (sizeof(irregular) / sizeof(irregular[0]));
         idx++)
    {
        assert(
            sh_runtime_advance(
                runtime_a,
                irregular[idx],
                NULL) == SH_RESULT_OK);
    }

    for (idx = 0u; idx < 100u; idx++)
    {
        assert(
            sh_runtime_advance(
                runtime_b,
                UINT64_C(1000),
                NULL) == SH_RESULT_OK);
    }

    assert(
        sh_runtime_get_stats(runtime_a, &stats_a) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_get_stats(runtime_b, &stats_b) ==
        SH_RESULT_OK);

    assert(stats_a.total_elapsed_us == UINT64_C(100000));
    assert(stats_b.total_elapsed_us == UINT64_C(100000));

    assert(stats_a.tick_count == stats_b.tick_count);
    assert(
        stats_a.interpolation_units ==
        stats_b.interpolation_units);

    assert(stats_a.tick_count == UINT64_C(6));
    assert(stats_a.interpolation_units == 0u);

    assert(recorder_a.count == recorder_b.count);
    assert(recorder_a.last_tick == recorder_b.last_tick);

    sh_runtime_destroy(runtime_a);
    sh_runtime_destroy(runtime_b);
}

static void test_long_frame_clamp(void)
{
    TickRecorder recorder = { 0u, 0u };
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime = create_runtime(&recorder, false);

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(1000000),
            &advance) == SH_RESULT_OK);

    assert(advance.input_elapsed_us == UINT64_C(1000000));
    assert(advance.accepted_elapsed_us == UINT64_C(133333));
    assert(advance.dropped_elapsed_us == UINT64_C(866667));
    assert(advance.paused_elapsed_us == UINT64_C(0));
    assert(advance.ticks_executed == 7u);
    assert(advance.interpolation_units == 999980u);
    assert(advance.tick_count_before == UINT64_C(0));
    assert(advance.tick_count_after == UINT64_C(7));
    assert(!advance.paused);

    advance = (ShAdvanceInfo)SH_ADVANCE_INFO_INIT;

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(1),
            &advance) == SH_RESULT_OK);

    assert(advance.ticks_executed == 1u);
    assert(advance.interpolation_units == 40u);
    assert(advance.tick_count_before == UINT64_C(7));
    assert(advance.tick_count_after == UINT64_C(8));

    assert(
        sh_runtime_get_stats(runtime, &stats) ==
        SH_RESULT_OK);

    assert(stats.total_elapsed_us == UINT64_C(1000001));
    assert(stats.accepted_elapsed_us == UINT64_C(133334));
    assert(stats.dropped_elapsed_us == UINT64_C(866667));
    assert(stats.tick_count == UINT64_C(8));
    assert(stats.interpolation_units == 40u);

    sh_runtime_destroy(runtime);
}

static void test_pause_and_single_step(void)
{
    TickRecorder recorder = { 0u, 0u };
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime = create_runtime(&recorder, true);

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(50000),
            &advance) == SH_RESULT_OK);

    assert(advance.ticks_executed == 0u);
    assert(advance.accepted_elapsed_us == UINT64_C(0));
    assert(advance.dropped_elapsed_us == UINT64_C(0));
    assert(advance.paused_elapsed_us == UINT64_C(50000));
    assert(advance.paused);
    assert(recorder.count == UINT64_C(0));

    advance = (ShAdvanceInfo)SH_ADVANCE_INFO_INIT;

    assert(
        sh_runtime_step(runtime, &advance) ==
        SH_RESULT_OK);

    assert(advance.ticks_executed == 1u);
    assert(advance.tick_count_before == UINT64_C(0));
    assert(advance.tick_count_after == UINT64_C(1));
    assert(advance.paused);
    assert(recorder.count == UINT64_C(1));

    assert(
        sh_runtime_set_paused(runtime, false) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_step(runtime, NULL) ==
        SH_RESULT_INVALID_STATE);

    advance = (ShAdvanceInfo)SH_ADVANCE_INFO_INIT;

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(16667),
            &advance) == SH_RESULT_OK);

    assert(advance.ticks_executed == 1u);
    assert(advance.interpolation_units == 20u);
    assert(!advance.paused);

    assert(
        sh_runtime_get_stats(runtime, &stats) ==
        SH_RESULT_OK);

    assert(stats.update_count == UINT64_C(3));
    assert(stats.total_elapsed_us == UINT64_C(66667));
    assert(stats.accepted_elapsed_us == UINT64_C(16667));
    assert(stats.paused_elapsed_us == UINT64_C(50000));
    assert(stats.tick_count == UINT64_C(2));
    assert(stats.interpolation_units == 20u);
    assert(!stats.paused);

    sh_runtime_destroy(runtime);
}

static void test_overflow_is_reported_without_second_update(void)
{
    TickRecorder recorder = { 0u, 0u };
    ShRuntimeStats before = SH_RUNTIME_STATS_INIT;
    ShRuntimeStats after = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime = create_runtime(&recorder, false);

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_MAX,
            NULL) == SH_RESULT_OK);

    assert(
        sh_runtime_get_stats(runtime, &before) ==
        SH_RESULT_OK);

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(1),
            NULL) == SH_RESULT_OVERFLOW);

    assert(
        sh_runtime_get_stats(runtime, &after) ==
        SH_RESULT_OK);

    assert(after.update_count == before.update_count);
    assert(after.total_elapsed_us == before.total_elapsed_us);
    assert(after.tick_count == before.tick_count);
    assert(
        after.interpolation_units ==
        before.interpolation_units);

    sh_runtime_destroy(runtime);
}

static void test_advance_info_validation(void)
{
    TickRecorder recorder = { 0u, 0u };
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;
    ShRuntime* runtime = create_runtime(&recorder, false);

    advance.struct_size = 1u;

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(1000),
            &advance) == SH_RESULT_INVALID_ARGUMENT);

    advance = (ShAdvanceInfo)SH_ADVANCE_INFO_INIT;
    advance.abi_version = UINT32_C(0xFFFFFFFF);

    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(1000),
            &advance) == SH_RESULT_UNSUPPORTED_VERSION);

    assert(
        sh_runtime_get_stats(runtime, &stats) ==
        SH_RESULT_OK);

    assert(stats.update_count == UINT64_C(0));
    assert(stats.total_elapsed_us == UINT64_C(0));
    assert(stats.tick_count == UINT64_C(0));

    sh_runtime_destroy(runtime);
}

int main(void)
{
    test_exact_sixty_ticks_per_second();
    test_subdivision_equivalence();
    test_long_frame_clamp();
    test_pause_and_single_step();
    test_overflow_is_reported_without_second_update();
    test_advance_info_validation();

    return 0;
}
EOF

# O teste de RNG da etapa 03 permanece inalterado.
[[ -s "$TEST_DIR/test_rng.c" ]] || \
    fail "teste de RNG da etapa 03 foi perdido."

# ---------------------------------------------------------------------------
# Documentação.
# ---------------------------------------------------------------------------

PHASE="documentação da etapa 04"

cat > "$DOC_DIR/STAGE04_DETERMINISTIC_TIMING.md" <<'EOF'
# Etapa 04 — Timing Determinístico

## Objetivo

Separar o avanço lógico do jogo da apresentação e do `VSync` do PlayStation.

## Modelo adotado

O runtime usa um acumulador inteiro exato:

```text
accumulator += elapsed_microseconds * 60
ticks = accumulator / 1.000.000
accumulator %= 1.000.000
```

Esse modelo evita depender de um timestep arredondado de 16.666 ou 16.667
microssegundos. Um segundo exato sempre produz 60 ticks.

## Clamp

O padrão aceita no máximo 133.333 microssegundos por chamada, permitindo até
oito ticks de recuperação. O restante é contabilizado como tempo descartado.

O clamp evita uma espiral de atualização depois de pausas longas do host.

## Pausa

Quando pausado:

- o tempo recebido não entra no acumulador;
- nenhum tick automático é executado;
- o tempo é contabilizado separadamente;
- `sh_runtime_step` executa exatamente um tick.

## Interpolação

`interpolation_units` varia de 0 a 999.999. A fração de apresentação é:

```text
interpolation_units / 1.000.000
```

## Compatibilidade

`sh_runtime_update` permanece exportada e funciona como um atalho para
`sh_runtime_advance` sem solicitar o relatório detalhado.

## Limitações

O callback de tick ainda é um gancho headless. Ele não executa `MainLoop`,
mapas, áudio ou renderização. Essa integração será feita nas etapas seguintes.
EOF

cat > "$DOC_DIR/ABI_DRAFT.md" <<'EOF'
# ABI C Portátil

A etapa 04 implementa a ABI experimental `0.2.0`.

## Lifecycle

```c
ShResult sh_runtime_create(
    const ShRuntimeConfig* config,
    ShRuntime** out_runtime);

ShResult sh_runtime_boot(ShRuntime* runtime);

ShResult sh_runtime_advance(
    ShRuntime* runtime,
    uint64_t elapsed_us,
    ShAdvanceInfo* out_info);

ShResult sh_runtime_set_paused(
    ShRuntime* runtime,
    bool paused);

ShResult sh_runtime_step(
    ShRuntime* runtime,
    ShAdvanceInfo* out_info);

void sh_runtime_destroy(ShRuntime* runtime);
```

## Regras

- estruturas públicas começam com `struct_size` e `abi_version`;
- `ShRuntime` é opaco;
- a API não expõe tipos Psy-Q;
- `sh_runtime_update` permanece como compatibilidade;
- o host controla a cadência e fornece o tempo decorrido;
- o runtime produz ticks lógicos determinísticos de 60 Hz;
- nenhuma ROM ou asset é embutido na biblioteca.
EOF

python3 - "$DOC_DIR/ROADMAP.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old = """## Etapa 04 — Timing determinístico

- extrair fronteira de um frame;
- fornecer tempo pelo host;
- preservar ticks originais;
- permitir execução headless.
"""

new = """## Etapa 04 — Timing determinístico

Status: concluída.

- acumulador inteiro exato de 60 Hz;
- avanço por tempo fornecido pelo host;
- clamp de frames longos;
- pausa e avanço unitário;
- callback headless por tick;
- testes de subdivisão equivalente.
"""

if old in text:
    text = text.replace(old, new)
elif "## Etapa 04 — Timing determinístico\n\nStatus: concluída." not in text:
    raise SystemExit("Não foi possível localizar a seção da etapa 04 no roadmap.")

path.write_text(text, encoding="utf-8", newline="\n")
PY

SOURCE_FILES=(
    "$PUBLIC_INCLUDE_DIR/sh_types.h"
    "$PUBLIC_INCLUDE_DIR/sh_result.h"
    "$PUBLIC_INCLUDE_DIR/sh_timing.h"
    "$PUBLIC_INCLUDE_DIR/sh_api.h"
    "$PORTABLE_DIR/CMakeLists.txt"
    "$PORTABLE_DIR/src/sh_clock.h"
    "$PORTABLE_DIR/src/sh_clock.c"
    "$PORTABLE_DIR/src/sh_runtime_internal.h"
    "$PORTABLE_DIR/src/sh_runtime.c"
    "$TEST_DIR/test_rng.c"
    "$TEST_DIR/test_api_contract.c"
    "$TEST_DIR/test_abi_layout.c"
    "$TEST_DIR/test_timing.c"
    "$DOC_DIR/ABI_DRAFT.md"
    "$DOC_DIR/ROADMAP.md"
    "$DOC_DIR/STAGE04_DETERMINISTIC_TIMING.md"
)

validate_text_files "${SOURCE_FILES[@]}" || \
    fail "a validação textual dos arquivos falhou."

PHASE="configuração do build nativo"

rm -rf -- "$BUILD_DIR"

cmake \
    -S "$PORTABLE_DIR" \
    -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DBUILD_TESTING=ON \
    -DSH_ENABLE_WERROR=ON \
    -DSH_ENABLE_SANITIZERS=OFF \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    2>&1 | tee "$REPORT_DIR/cmake-configure.log"

PHASE="compilação do build nativo"

cmake \
    --build "$BUILD_DIR" \
    --parallel "$(nproc)" \
    2>&1 | tee "$REPORT_DIR/cmake-build.log"

PHASE="testes nativos"

ctest \
    --test-dir "$BUILD_DIR" \
    --output-on-failure \
    2>&1 | tee "$REPORT_DIR/ctest.log"

PHASE="validação dos símbolos da ABI"

SHARED_LIBRARY="$(
    find "$BUILD_DIR" \
        -maxdepth 2 \
        -type f \
        -name 'libsilent_hill_core.so*' \
        -print |
        sort |
        head -n 1
)"

[[ -n "$SHARED_LIBRARY" ]] || \
    fail "biblioteca compartilhada não encontrada."

nm \
    -D \
    --defined-only \
    "$SHARED_LIBRARY" |
    awk '$3 ~ /^sh_/ { print $3 }' |
    sort -u \
    > "$REPORT_DIR/abi-symbols.txt"

cat > "$REPORT_DIR/abi-symbols-expected.txt" <<'EOF'
sh_api_version
sh_result_string
sh_rng_get_seed
sh_rng_init
sh_rng_next_u12
sh_rng_next_u15
sh_rng_next_u32
sh_rng_set_seed
sh_runtime_advance
sh_runtime_boot
sh_runtime_create
sh_runtime_destroy
sh_runtime_get_stats
sh_runtime_set_paused
sh_runtime_step
sh_runtime_update
EOF

diff \
    -u \
    "$REPORT_DIR/abi-symbols-expected.txt" \
    "$REPORT_DIR/abi-symbols.txt" \
    > "$REPORT_DIR/abi-symbols.diff" || {

    cat "$REPORT_DIR/abi-symbols.diff" >&2
    fail "os símbolos exportados não correspondem ao contrato esperado."
}

PHASE="build com sanitizers"

rm -rf -- "$SANITIZER_BUILD_DIR"

cmake \
    -S "$PORTABLE_DIR" \
    -B "$SANITIZER_BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DBUILD_TESTING=ON \
    -DSH_ENABLE_WERROR=ON \
    -DSH_ENABLE_SANITIZERS=ON \
    2>&1 | tee "$REPORT_DIR/cmake-sanitizers-configure.log"

cmake \
    --build "$SANITIZER_BUILD_DIR" \
    --parallel "$(nproc)" \
    2>&1 | tee "$REPORT_DIR/cmake-sanitizers-build.log"

ASAN_OPTIONS="detect_leaks=1:halt_on_error=1" \
UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
ctest \
    --test-dir "$SANITIZER_BUILD_DIR" \
    --output-on-failure \
    2>&1 | tee "$REPORT_DIR/ctest-sanitizers.log"

PHASE="regressão do build matching"

if [[ -f "$REPO_ROOT/.venv/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source "$REPO_ROOT/.venv/bin/activate"
fi

make checksum \
    2>&1 | tee "$REPORT_DIR/matching-checksum.log"

if grep -qE 'FAILED|Falhou|ERRO|Error' \
    "$REPORT_DIR/matching-checksum.log"; then

    fail "a regressão do build matching apresentou falha."
fi

MATCHING_OK_COUNT="$(
    grep -c ': OK$' "$REPORT_DIR/matching-checksum.log" || true
)"

printf '%s\n' "$MATCHING_OK_COUNT" \
    > "$REPORT_DIR/matching-checksum-ok-count.txt"

if [[ "$MATCHING_OK_COUNT" -ne 50 ]]; then
    fail "esperados 50 checksums OK; encontrados $MATCHING_OK_COUNT."
fi

PHASE="inventário final"

{
    echo "Compilador:"
    cmake \
        -S "$PORTABLE_DIR" \
        -B "$BUILD_DIR" \
        -LA \
        -N 2>/dev/null |
        grep -E '^CMAKE_C_COMPILER(:|_)|^CMAKE_BUILD_TYPE:' || true

    echo
    echo "Bibliotecas:"
    find "$BUILD_DIR" \
        -maxdepth 2 \
        -type f \
        \( -name 'libsilent_hill_core.a' -o \
           -name 'libsilent_hill_core.so*' \) \
        -printf '%P\t%s bytes\n' |
        sort

    echo
    echo "Testes:"
    ctest \
        --test-dir "$BUILD_DIR" \
        --show-only=human
} > "$REPORT_DIR/build-inventory.txt"

git diff --check -- \
    "$DOC_DIR_REL" \
    "$PUBLIC_INCLUDE_DIR_REL" \
    "$PORTABLE_DIR_REL" \
    "$TEST_DIR_REL"

FINAL_STATUS="etapa 04 concluída com sucesso"
PHASE="concluída"

log
log "Etapa 04 concluída com sucesso."
log
log "Testes normais: 4 aprovados."
log "Testes ASan/UBSan: 4 aprovados."
log "Símbolos da ABI 0.2: aprovados."
log "Checksums matching: 50 aprovados."
log
log "Nenhum commit foi criado automaticamente."
