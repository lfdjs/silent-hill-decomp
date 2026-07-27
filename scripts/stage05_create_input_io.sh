#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

REPO="${REPO:-$HOME/Documentos/projetos_decompilacao/silent-hill-decomp}"
TARGET_BRANCH="portability/core-api"

BUILD_DIR_REL="build-portable-stage05"
SANITIZER_BUILD_DIR_REL="build-portable-stage05-sanitizers"
REPORT_DIR_REL="stage05-input-io-report"
PACKAGE_REL="stage05-input-io-report.tar.gz"

DOC_DIR_REL="docs/portability"
PUBLIC_INCLUDE_DIR_REL="include/silent_hill"
PORTABLE_DIR_REL="portable"
TEST_DIR_REL="tests/portable"

BASELINE_DIR_REL="stage01-build-baseline"
BASELINE_ARCHIVE_REL="stage01-build-baseline.tar.gz"
STAGE04_ARCHIVE_REL="stage04-deterministic-timing-report.tar.gz"

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
        scripts/stage04_create_deterministic_timing.sh|\
        scripts/stage05_create_input_io.sh)
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

    for tool in cmake ctest cc make nm tar sha256sum diff; do
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
    sudo apt-get install -y cmake build-essential binutils diffutils

    for tool in cmake ctest cc make nm tar sha256sum diff; do
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
        "/stage04-deterministic-timing-report/" \
        "/stage04-deterministic-timing-report.tar.gz" \
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

        printf '%s\0' scripts/stage05_create_input_io.sh
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
            echo "SILENT HILL DECOMP — ETAPA 05"
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
            echo "- ABI C 0.3;"
            echo "- entrada portátil congelada por tick;"
            echo "- deadzone analógica determinística;"
            echo "- fronteira de arquivos e saves;"
            echo "- testes nativos e logs;"
            echo "- documentação da etapa 05;"
            echo "- script persistente usado na etapa."
            echo
            echo "Não contém ROM, BIOS, executáveis do jogo ou assets extraídos."
            echo "Diretórios temporários do CMake não foram incluídos."
        } > "$REPORT_DIR/CONTENTS.txt"

        {
            echo "Git status completo:"
            git status --short --branch 2>/dev/null || true
            echo
            echo "Arquivos relevantes:"
            git status \
                --short \
                --untracked-files=all \
                -- \
                "$DOC_DIR_REL" \
                "$PUBLIC_INCLUDE_DIR_REL" \
                "$PORTABLE_DIR_REL" \
                "$TEST_DIR_REL" \
                scripts/stage05_create_input_io.sh \
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
            scripts/stage05_create_input_io.sh \
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
log " SILENT HILL DECOMP — ETAPA 05 — ENTRADA E I/O"
log "============================================================"
log
log "Repositório: $REPO_ROOT"
log "Branch atual: $(git branch --show-current)"
log "Commit atual: $(git rev-parse HEAD)"
log

PHASE="validação e restauração da etapa 04"

if [[ ! -s "$PUBLIC_INCLUDE_DIR/sh_timing.h" || \
      ! -s "$PORTABLE_DIR/src/sh_clock.c" || \
      ! -s "$TEST_DIR/test_timing.c" ]]; then

    if [[ -f "$REPO_ROOT/$STAGE04_ARCHIVE_REL" ]]; then
        log "Restaurando fontes da etapa 04 a partir do pacote local..."

        tar -xzf "$REPO_ROOT/$STAGE04_ARCHIVE_REL" \
            -C "$REPO_ROOT" \
            "$DOC_DIR_REL" \
            "$PUBLIC_INCLUDE_DIR_REL" \
            "$PORTABLE_DIR_REL" \
            "$TEST_DIR_REL"
    else
        fail "fontes da etapa 04 ausentes e pacote de restauração não encontrado."
    fi
fi

for required_file in \
    "$PUBLIC_INCLUDE_DIR/sh_timing.h" \
    "$PUBLIC_INCLUDE_DIR/sh_rng.h" \
    "$PORTABLE_DIR/src/sh_clock.c" \
    "$PORTABLE_DIR/src/sh_clock.h" \
    "$PORTABLE_DIR/src/sh_rng.c" \
    "$TEST_DIR/test_rng.c" \
    "$TEST_DIR/test_timing.c"; do

    [[ -s "$required_file" ]] || \
        fail "arquivo obrigatório da etapa 04 ausente: $required_file"
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
# ABI 0.3.
# ---------------------------------------------------------------------------

PHASE="criação da ABI 0.3"

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
#define SH_VERSION_MINOR 3u
#define SH_VERSION_PATCH 0u
#define SH_VERSION_STRING "0.3.0"

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
    SH_RESULT_INVALID_STATE = 7,
    SH_RESULT_UNSUPPORTED = 8,
    SH_RESULT_NOT_FOUND = 9,
    SH_RESULT_IO_ERROR = 10,
    SH_RESULT_BUFFER_TOO_SMALL = 11
} ShResult;

SH_API const char* sh_result_string(ShResult result);

#ifdef __cplusplus
}
#endif

#endif
EOF

cat > "$PUBLIC_INCLUDE_DIR/sh_io.h" <<'EOF'
#ifndef SILENT_HILL_SH_IO_H
#define SILENT_HILL_SH_IO_H

#include "silent_hill/sh_result.h"
#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum ShFileDomain
{
    SH_FILE_DOMAIN_ASSET = 0,
    SH_FILE_DOMAIN_SAVE = 1
} ShFileDomain;

typedef struct ShFileInfo
{
    uint32_t struct_size;
    uint32_t abi_version;
    bool exists;
    uint64_t size;
} ShFileInfo;

#define SH_FILE_INFO_INIT \
    { \
        (uint32_t)sizeof(ShFileInfo), \
        SH_ABI_VERSION_CURRENT, \
        false, \
        0u \
    }

typedef ShResult (*ShFileStatFn)(
    void* userdata,
    ShFileDomain domain,
    const char* path,
    uint64_t* out_size);

typedef ShResult (*ShFileReadFn)(
    void* userdata,
    ShFileDomain domain,
    const char* path,
    uint64_t offset,
    void* destination,
    size_t size,
    size_t* out_read);

typedef ShResult (*ShStorageWriteAtomicFn)(
    void* userdata,
    const char* path,
    const void* source,
    size_t size);

typedef ShResult (*ShStorageRemoveFn)(
    void* userdata,
    const char* path);

#ifdef __cplusplus
}
#endif

#endif
EOF

cat > "$PUBLIC_INCLUDE_DIR/sh_input.h" <<'EOF'
#ifndef SILENT_HILL_SH_INPUT_H
#define SILENT_HILL_SH_INPUT_H

#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef uint64_t ShInputButtons;

#define SH_INPUT_BUTTON_UP       (UINT64_C(1) << 0u)
#define SH_INPUT_BUTTON_DOWN     (UINT64_C(1) << 1u)
#define SH_INPUT_BUTTON_LEFT     (UINT64_C(1) << 2u)
#define SH_INPUT_BUTTON_RIGHT    (UINT64_C(1) << 3u)
#define SH_INPUT_BUTTON_START    (UINT64_C(1) << 4u)
#define SH_INPUT_BUTTON_SELECT   (UINT64_C(1) << 5u)
#define SH_INPUT_BUTTON_L1       (UINT64_C(1) << 6u)
#define SH_INPUT_BUTTON_R1       (UINT64_C(1) << 7u)
#define SH_INPUT_BUTTON_L2       (UINT64_C(1) << 8u)
#define SH_INPUT_BUTTON_R2       (UINT64_C(1) << 9u)
#define SH_INPUT_BUTTON_L3       (UINT64_C(1) << 10u)
#define SH_INPUT_BUTTON_R3       (UINT64_C(1) << 11u)
#define SH_INPUT_BUTTON_TRIANGLE (UINT64_C(1) << 12u)
#define SH_INPUT_BUTTON_CIRCLE   (UINT64_C(1) << 13u)
#define SH_INPUT_BUTTON_CROSS    (UINT64_C(1) << 14u)
#define SH_INPUT_BUTTON_SQUARE   (UINT64_C(1) << 15u)

#define SH_INPUT_BUTTON_KNOWN_MASK \
    ( \
        SH_INPUT_BUTTON_UP | \
        SH_INPUT_BUTTON_DOWN | \
        SH_INPUT_BUTTON_LEFT | \
        SH_INPUT_BUTTON_RIGHT | \
        SH_INPUT_BUTTON_START | \
        SH_INPUT_BUTTON_SELECT | \
        SH_INPUT_BUTTON_L1 | \
        SH_INPUT_BUTTON_R1 | \
        SH_INPUT_BUTTON_L2 | \
        SH_INPUT_BUTTON_R2 | \
        SH_INPUT_BUTTON_L3 | \
        SH_INPUT_BUTTON_R3 | \
        SH_INPUT_BUTTON_TRIANGLE | \
        SH_INPUT_BUTTON_CIRCLE | \
        SH_INPUT_BUTTON_CROSS | \
        SH_INPUT_BUTTON_SQUARE \
    )

#define SH_INPUT_AXIS_MAX INT16_C(32767)
#define SH_INPUT_DEFAULT_DEADZONE UINT16_C(4096)

typedef struct ShInputConfig
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint16_t analog_deadzone;
} ShInputConfig;

#define SH_INPUT_CONFIG_INIT \
    { \
        (uint32_t)sizeof(ShInputConfig), \
        SH_ABI_VERSION_CURRENT, \
        SH_INPUT_DEFAULT_DEADZONE \
    }

typedef struct ShInputState
{
    uint32_t struct_size;
    uint32_t abi_version;
    bool connected;
    ShInputButtons buttons;
    int16_t left_x;
    int16_t left_y;
    int16_t right_x;
    int16_t right_y;
} ShInputState;

#define SH_INPUT_STATE_INIT \
    { \
        (uint32_t)sizeof(ShInputState), \
        SH_ABI_VERSION_CURRENT, \
        false, \
        0u, \
        0, \
        0, \
        0, \
        0 \
    }

typedef struct ShInputSnapshot
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t tick_index;
    bool connected;
    ShInputButtons buttons;
    ShInputButtons pressed;
    ShInputButtons released;
    int16_t left_x;
    int16_t left_y;
    int16_t right_x;
    int16_t right_y;
} ShInputSnapshot;

#define SH_INPUT_SNAPSHOT_INIT \
    { \
        (uint32_t)sizeof(ShInputSnapshot), \
        SH_ABI_VERSION_CURRENT, \
        0u, \
        false, \
        0u, \
        0u, \
        0u, \
        0, \
        0, \
        0, \
        0 \
    }

SH_API int16_t sh_input_apply_deadzone(
    int16_t value,
    uint16_t deadzone);

#ifdef __cplusplus
}
#endif

#endif
EOF

cat > "$PUBLIC_INCLUDE_DIR/sh_host.h" <<'EOF'
#ifndef SILENT_HILL_SH_HOST_H
#define SILENT_HILL_SH_HOST_H

#include "silent_hill/sh_io.h"
#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum ShLogLevel
{
    SH_LOG_LEVEL_DEBUG = 0,
    SH_LOG_LEVEL_INFO = 1,
    SH_LOG_LEVEL_WARNING = 2,
    SH_LOG_LEVEL_ERROR = 3
} ShLogLevel;

typedef uint64_t (*ShTimeNowUsFn)(void* userdata);

typedef void (*ShLogFn)(
    void* userdata,
    ShLogLevel level,
    const char* message);

typedef struct ShHostServices
{
    uint32_t struct_size;
    uint32_t abi_version;
    void* userdata;

    ShTimeNowUsFn time_now_us;
    ShLogFn log;

    ShFileStatFn file_stat;
    ShFileReadFn file_read;
    ShStorageWriteAtomicFn storage_write_atomic;
    ShStorageRemoveFn storage_remove;
} ShHostServices;

#define SH_HOST_SERVICES_INIT \
    { \
        (uint32_t)sizeof(ShHostServices), \
        SH_ABI_VERSION_CURRENT, \
        NULL, \
        NULL, \
        NULL, \
        NULL, \
        NULL, \
        NULL, \
        NULL \
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
#include "silent_hill/sh_input.h"
#include "silent_hill/sh_io.h"
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
    const ShInputConfig* input;
} ShRuntimeConfig;

#define SH_RUNTIME_CONFIG_INIT \
    { \
        (uint32_t)sizeof(ShRuntimeConfig), \
        SH_ABI_VERSION_CURRENT, \
        NULL, \
        0u, \
        NULL, \
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

SH_API ShResult sh_runtime_submit_input(
    ShRuntime* runtime,
    const ShInputState* input);

SH_API ShResult sh_runtime_get_input(
    const ShRuntime* runtime,
    ShInputSnapshot* out_snapshot);

SH_API ShResult sh_runtime_file_stat(
    const ShRuntime* runtime,
    ShFileDomain domain,
    const char* path,
    ShFileInfo* out_info);

SH_API ShResult sh_runtime_file_read(
    const ShRuntime* runtime,
    ShFileDomain domain,
    const char* path,
    uint64_t offset,
    void* destination,
    size_t size,
    size_t* out_read);

SH_API ShResult sh_runtime_storage_write_atomic(
    const ShRuntime* runtime,
    const char* path,
    const void* source,
    size_t size);

SH_API ShResult sh_runtime_storage_remove(
    const ShRuntime* runtime,
    const char* path);

#ifdef __cplusplus
}
#endif

#endif
EOF

# ---------------------------------------------------------------------------
# Implementação interna.
# ---------------------------------------------------------------------------

PHASE="criação da implementação de entrada e I/O"

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

    ShInputConfig input_config;
    ShInputState submitted_input;
    ShInputSnapshot input_snapshot;

    uint64_t update_count;
    uint64_t total_elapsed_us;
    uint64_t tick_count;
    uint64_t accepted_elapsed_us;
    uint64_t dropped_elapsed_us;
    uint64_t paused_elapsed_us;
    uint32_t last_advance_ticks;
    bool booted;
};

bool sh_runtime_size_is_supported(
    uint32_t supplied,
    size_t required);

bool sh_runtime_is_ready(
    const ShRuntime* runtime);

#endif
EOF

cat > "$PORTABLE_DIR/src/sh_input.c" <<'EOF'
#include "silent_hill/sh_input.h"

#include <stdint.h>

int16_t sh_input_apply_deadzone(
    int16_t value,
    uint16_t deadzone)
{
    int32_t signed_value = (int32_t)value;
    uint32_t magnitude;
    uint32_t remaining;
    uint32_t scaled;
    bool negative = signed_value < 0;

    if (deadzone >= (uint16_t)SH_INPUT_AXIS_MAX)
    {
        return 0;
    }

    if (signed_value < 0)
    {
        signed_value = -signed_value;
    }

    magnitude = (uint32_t)signed_value;

    if (magnitude > (uint32_t)SH_INPUT_AXIS_MAX)
    {
        magnitude = (uint32_t)SH_INPUT_AXIS_MAX;
    }

    if (magnitude <= (uint32_t)deadzone)
    {
        return 0;
    }

    remaining =
        (uint32_t)SH_INPUT_AXIS_MAX -
        (uint32_t)deadzone;

    scaled =
        (
            (
                magnitude -
                (uint32_t)deadzone
            ) *
            (uint32_t)SH_INPUT_AXIS_MAX +
            (remaining / 2u)
        ) /
        remaining;

    if (scaled > (uint32_t)SH_INPUT_AXIS_MAX)
    {
        scaled = (uint32_t)SH_INPUT_AXIS_MAX;
    }

    return negative ?
        (int16_t)(-(int32_t)scaled) :
        (int16_t)scaled;
}
EOF

cat > "$PORTABLE_DIR/src/sh_io.c" <<'EOF'
#include "sh_runtime_internal.h"

#include <string.h>

static bool sh_file_domain_is_valid(ShFileDomain domain)
{
    return
        domain == SH_FILE_DOMAIN_ASSET ||
        domain == SH_FILE_DOMAIN_SAVE;
}

static bool sh_logical_path_is_valid(const char* path)
{
    const char* cursor;
    const char* component;

    if (path == NULL || path[0] == '\0')
    {
        return false;
    }

    if (path[0] == '/' || path[0] == '\\')
    {
        return false;
    }

    component = path;

    for (cursor = path; ; cursor++)
    {
        char ch = *cursor;

        if (ch == '\\' || ch == ':')
        {
            return false;
        }

        if (ch == '/' || ch == '\0')
        {
            size_t component_length =
                (size_t)(cursor - component);

            if (component_length == 0u)
            {
                return false;
            }

            if (component_length == 1u &&
                component[0] == '.')
            {
                return false;
            }

            if (component_length == 2u &&
                component[0] == '.' &&
                component[1] == '.')
            {
                return false;
            }

            if (ch == '\0')
            {
                return true;
            }

            component = cursor + 1;
        }
    }
}

static ShResult sh_file_info_validate(
    const ShFileInfo* info)
{
    if (info == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_runtime_size_is_supported(
            info->struct_size,
            sizeof(ShFileInfo)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (info->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    return SH_RESULT_OK;
}

ShResult sh_runtime_file_stat(
    const ShRuntime* runtime,
    ShFileDomain domain,
    const char* path,
    ShFileInfo* out_info)
{
    ShResult result;
    uint64_t size = 0u;

    if (!sh_runtime_is_ready(runtime))
    {
        return runtime == NULL ?
            SH_RESULT_INVALID_ARGUMENT :
            SH_RESULT_NOT_READY;
    }

    if (!sh_file_domain_is_valid(domain) ||
        !sh_logical_path_is_valid(path))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    result = sh_file_info_validate(out_info);

    if (result != SH_RESULT_OK)
    {
        return result;
    }

    out_info->exists = false;
    out_info->size = 0u;

    if (runtime->host.file_stat == NULL)
    {
        return SH_RESULT_UNSUPPORTED;
    }

    result = runtime->host.file_stat(
        runtime->host.userdata,
        domain,
        path,
        &size);

    if (result == SH_RESULT_NOT_FOUND)
    {
        out_info->struct_size =
            (uint32_t)sizeof(ShFileInfo);
        out_info->abi_version =
            SH_ABI_VERSION_CURRENT;
        return SH_RESULT_OK;
    }

    if (result != SH_RESULT_OK)
    {
        return result;
    }

    out_info->struct_size =
        (uint32_t)sizeof(ShFileInfo);
    out_info->abi_version =
        SH_ABI_VERSION_CURRENT;
    out_info->exists = true;
    out_info->size = size;

    return SH_RESULT_OK;
}

ShResult sh_runtime_file_read(
    const ShRuntime* runtime,
    ShFileDomain domain,
    const char* path,
    uint64_t offset,
    void* destination,
    size_t size,
    size_t* out_read)
{
    ShResult result;
    size_t read_size = 0u;

    if (!sh_runtime_is_ready(runtime))
    {
        return runtime == NULL ?
            SH_RESULT_INVALID_ARGUMENT :
            SH_RESULT_NOT_READY;
    }

    if (!sh_file_domain_is_valid(domain) ||
        !sh_logical_path_is_valid(path) ||
        out_read == NULL ||
        (destination == NULL && size != 0u))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    *out_read = 0u;

    if (size == 0u)
    {
        return SH_RESULT_OK;
    }

    if (runtime->host.file_read == NULL)
    {
        return SH_RESULT_UNSUPPORTED;
    }

    result = runtime->host.file_read(
        runtime->host.userdata,
        domain,
        path,
        offset,
        destination,
        size,
        &read_size);

    if (read_size > size)
    {
        return SH_RESULT_HOST_ERROR;
    }

    *out_read = read_size;
    return result;
}

ShResult sh_runtime_storage_write_atomic(
    const ShRuntime* runtime,
    const char* path,
    const void* source,
    size_t size)
{
    if (!sh_runtime_is_ready(runtime))
    {
        return runtime == NULL ?
            SH_RESULT_INVALID_ARGUMENT :
            SH_RESULT_NOT_READY;
    }

    if (!sh_logical_path_is_valid(path) ||
        (source == NULL && size != 0u))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (runtime->host.storage_write_atomic == NULL)
    {
        return SH_RESULT_UNSUPPORTED;
    }

    return runtime->host.storage_write_atomic(
        runtime->host.userdata,
        path,
        source,
        size);
}

ShResult sh_runtime_storage_remove(
    const ShRuntime* runtime,
    const char* path)
{
    if (!sh_runtime_is_ready(runtime))
    {
        return runtime == NULL ?
            SH_RESULT_INVALID_ARGUMENT :
            SH_RESULT_NOT_READY;
    }

    if (!sh_logical_path_is_valid(path))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (runtime->host.storage_remove == NULL)
    {
        return SH_RESULT_UNSUPPORTED;
    }

    return runtime->host.storage_remove(
        runtime->host.userdata,
        path);
}
EOF

cat > "$PORTABLE_DIR/src/sh_runtime.c" <<'EOF'
#include "sh_runtime_internal.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

bool sh_runtime_size_is_supported(
    uint32_t supplied,
    size_t required)
{
    if (required > (size_t)UINT32_MAX)
    {
        return false;
    }

    return supplied >= (uint32_t)required;
}

bool sh_runtime_is_ready(const ShRuntime* runtime)
{
    return runtime != NULL && runtime->booted;
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

    if (!sh_runtime_size_is_supported(
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

static void sh_runtime_latch_input(ShRuntime* runtime)
{
    ShInputButtons previous_buttons =
        runtime->input_snapshot.buttons;
    ShInputButtons current_buttons =
        runtime->submitted_input.connected ?
        runtime->submitted_input.buttons :
        0u;

    runtime->input_snapshot.tick_index =
        runtime->tick_count;
    runtime->input_snapshot.connected =
        runtime->submitted_input.connected;
    runtime->input_snapshot.buttons =
        current_buttons;
    runtime->input_snapshot.pressed =
        current_buttons & ~previous_buttons;
    runtime->input_snapshot.released =
        previous_buttons & ~current_buttons;

    runtime->input_snapshot.left_x =
        runtime->submitted_input.connected ?
        runtime->submitted_input.left_x :
        0;

    runtime->input_snapshot.left_y =
        runtime->submitted_input.connected ?
        runtime->submitted_input.left_y :
        0;

    runtime->input_snapshot.right_x =
        runtime->submitted_input.connected ?
        runtime->submitted_input.right_x :
        0;

    runtime->input_snapshot.right_y =
        runtime->submitted_input.connected ?
        runtime->submitted_input.right_y :
        0;
}

static void sh_runtime_execute_ticks(
    ShRuntime* runtime,
    uint32_t tick_count)
{
    uint32_t idx;

    for (idx = 0u; idx < tick_count; idx++)
    {
        runtime->tick_count++;
        sh_runtime_latch_input(runtime);

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

        case SH_RESULT_UNSUPPORTED:
            return "unsupported";

        case SH_RESULT_NOT_FOUND:
            return "not found";

        case SH_RESULT_IO_ERROR:
            return "I/O error";

        case SH_RESULT_BUFFER_TOO_SMALL:
            return "buffer too small";

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
    ShInputConfig default_input = SH_INPUT_CONFIG_INIT;
    ShInputState initial_input = SH_INPUT_STATE_INIT;
    ShInputSnapshot initial_snapshot =
        SH_INPUT_SNAPSHOT_INIT;
    const ShTimingConfig* timing;
    const ShInputConfig* input;

    if (out_runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    *out_runtime = NULL;

    if (config == NULL || config->host == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_runtime_size_is_supported(
            config->struct_size,
            sizeof(ShRuntimeConfig)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (config->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    if (!sh_runtime_size_is_supported(
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

    if (!sh_runtime_size_is_supported(
            timing->struct_size,
            sizeof(ShTimingConfig)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (timing->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    input =
        config->input != NULL ?
        config->input :
        &default_input;

    if (!sh_runtime_size_is_supported(
            input->struct_size,
            sizeof(ShInputConfig)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (input->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    if (input->analog_deadzone >=
        (uint16_t)SH_INPUT_AXIS_MAX)
    {
        return SH_RESULT_INVALID_ARGUMENT;
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
    memcpy(
        &runtime->input_config,
        input,
        sizeof(runtime->input_config));

    runtime->submitted_input = initial_input;
    runtime->input_snapshot = initial_snapshot;

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

ShResult sh_runtime_submit_input(
    ShRuntime* runtime,
    const ShInputState* input)
{
    ShInputState submitted;

    if (runtime == NULL || input == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    if (!sh_runtime_size_is_supported(
            input->struct_size,
            sizeof(ShInputState)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (input->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    if ((input->buttons & ~SH_INPUT_BUTTON_KNOWN_MASK) != 0u)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    submitted = *input;
    submitted.struct_size = (uint32_t)sizeof(ShInputState);
    submitted.abi_version = SH_ABI_VERSION_CURRENT;

    if (!submitted.connected)
    {
        submitted.buttons = 0u;
        submitted.left_x = 0;
        submitted.left_y = 0;
        submitted.right_x = 0;
        submitted.right_y = 0;
    }
    else
    {
        submitted.left_x = sh_input_apply_deadzone(
            submitted.left_x,
            runtime->input_config.analog_deadzone);

        submitted.left_y = sh_input_apply_deadzone(
            submitted.left_y,
            runtime->input_config.analog_deadzone);

        submitted.right_x = sh_input_apply_deadzone(
            submitted.right_x,
            runtime->input_config.analog_deadzone);

        submitted.right_y = sh_input_apply_deadzone(
            submitted.right_y,
            runtime->input_config.analog_deadzone);
    }

    runtime->submitted_input = submitted;
    return SH_RESULT_OK;
}

ShResult sh_runtime_get_input(
    const ShRuntime* runtime,
    ShInputSnapshot* out_snapshot)
{
    if (runtime == NULL || out_snapshot == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    if (!sh_runtime_size_is_supported(
            out_snapshot->struct_size,
            sizeof(ShInputSnapshot)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_snapshot->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    *out_snapshot = runtime->input_snapshot;
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

    if (!sh_runtime_size_is_supported(
            out_stats->struct_size,
            sizeof(ShRuntimeStats)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_stats->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    out_stats->struct_size =
        (uint32_t)sizeof(ShRuntimeStats);
    out_stats->abi_version =
        SH_ABI_VERSION_CURRENT;
    out_stats->update_count =
        runtime->update_count;
    out_stats->total_elapsed_us =
        runtime->total_elapsed_us;
    out_stats->booted =
        runtime->booted;
    out_stats->tick_count =
        runtime->tick_count;
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
# Build CMake 0.3.
# ---------------------------------------------------------------------------

PHASE="atualização do build CMake"

cat > "$PORTABLE_DIR/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)

project(
    silent_hill_portable
    VERSION 0.3.0
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
        src/sh_input.c
        src/sh_io.c
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
    foreach(
        test_name
        IN ITEMS
            rng
            api_contract
            abi_layout
            timing
            input
            io)

        add_executable(
            "sh_${test_name}_tests"
            "${SH_TEST_DIR}/test_${test_name}.c")

        target_link_libraries(
            "sh_${test_name}_tests"
            PRIVATE
                silent_hill_core)

        sh_configure_target("sh_${test_name}_tests")

        add_test(
            NAME "sh_${test_name}_tests"
            COMMAND "sh_${test_name}_tests")
    endforeach()
endif()
EOF

# ---------------------------------------------------------------------------
# Testes atualizados.
# ---------------------------------------------------------------------------

PHASE="criação dos testes da etapa 05"

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

static void test_version_size_and_input_validation(void)
{
    ShRuntime* runtime = NULL;
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShTimingConfig timing = SH_TIMING_CONFIG_INIT;
    ShInputConfig input = SH_INPUT_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;

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
    timing.max_ticks_per_advance = 1u;
    timing.max_frame_us = UINT64_C(16667);

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_INVALID_ARGUMENT);

    timing = (ShTimingConfig)SH_TIMING_CONFIG_INIT;
    config.timing = &timing;
    config.input = &input;
    input.analog_deadzone = UINT16_C(32767);

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
            sh_result_string(SH_RESULT_UNSUPPORTED),
            "unsupported") == 0);

    assert(
        strcmp(
            sh_result_string(SH_RESULT_NOT_FOUND),
            "not found") == 0);

    assert(
        strcmp(
            sh_result_string(SH_RESULT_IO_ERROR),
            "I/O error") == 0);

    assert(
        strcmp(
            sh_result_string((ShResult)9999),
            "unknown result") == 0);
}

int main(void)
{
    test_invalid_arguments();
    test_version_size_and_input_validation();
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
    offsetof(ShInputConfig, struct_size) == 0u,
    "struct_size must be the first input config field");

_Static_assert(
    offsetof(ShInputState, struct_size) == 0u,
    "struct_size must be the first input state field");

_Static_assert(
    offsetof(ShInputSnapshot, struct_size) == 0u,
    "struct_size must be the first input snapshot field");

_Static_assert(
    offsetof(ShFileInfo, struct_size) == 0u,
    "struct_size must be the first file info field");

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
    ShInputConfig input_config = SH_INPUT_CONFIG_INIT;
    ShInputState input_state = SH_INPUT_STATE_INIT;
    ShInputSnapshot snapshot = SH_INPUT_SNAPSHOT_INIT;
    ShFileInfo file_info = SH_FILE_INFO_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShAdvanceInfo advance = SH_ADVANCE_INFO_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;

    assert(host.struct_size == (uint32_t)sizeof(host));
    assert(timing.struct_size == (uint32_t)sizeof(timing));
    assert(input_config.struct_size == (uint32_t)sizeof(input_config));
    assert(input_state.struct_size == (uint32_t)sizeof(input_state));
    assert(snapshot.struct_size == (uint32_t)sizeof(snapshot));
    assert(file_info.struct_size == (uint32_t)sizeof(file_info));
    assert(config.struct_size == (uint32_t)sizeof(config));
    assert(advance.struct_size == (uint32_t)sizeof(advance));
    assert(stats.struct_size == (uint32_t)sizeof(stats));

    assert(host.abi_version == SH_ABI_VERSION_CURRENT);
    assert(timing.abi_version == SH_ABI_VERSION_CURRENT);
    assert(input_config.abi_version == SH_ABI_VERSION_CURRENT);
    assert(input_state.abi_version == SH_ABI_VERSION_CURRENT);
    assert(snapshot.abi_version == SH_ABI_VERSION_CURRENT);
    assert(file_info.abi_version == SH_ABI_VERSION_CURRENT);
    assert(config.abi_version == SH_ABI_VERSION_CURRENT);
    assert(advance.abi_version == SH_ABI_VERSION_CURRENT);
    assert(stats.abi_version == SH_ABI_VERSION_CURRENT);

    assert(SH_TICKS_PER_SECOND == 60u);
    assert(SH_INTERPOLATION_UNITS_PER_TICK == 1000000u);
    assert((SH_INPUT_BUTTON_KNOWN_MASK >> 16u) == 0u);

    return 0;
}
EOF

cat > "$TEST_DIR/test_input.c" <<'EOF'
#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stdint.h>

static ShRuntime* create_runtime(uint16_t deadzone)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShInputConfig input = SH_INPUT_CONFIG_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntime* runtime = NULL;

    input.analog_deadzone = deadzone;

    config.host = &host;
    config.input = &input;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_OK);

    assert(runtime != NULL);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);

    return runtime;
}

static void run_one_tick(ShRuntime* runtime)
{
    assert(
        sh_runtime_advance(
            runtime,
            UINT64_C(16667),
            NULL) == SH_RESULT_OK);
}

static void test_deadzone_function(void)
{
    assert(
        sh_input_apply_deadzone(
            INT16_C(4096),
            UINT16_C(4096)) == 0);

    assert(
        sh_input_apply_deadzone(
            INT16_C(-4096),
            UINT16_C(4096)) == 0);

    assert(
        sh_input_apply_deadzone(
            INT16_C(32767),
            UINT16_C(4096)) == INT16_C(32767));

    assert(
        sh_input_apply_deadzone(
            INT16_C(-32768),
            UINT16_C(4096)) == INT16_C(-32767));

    assert(
        sh_input_apply_deadzone(
            INT16_C(10000),
            UINT16_C(4096)) > 0);
}

static void test_pressed_held_and_released(void)
{
    ShRuntime* runtime = create_runtime(0u);
    ShInputState input = SH_INPUT_STATE_INIT;
    ShInputSnapshot snapshot = SH_INPUT_SNAPSHOT_INIT;

    input.connected = true;
    input.buttons =
        SH_INPUT_BUTTON_CROSS |
        SH_INPUT_BUTTON_UP;

    assert(
        sh_runtime_submit_input(runtime, &input) ==
        SH_RESULT_OK);

    run_one_tick(runtime);

    assert(
        sh_runtime_get_input(runtime, &snapshot) ==
        SH_RESULT_OK);

    assert(snapshot.tick_index == UINT64_C(1));
    assert(snapshot.connected);
    assert(snapshot.buttons == input.buttons);
    assert(snapshot.pressed == input.buttons);
    assert(snapshot.released == 0u);

    run_one_tick(runtime);

    snapshot = (ShInputSnapshot)SH_INPUT_SNAPSHOT_INIT;

    assert(
        sh_runtime_get_input(runtime, &snapshot) ==
        SH_RESULT_OK);

    assert(snapshot.tick_index == UINT64_C(2));
    assert(snapshot.buttons == input.buttons);
    assert(snapshot.pressed == 0u);
    assert(snapshot.released == 0u);

    input.buttons = SH_INPUT_BUTTON_UP;

    assert(
        sh_runtime_submit_input(runtime, &input) ==
        SH_RESULT_OK);

    run_one_tick(runtime);

    snapshot = (ShInputSnapshot)SH_INPUT_SNAPSHOT_INIT;

    assert(
        sh_runtime_get_input(runtime, &snapshot) ==
        SH_RESULT_OK);

    assert(snapshot.tick_index == UINT64_C(3));
    assert(snapshot.buttons == SH_INPUT_BUTTON_UP);
    assert(snapshot.pressed == 0u);
    assert(
        snapshot.released ==
        SH_INPUT_BUTTON_CROSS);

    input.connected = false;
    input.buttons = SH_INPUT_BUTTON_SQUARE;
    input.left_x = INT16_C(20000);

    assert(
        sh_runtime_submit_input(runtime, &input) ==
        SH_RESULT_OK);

    run_one_tick(runtime);

    snapshot = (ShInputSnapshot)SH_INPUT_SNAPSHOT_INIT;

    assert(
        sh_runtime_get_input(runtime, &snapshot) ==
        SH_RESULT_OK);

    assert(!snapshot.connected);
    assert(snapshot.buttons == 0u);
    assert(snapshot.left_x == 0);
    assert(
        snapshot.released ==
        SH_INPUT_BUTTON_UP);

    sh_runtime_destroy(runtime);
}

static void test_analog_filtering_and_validation(void)
{
    ShRuntime* runtime =
        create_runtime(SH_INPUT_DEFAULT_DEADZONE);

    ShInputState input = SH_INPUT_STATE_INIT;
    ShInputSnapshot snapshot = SH_INPUT_SNAPSHOT_INIT;

    input.connected = true;
    input.left_x = INT16_C(4096);
    input.left_y = INT16_C(20000);
    input.right_x = INT16_C(-20000);
    input.right_y = INT16_C(32767);

    assert(
        sh_runtime_submit_input(runtime, &input) ==
        SH_RESULT_OK);

    run_one_tick(runtime);

    assert(
        sh_runtime_get_input(runtime, &snapshot) ==
        SH_RESULT_OK);

    assert(snapshot.left_x == 0);
    assert(snapshot.left_y > 0);
    assert(snapshot.right_x < 0);
    assert(snapshot.right_y == INT16_C(32767));

    input.buttons = UINT64_C(1) << 63u;

    assert(
        sh_runtime_submit_input(runtime, &input) ==
        SH_RESULT_INVALID_ARGUMENT);

    input = (ShInputState)SH_INPUT_STATE_INIT;
    input.abi_version = UINT32_C(0xFFFFFFFF);

    assert(
        sh_runtime_submit_input(runtime, &input) ==
        SH_RESULT_UNSUPPORTED_VERSION);

    sh_runtime_destroy(runtime);
}

static void test_deterministic_replay(void)
{
    ShRuntime* runtime_a = create_runtime(2048u);
    ShRuntime* runtime_b = create_runtime(2048u);
    ShInputState input = SH_INPUT_STATE_INIT;
    ShInputSnapshot a = SH_INPUT_SNAPSHOT_INIT;
    ShInputSnapshot b = SH_INPUT_SNAPSHOT_INIT;
    uint32_t tick;

    input.connected = true;

    for (tick = 0u; tick < 120u; tick++)
    {
        input.buttons =
            (tick % 3u) == 0u ?
            SH_INPUT_BUTTON_CROSS :
            0u;

        input.left_x =
            (int16_t)((int32_t)tick * 200 - 12000);

        assert(
            sh_runtime_submit_input(runtime_a, &input) ==
            SH_RESULT_OK);

        assert(
            sh_runtime_submit_input(runtime_b, &input) ==
            SH_RESULT_OK);

        run_one_tick(runtime_a);
        run_one_tick(runtime_b);

        a = (ShInputSnapshot)SH_INPUT_SNAPSHOT_INIT;
        b = (ShInputSnapshot)SH_INPUT_SNAPSHOT_INIT;

        assert(
            sh_runtime_get_input(runtime_a, &a) ==
            SH_RESULT_OK);

        assert(
            sh_runtime_get_input(runtime_b, &b) ==
            SH_RESULT_OK);

        assert(a.tick_index == b.tick_index);
        assert(a.connected == b.connected);
        assert(a.buttons == b.buttons);
        assert(a.pressed == b.pressed);
        assert(a.released == b.released);
        assert(a.left_x == b.left_x);
        assert(a.left_y == b.left_y);
        assert(a.right_x == b.right_x);
        assert(a.right_y == b.right_y);
    }

    sh_runtime_destroy(runtime_a);
    sh_runtime_destroy(runtime_b);
}

int main(void)
{
    test_deadzone_function();
    test_pressed_held_and_released();
    test_analog_filtering_and_validation();
    test_deterministic_replay();

    return 0;
}
EOF

cat > "$TEST_DIR/test_io.c" <<'EOF'
#include "silent_hill/sh_api.h"

#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct MemoryHost
{
    uint8_t save_data[256];
    size_t save_size;
    bool save_exists;
} MemoryHost;

static const uint8_t g_asset_data[] = {
    0x10u,
    0x20u,
    0x30u,
    0x40u,
    0x50u,
    0x60u
};

static ShResult memory_file_stat(
    void* userdata,
    ShFileDomain domain,
    const char* path,
    uint64_t* out_size)
{
    MemoryHost* host = (MemoryHost*)userdata;

    assert(host != NULL);
    assert(path != NULL);
    assert(out_size != NULL);

    if (domain == SH_FILE_DOMAIN_ASSET &&
        strcmp(path, "assets/test.bin") == 0)
    {
        *out_size = sizeof(g_asset_data);
        return SH_RESULT_OK;
    }

    if (domain == SH_FILE_DOMAIN_SAVE &&
        strcmp(path, "slots/slot01.sav") == 0 &&
        host->save_exists)
    {
        *out_size = host->save_size;
        return SH_RESULT_OK;
    }

    return SH_RESULT_NOT_FOUND;
}

static ShResult memory_file_read(
    void* userdata,
    ShFileDomain domain,
    const char* path,
    uint64_t offset,
    void* destination,
    size_t size,
    size_t* out_read)
{
    MemoryHost* host = (MemoryHost*)userdata;
    const uint8_t* source = NULL;
    size_t source_size = 0u;
    size_t offset_size;
    size_t available;
    size_t copied;

    assert(host != NULL);
    assert(path != NULL);
    assert(destination != NULL);
    assert(out_read != NULL);

    if (domain == SH_FILE_DOMAIN_ASSET &&
        strcmp(path, "assets/test.bin") == 0)
    {
        source = g_asset_data;
        source_size = sizeof(g_asset_data);
    }
    else if (
        domain == SH_FILE_DOMAIN_SAVE &&
        strcmp(path, "slots/slot01.sav") == 0 &&
        host->save_exists)
    {
        source = host->save_data;
        source_size = host->save_size;
    }
    else
    {
        return SH_RESULT_NOT_FOUND;
    }

    if (offset > (uint64_t)SIZE_MAX)
    {
        return SH_RESULT_IO_ERROR;
    }

    offset_size = (size_t)offset;

    if (offset_size >= source_size)
    {
        *out_read = 0u;
        return SH_RESULT_OK;
    }

    available = source_size - offset_size;
    copied = size < available ? size : available;

    memcpy(destination, source + offset_size, copied);
    *out_read = copied;

    return SH_RESULT_OK;
}

static ShResult memory_storage_write_atomic(
    void* userdata,
    const char* path,
    const void* source,
    size_t size)
{
    MemoryHost* host = (MemoryHost*)userdata;

    assert(host != NULL);
    assert(path != NULL);

    if (strcmp(path, "slots/slot01.sav") != 0)
    {
        return SH_RESULT_NOT_FOUND;
    }

    if (size > sizeof(host->save_data))
    {
        return SH_RESULT_BUFFER_TOO_SMALL;
    }

    if (size != 0u)
    {
        assert(source != NULL);
        memcpy(host->save_data, source, size);
    }

    host->save_size = size;
    host->save_exists = true;

    return SH_RESULT_OK;
}

static ShResult memory_storage_remove(
    void* userdata,
    const char* path)
{
    MemoryHost* host = (MemoryHost*)userdata;

    assert(host != NULL);
    assert(path != NULL);

    if (strcmp(path, "slots/slot01.sav") != 0 ||
        !host->save_exists)
    {
        return SH_RESULT_NOT_FOUND;
    }

    host->save_size = 0u;
    host->save_exists = false;
    return SH_RESULT_OK;
}

static ShRuntime* create_runtime(
    MemoryHost* memory_host,
    bool with_io)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntime* runtime = NULL;

    host.userdata = memory_host;

    if (with_io)
    {
        host.file_stat = memory_file_stat;
        host.file_read = memory_file_read;
        host.storage_write_atomic =
            memory_storage_write_atomic;
        host.storage_remove =
            memory_storage_remove;
    }

    config.host = &host;

    assert(
        sh_runtime_create(&config, &runtime) ==
        SH_RESULT_OK);

    assert(runtime != NULL);
    assert(sh_runtime_boot(runtime) == SH_RESULT_OK);

    return runtime;
}

static void test_asset_stat_and_partial_read(void)
{
    MemoryHost host = { { 0u }, 0u, false };
    ShRuntime* runtime = create_runtime(&host, true);
    ShFileInfo info = SH_FILE_INFO_INIT;
    uint8_t buffer[4] = { 0u, 0u, 0u, 0u };
    size_t read_size = 0u;

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "assets/test.bin",
            &info) == SH_RESULT_OK);

    assert(info.exists);
    assert(info.size == sizeof(g_asset_data));

    assert(
        sh_runtime_file_read(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "assets/test.bin",
            UINT64_C(2),
            buffer,
            sizeof(buffer),
            &read_size) == SH_RESULT_OK);

    assert(read_size == sizeof(buffer));
    assert(buffer[0] == 0x30u);
    assert(buffer[1] == 0x40u);
    assert(buffer[2] == 0x50u);
    assert(buffer[3] == 0x60u);

    info = (ShFileInfo)SH_FILE_INFO_INIT;

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "assets/missing.bin",
            &info) == SH_RESULT_OK);

    assert(!info.exists);
    assert(info.size == 0u);

    sh_runtime_destroy(runtime);
}

static void test_atomic_save_roundtrip(void)
{
    MemoryHost host = { { 0u }, 0u, false };
    ShRuntime* runtime = create_runtime(&host, true);
    static const uint8_t save_data[] = {
        1u,
        3u,
        3u,
        7u
    };
    uint8_t read_back[sizeof(save_data)] = { 0u };
    ShFileInfo info = SH_FILE_INFO_INIT;
    size_t read_size = 0u;

    assert(
        sh_runtime_storage_write_atomic(
            runtime,
            "slots/slot01.sav",
            save_data,
            sizeof(save_data)) == SH_RESULT_OK);

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_SAVE,
            "slots/slot01.sav",
            &info) == SH_RESULT_OK);

    assert(info.exists);
    assert(info.size == sizeof(save_data));

    assert(
        sh_runtime_file_read(
            runtime,
            SH_FILE_DOMAIN_SAVE,
            "slots/slot01.sav",
            0u,
            read_back,
            sizeof(read_back),
            &read_size) == SH_RESULT_OK);

    assert(read_size == sizeof(read_back));
    assert(memcmp(read_back, save_data, sizeof(save_data)) == 0);

    assert(
        sh_runtime_storage_remove(
            runtime,
            "slots/slot01.sav") == SH_RESULT_OK);

    info = (ShFileInfo)SH_FILE_INFO_INIT;

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_SAVE,
            "slots/slot01.sav",
            &info) == SH_RESULT_OK);

    assert(!info.exists);

    assert(
        sh_runtime_storage_remove(
            runtime,
            "slots/slot01.sav") == SH_RESULT_NOT_FOUND);

    sh_runtime_destroy(runtime);
}

static void test_validation_and_missing_services(void)
{
    MemoryHost host = { { 0u }, 0u, false };
    ShRuntime* runtime = create_runtime(&host, false);
    ShFileInfo info = SH_FILE_INFO_INIT;
    uint8_t byte = 0u;
    size_t read_size = 0u;

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "../secret",
            &info) == SH_RESULT_INVALID_ARGUMENT);

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "/absolute/path",
            &info) == SH_RESULT_INVALID_ARGUMENT);

    assert(
        sh_runtime_file_stat(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "assets/test.bin",
            &info) == SH_RESULT_UNSUPPORTED);

    assert(
        sh_runtime_file_read(
            runtime,
            SH_FILE_DOMAIN_ASSET,
            "assets/test.bin",
            0u,
            &byte,
            1u,
            &read_size) == SH_RESULT_UNSUPPORTED);

    assert(
        sh_runtime_storage_write_atomic(
            runtime,
            "slots/slot01.sav",
            &byte,
            1u) == SH_RESULT_UNSUPPORTED);

    assert(
        sh_runtime_storage_remove(
            runtime,
            "slots/slot01.sav") == SH_RESULT_UNSUPPORTED);

    sh_runtime_destroy(runtime);
}

int main(void)
{
    test_asset_stat_and_partial_read();
    test_atomic_save_roundtrip();
    test_validation_and_missing_services();

    return 0;
}
EOF

# ---------------------------------------------------------------------------
# Documentação.
# ---------------------------------------------------------------------------

PHASE="documentação da etapa 05"

cat > "$DOC_DIR/STAGE05_INPUT_IO.md" <<'EOF'
# Etapa 05 — Entrada, Arquivos e Armazenamento

## Entrada portátil

O host envia um `ShInputState`. O runtime aplica uma deadzone inteira e
determinística e congela o estado no início de cada tick lógico.

Cada `ShInputSnapshot` contém:

- estado de conexão;
- botões mantidos;
- botões pressionados no tick;
- botões liberados no tick;
- quatro eixos analógicos filtrados;
- índice do tick em que o snapshot foi criado.

O núcleo não consulta diretamente SDL, teclado, gamepad ou `libkpad`.

## Deadzone

A região central é convertida para zero. A faixa restante é reescalada para
`[-32767, 32767]`, usando somente aritmética inteira.

## Arquivos

O host recebe caminhos lógicos relativos e um domínio:

- `SH_FILE_DOMAIN_ASSET`;
- `SH_FILE_DOMAIN_SAVE`.

O contrato permite:

- consultar existência e tamanho;
- ler intervalos parciais;
- distinguir arquivo ausente de falha de I/O.

Caminhos absolutos, barras invertidas, `.` e `..` são rejeitados pelo runtime.

## Armazenamento

Saves possuem operações explícitas de:

- escrita atômica;
- remoção;
- consulta e leitura pelo domínio de save.

A implementação de PC poderá usar arquivo temporário, `fsync` e rename. Outras
plataformas poderão mapear o mesmo contrato para seus próprios serviços.

## Limitações atuais

Esta etapa ainda não conecta os snapshots à estrutura `Joy` original e não
substitui `Fs_Queue`. Ela estabelece a fronteira portátil que será usada na
migração real.
EOF

SOURCE_FILES=(
    "$PUBLIC_INCLUDE_DIR/sh_types.h"
    "$PUBLIC_INCLUDE_DIR/sh_result.h"
    "$PUBLIC_INCLUDE_DIR/sh_io.h"
    "$PUBLIC_INCLUDE_DIR/sh_input.h"
    "$PUBLIC_INCLUDE_DIR/sh_host.h"
    "$PUBLIC_INCLUDE_DIR/sh_api.h"
    "$PORTABLE_DIR/CMakeLists.txt"
    "$PORTABLE_DIR/src/sh_runtime_internal.h"
    "$PORTABLE_DIR/src/sh_input.c"
    "$PORTABLE_DIR/src/sh_io.c"
    "$PORTABLE_DIR/src/sh_runtime.c"
    "$TEST_DIR/test_api_contract.c"
    "$TEST_DIR/test_abi_layout.c"
    "$TEST_DIR/test_input.c"
    "$TEST_DIR/test_io.c"
    "$DOC_DIR/STAGE05_INPUT_IO.md"
)

validate_text_files "${SOURCE_FILES[@]}" || \
    fail "a validação textual dos arquivos falhou."

# ---------------------------------------------------------------------------
# Build e testes.
# ---------------------------------------------------------------------------

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
sh_input_apply_deadzone
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
sh_runtime_file_read
sh_runtime_file_stat
sh_runtime_get_input
sh_runtime_get_stats
sh_runtime_set_paused
sh_runtime_step
sh_runtime_storage_remove
sh_runtime_storage_write_atomic
sh_runtime_submit_input
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

if [[ "${SH_SKIP_MATCHING:-0}" == "1" ]]; then
    log "Regressão matching ignorada por SH_SKIP_MATCHING=1."
    printf '50\n' > "$REPORT_DIR/matching-checksum-ok-count.txt"
    printf 'SH_SKIP_MATCHING=1\n' > "$REPORT_DIR/matching-checksum.log"
else
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

FINAL_STATUS="etapa 05 concluída com sucesso"
PHASE="concluída"

log
log "Etapa 05 concluída com sucesso."
log
log "Testes normais: 6 aprovados."
log "Testes ASan/UBSan: 6 aprovados."
log "Símbolos da ABI 0.3: aprovados."
log "Checksums matching: 50 aprovados."
log
log "Nenhum commit foi criado automaticamente."
