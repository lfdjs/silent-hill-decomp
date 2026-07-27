#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

REPO="${REPO:-$HOME/Documentos/projetos_decompilacao/silent-hill-decomp}"
TARGET_BRANCH="portability/core-api"

BUILD_DIR_REL="build-portable-stage03"
SANITIZER_BUILD_DIR_REL="build-portable-stage03-sanitizers"
REPORT_DIR_REL="stage03-portable-core-report"
PACKAGE_REL="stage03-portable-core-report.tar.gz"

DOC_DIR_REL="docs/portability"
PUBLIC_INCLUDE_DIR_REL="include/silent_hill"
PORTABLE_DIR_REL="portable"
TEST_DIR_REL="tests/portable"

BASELINE_DIR_REL="stage01-build-baseline"
BASELINE_ARCHIVE_REL="stage01-build-baseline.tar.gz"
STAGE02_ARCHIVE_REL="stage02-architecture-report.tar.gz"

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
        scripts/stage03_create_portable_core.sh)
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

        printf '%s\0' scripts/stage03_create_portable_core.sh
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
        PHASE="${PHASE:-desconhecida}"

        {
            echo "SILENT HILL DECOMP — ETAPA 03"
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
            echo "- headers públicos da ABI C;"
            echo "- runtime portátil mínimo;"
            echo "- RNG determinístico;"
            echo "- testes nativos;"
            echo "- documentação de portabilidade;"
            echo "- logs e relatórios da etapa 03;"
            echo "- script persistente da etapa."
            echo
            echo "Não contém ROM, BIOS, executáveis do jogo ou assets extraídos."
            echo "Os binários temporários do CMake não foram incluídos."
        } > "$REPORT_DIR/CONTENTS.txt"

        {
            echo "Git status completo:"
            git status --short --branch 2>/dev/null || true
            echo
            echo "Arquivos alterados ou não rastreados no escopo:"
            git status \
                --short \
                --untracked-files=all \
                -- \
                "$DOC_DIR_REL" \
                "$PUBLIC_INCLUDE_DIR_REL" \
                "$PORTABLE_DIR_REL" \
                "$TEST_DIR_REL" \
                scripts/stage03_create_portable_core.sh \
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
            scripts/stage03_create_portable_core.sh \
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
log " SILENT HILL DECOMP — ETAPA 03 — NÚCLEO PORTÁTIL"
log "============================================================"
log
log "Repositório: $REPO_ROOT"
log "Branch atual: $(git branch --show-current)"
log "Commit atual: $(git rev-parse HEAD)"
log

PHASE="validação da etapa 02"

if [[ ! -s "$DOC_DIR/ARCHITECTURE.md" ]]; then
    if [[ -f "$REPO_ROOT/$STAGE02_ARCHIVE_REL" ]]; then
        log "Restaurando documentação da etapa 02 a partir do pacote local..."

        tar -xzf "$REPO_ROOT/$STAGE02_ARCHIVE_REL" \
            -C "$REPO_ROOT" \
            "$DOC_DIR_REL"
    else
        fail "documentação da etapa 02 não encontrada."
    fi
fi

for required_doc in \
    README.md \
    ARCHITECTURE.md \
    ABI_DRAFT.md \
    DECISIONS.md \
    MIGRATION_MATRIX.tsv \
    ROADMAP.md; do

    [[ -s "$DOC_DIR/$required_doc" ]] || \
        fail "documento obrigatório ausente: $DOC_DIR/$required_doc"
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
    "$TEST_DIR"

# ---------------------------------------------------------------------------
# Headers públicos.
# ---------------------------------------------------------------------------

PHASE="criação da ABI pública"

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
#define SH_VERSION_MINOR 1u
#define SH_VERSION_PATCH 0u
#define SH_VERSION_STRING "0.1.0"

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
    SH_RESULT_OVERFLOW = 6
} ShResult;

SH_API const char* sh_result_string(ShResult result);

#ifdef __cplusplus
}
#endif

#endif
EOF

cat > "$PUBLIC_INCLUDE_DIR/sh_host.h" <<'EOF'
#ifndef SILENT_HILL_SH_HOST_H
#define SILENT_HILL_SH_HOST_H

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

typedef bool (*ShFileReadFn)(
    void* userdata,
    const char* path,
    uint64_t offset,
    void* destination,
    size_t size);

typedef struct ShHostServices
{
    uint32_t struct_size;
    uint32_t abi_version;
    void* userdata;

    ShTimeNowUsFn time_now_us;
    ShLogFn log;
    ShFileReadFn file_read;
} ShHostServices;

#define SH_HOST_SERVICES_INIT \
    { \
        (uint32_t)sizeof(ShHostServices), \
        SH_ABI_VERSION_CURRENT, \
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

cat > "$PUBLIC_INCLUDE_DIR/sh_rng.h" <<'EOF'
#ifndef SILENT_HILL_SH_RNG_H
#define SILENT_HILL_SH_RNG_H

#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ShRng
{
    uint32_t seed;
} ShRng;

SH_API void sh_rng_init(ShRng* rng, uint32_t seed);
SH_API uint32_t sh_rng_get_seed(const ShRng* rng);
SH_API void sh_rng_set_seed(ShRng* rng, uint32_t seed);
SH_API uint32_t sh_rng_next_u32(ShRng* rng);
SH_API uint16_t sh_rng_next_u15(ShRng* rng);
SH_API uint16_t sh_rng_next_u12(ShRng* rng);

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
} ShRuntimeConfig;

#define SH_RUNTIME_CONFIG_INIT \
    { \
        (uint32_t)sizeof(ShRuntimeConfig), \
        SH_ABI_VERSION_CURRENT, \
        NULL, \
        0u \
    }

typedef struct ShRuntimeStats
{
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t update_count;
    uint64_t total_elapsed_us;
    bool booted;
} ShRuntimeStats;

#define SH_RUNTIME_STATS_INIT \
    { \
        (uint32_t)sizeof(ShRuntimeStats), \
        SH_ABI_VERSION_CURRENT, \
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

SH_API ShResult sh_runtime_update(
    ShRuntime* runtime,
    uint64_t elapsed_us);

SH_API ShResult sh_runtime_get_stats(
    const ShRuntime* runtime,
    ShRuntimeStats* out_stats);

#ifdef __cplusplus
}
#endif

#endif
EOF

# ---------------------------------------------------------------------------
# Implementação.
# ---------------------------------------------------------------------------

PHASE="criação do runtime portátil"

cat > "$PORTABLE_DIR/src/sh_runtime_internal.h" <<'EOF'
#ifndef SILENT_HILL_SH_RUNTIME_INTERNAL_H
#define SILENT_HILL_SH_RUNTIME_INTERNAL_H

#include "silent_hill/sh_api.h"

struct ShRuntime
{
    ShHostServices host;
    ShRng rng;
    uint64_t update_count;
    uint64_t total_elapsed_us;
    bool booted;
};

#endif
EOF

cat > "$PORTABLE_DIR/src/sh_rng.c" <<'EOF'
#include "silent_hill/sh_rng.h"

void sh_rng_init(ShRng* rng, uint32_t seed)
{
    if (rng != NULL)
    {
        rng->seed = seed;
    }
}

uint32_t sh_rng_get_seed(const ShRng* rng)
{
    return rng != NULL ? rng->seed : 0u;
}

void sh_rng_set_seed(ShRng* rng, uint32_t seed)
{
    if (rng != NULL)
    {
        rng->seed = seed;
    }
}

uint32_t sh_rng_next_u32(ShRng* rng)
{
    if (rng == NULL)
    {
        return 0u;
    }

    rng->seed =
        (rng->seed * UINT32_C(1664525)) +
        UINT32_C(1013904223);

    return rng->seed;
}

uint16_t sh_rng_next_u15(ShRng* rng)
{
    return (uint16_t)(sh_rng_next_u32(rng) >> 17u);
}

uint16_t sh_rng_next_u12(ShRng* rng)
{
    return (uint16_t)(sh_rng_next_u32(rng) >> 20u);
}
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

        default:
            return "unknown result";
    }
}

ShResult sh_runtime_create(
    const ShRuntimeConfig* config,
    ShRuntime** out_runtime)
{
    ShRuntime* runtime;

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

    runtime = (ShRuntime*)calloc(1u, sizeof(*runtime));

    if (runtime == NULL)
    {
        return SH_RESULT_OUT_OF_MEMORY;
    }

    memcpy(&runtime->host, config->host, sizeof(runtime->host));
    sh_rng_init(&runtime->rng, config->initial_rng_seed);

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

ShResult sh_runtime_update(
    ShRuntime* runtime,
    uint64_t elapsed_us)
{
    if (runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!runtime->booted)
    {
        return SH_RESULT_NOT_READY;
    }

    if (UINT64_MAX - runtime->total_elapsed_us < elapsed_us)
    {
        return SH_RESULT_OVERFLOW;
    }

    if (runtime->update_count == UINT64_MAX)
    {
        return SH_RESULT_OVERFLOW;
    }

    runtime->total_elapsed_us += elapsed_us;
    runtime->update_count++;

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

    return SH_RESULT_OK;
}
EOF

# ---------------------------------------------------------------------------
# CMake independente.
# ---------------------------------------------------------------------------

PHASE="criação do build CMake"

cat > "$PORTABLE_DIR/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)

project(
    silent_hill_portable
    VERSION 0.1.0
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
        src/sh_rng.c
        src/sh_runtime.c)

set_target_properties(
    silent_hill_core_objects
    PROPERTIES
        POSITION_INDEPENDENT_CODE ON)

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
        SOVERSION "${PROJECT_VERSION_MAJOR}")

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
endif()
EOF

# ---------------------------------------------------------------------------
# Testes.
# ---------------------------------------------------------------------------

PHASE="criação dos testes"

cat > "$TEST_DIR/test_rng.c" <<'EOF'
#include "silent_hill/sh_rng.h"

#include <assert.h>
#include <stdint.h>

static void test_reference_sequence_from_zero(void)
{
    static const uint32_t expected[] = {
        UINT32_C(0x3C6EF35F),
        UINT32_C(0x47502932),
        UINT32_C(0xD1CCF6E9),
        UINT32_C(0xAAF95334),
        UINT32_C(0x6252E503)
    };

    ShRng rng;
    size_t idx;

    sh_rng_init(&rng, 0u);

    for (idx = 0u; idx < (sizeof(expected) / sizeof(expected[0])); idx++)
    {
        assert(sh_rng_next_u32(&rng) == expected[idx]);
    }

    assert(sh_rng_get_seed(&rng) == expected[4]);
}

static void test_reference_sequence_from_known_seed(void)
{
    static const uint32_t expected[] = {
        UINT32_C(0x75432777),
        UINT32_C(0xCD305E6A),
        UINT32_C(0x25DBFAC1),
        UINT32_C(0x4B5C952C),
        UINT32_C(0x84DE0E9B)
    };

    ShRng rng;
    size_t idx;

    sh_rng_init(&rng, UINT32_C(0x12345678));

    for (idx = 0u; idx < (sizeof(expected) / sizeof(expected[0])); idx++)
    {
        assert(sh_rng_next_u32(&rng) == expected[idx]);
    }
}

static void test_original_width_helpers(void)
{
    ShRng rng;

    sh_rng_init(&rng, 0u);
    assert(sh_rng_next_u15(&rng) == UINT16_C(7735));

    sh_rng_init(&rng, 0u);
    assert(sh_rng_next_u12(&rng) == UINT16_C(966));
}

static void test_null_safety(void)
{
    sh_rng_init(NULL, 1u);
    sh_rng_set_seed(NULL, 2u);

    assert(sh_rng_get_seed(NULL) == 0u);
    assert(sh_rng_next_u32(NULL) == 0u);
    assert(sh_rng_next_u15(NULL) == 0u);
    assert(sh_rng_next_u12(NULL) == 0u);
}

int main(void)
{
    test_reference_sequence_from_zero();
    test_reference_sequence_from_known_seed();
    test_original_width_helpers();
    test_null_safety();

    return 0;
}
EOF

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

static void test_version_and_size_validation(void)
{
    ShRuntime* runtime = NULL;
    ShHostServices host = SH_HOST_SERVICES_INIT;
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
    assert(stats.booted);

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
            sh_result_string((ShResult)9999),
            "unknown result") == 0);
}

int main(void)
{
    test_invalid_arguments();
    test_version_and_size_validation();
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
    offsetof(ShRuntimeConfig, struct_size) == 0u,
    "struct_size must be the first config field");

_Static_assert(
    offsetof(ShRuntimeConfig, abi_version) == sizeof(uint32_t),
    "abi_version must follow struct_size");

_Static_assert(
    offsetof(ShRuntimeStats, struct_size) == 0u,
    "struct_size must be the first stats field");

_Static_assert(
    sizeof(ShRng) == sizeof(uint32_t),
    "ShRng must contain exactly one 32-bit seed");

int main(void)
{
    ShHostServices host = SH_HOST_SERVICES_INIT;
    ShRuntimeConfig config = SH_RUNTIME_CONFIG_INIT;
    ShRuntimeStats stats = SH_RUNTIME_STATS_INIT;

    assert(host.struct_size == (uint32_t)sizeof(host));
    assert(config.struct_size == (uint32_t)sizeof(config));
    assert(stats.struct_size == (uint32_t)sizeof(stats));

    assert(host.abi_version == SH_ABI_VERSION_CURRENT);
    assert(config.abi_version == SH_ABI_VERSION_CURRENT);
    assert(stats.abi_version == SH_ABI_VERSION_CURRENT);

    return 0;
}
EOF

# ---------------------------------------------------------------------------
# Documento da implementação.
# ---------------------------------------------------------------------------

PHASE="documentação do corte vertical"

cat > "$DOC_DIR/STAGE03_NATIVE_SLICE.md" <<'EOF'
# Etapa 03 — Primeiro Corte Nativo

## Conteúdo

A etapa 03 cria o primeiro código portátil compilável do projeto:

- ABI C versão 0.1;
- `ShRuntime` opaco;
- tabela de serviços fornecidos pelo host;
- lifecycle mínimo;
- estatísticas versionadas;
- módulo RNG determinístico;
- biblioteca estática;
- biblioteca compartilhada;
- testes de RNG, API e layout da ABI.

## Relação com o jogo original

O algoritmo de RNG preserva as operações de `src/main/rng.c`:

```text
seed = seed * 1664525 + 1013904223
```

A aritmética usa `uint32_t`, preservando o wraparound definido de 32 bits.

## Limitações atuais

Este corte ainda não:

- executa `MainLoop`;
- carrega overlays;
- acessa arquivos do jogo;
- produz vídeo;
- produz áudio;
- substitui qualquer chamada Psy-Q.

## Build

```bash
cmake \
    -S portable \
    -B build-portable-stage03 \
    -DCMAKE_BUILD_TYPE=Debug \
    -DSH_ENABLE_WERROR=ON

cmake --build build-portable-stage03 --parallel
ctest --test-dir build-portable-stage03 --output-on-failure
```
EOF

SOURCE_FILES=(
    "$PUBLIC_INCLUDE_DIR/sh_types.h"
    "$PUBLIC_INCLUDE_DIR/sh_result.h"
    "$PUBLIC_INCLUDE_DIR/sh_host.h"
    "$PUBLIC_INCLUDE_DIR/sh_rng.h"
    "$PUBLIC_INCLUDE_DIR/sh_api.h"
    "$PORTABLE_DIR/CMakeLists.txt"
    "$PORTABLE_DIR/src/sh_runtime_internal.h"
    "$PORTABLE_DIR/src/sh_rng.c"
    "$PORTABLE_DIR/src/sh_runtime.c"
    "$TEST_DIR/test_rng.c"
    "$TEST_DIR/test_api_contract.c"
    "$TEST_DIR/test_abi_layout.c"
    "$DOC_DIR/STAGE03_NATIVE_SLICE.md"
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
sh_runtime_boot
sh_runtime_create
sh_runtime_destroy
sh_runtime_get_stats
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

FINAL_STATUS="etapa 03 concluída com sucesso"
PHASE="concluída"

log
log "Etapa 03 concluída com sucesso."
log
log "Testes normais: aprovados."
log "Testes ASan/UBSan: aprovados."
log "Símbolos da ABI: aprovados."
log "Checksums matching: 50 aprovados."
log
log "Nenhum commit foi criado automaticamente."
