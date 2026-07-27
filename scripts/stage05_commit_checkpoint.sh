#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

REPO="${REPO:-$HOME/Documentos/projetos_decompilacao/silent-hill-decomp}"
TARGET_BRANCH="portability/core-api"

STAGE05_REPORT_DIR_REL="stage05-input-io-report"
STAGE05_ARCHIVE_REL="stage05-input-io-report.tar.gz"

BUILD_DIR_REL="build-portable-stage05"
SANITIZER_BUILD_DIR_REL="build-portable-stage05-sanitizers"

CHECKPOINT_REPORT_DIR_REL="stage05-commit-checkpoint-report"
CHECKPOINT_ARCHIVE_REL="stage05-commit-checkpoint-report.tar.gz"
CHECKPOINT_PATCH_REL="stage05-portable-checkpoint.patch"

COMMIT_SUBJECT="${COMMIT_SUBJECT:-feat(portable): establish ABI 0.3 runtime checkpoint}"

TEMP_DIR=""
REPORT_ACTIVE=0
PHASE="inicialização"
FINAL_STATUS="falha"
COMMIT_CREATED=0
PREVIOUS_HEAD=""
CHECKPOINT_COMMIT=""

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
        docs/portability/*|\
        include/silent_hill/*|\
        portable/*|\
        tests/portable/*|\
        scripts/stage01_portability_audit.sh|\
        scripts/stage01_prepare_matching_build.sh|\
        scripts/stage02_create_portable_architecture.sh|\
        scripts/stage03_create_portable_core.sh|\
        scripts/stage04_create_deterministic_timing.sh|\
        scripts/stage05_create_input_io.sh|\
        scripts/stage05_commit_checkpoint.sh)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

require_tools() {
    local missing=0
    local tool

    for tool in \
        git cmake ctest cc make nm tar sha256sum awk grep find \
        stat diff sed sort wc; do

        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'Ferramenta obrigatória ausente: %s\n' "$tool" >&2
            missing=1
        fi
    done

    [[ "$missing" -eq 0 ]] || \
        fail "instale as ferramentas indicadas antes de criar o checkpoint."
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
        "/stage05-input-io-report/" \
        "/stage05-input-io-report.tar.gz" \
        "/build-portable-stage03/" \
        "/build-portable-stage03-sanitizers/" \
        "/build-portable-stage04/" \
        "/build-portable-stage04-sanitizers/" \
        "/build-portable-stage05/" \
        "/build-portable-stage05-sanitizers/" \
        "/stage05-commit-checkpoint-report/" \
        "/stage05-commit-checkpoint-report.tar.gz" \
        "/stage05-portable-checkpoint.patch"; do

        if ! grep -qxF "$entry" "$exclude_file"; then
            printf '%s\n' "$entry" >> "$exclude_file"
        fi
    done
}

locate_stage05_report() {
    local local_report="$REPO_ROOT/$STAGE05_REPORT_DIR_REL"
    local local_archive="$REPO_ROOT/$STAGE05_ARCHIVE_REL"

    if [[ -d "$local_report" ]]; then
        STAGE05_REPORT="$local_report"
        return 0
    fi

    if [[ -f "$local_archive" ]]; then
        TEMP_DIR="$(mktemp -d)"

        tar -xzf "$local_archive" \
            -C "$TEMP_DIR" \
            "$STAGE05_REPORT_DIR_REL"

        STAGE05_REPORT="$TEMP_DIR/$STAGE05_REPORT_DIR_REL"
        return 0
    fi

    fail "não foi encontrado $STAGE05_REPORT_DIR_REL nem $STAGE05_ARCHIVE_REL."
}

validate_stage05_report() {
    local expected_symbols
    local actual_symbols
    local checksum_count

    for report_file in \
        summary.txt \
        ctest.log \
        ctest-sanitizers.log \
        matching-checksum-ok-count.txt \
        abi-symbols.txt \
        abi-symbols-expected.txt \
        SOURCE_SHA256SUMS.txt; do

        [[ -s "$STAGE05_REPORT/$report_file" ]] || \
            fail "relatório obrigatório ausente: $report_file"
    done

    grep -q '^Estado: etapa 05 concluída com sucesso$' \
        "$STAGE05_REPORT/summary.txt" || \
        fail "a etapa 05 não está marcada como concluída."

    grep -q '^Código de saída: 0$' \
        "$STAGE05_REPORT/summary.txt" || \
        fail "a etapa 05 não terminou com código zero."

    grep -q '100% tests passed, 0 tests failed out of 6' \
        "$STAGE05_REPORT/ctest.log" || \
        fail "os seis testes normais não estão confirmados."

    grep -q '100% tests passed, 0 tests failed out of 6' \
        "$STAGE05_REPORT/ctest-sanitizers.log" || \
        fail "os seis testes com sanitizers não estão confirmados."

    checksum_count="$(
        tr -d '[:space:]' \
            < "$STAGE05_REPORT/matching-checksum-ok-count.txt"
    )"

    [[ "$checksum_count" == "50" ]] || \
        fail "o relatório não confirma os 50 checksums matching."

    expected_symbols="$(
        grep -c '^sh_' \
            "$STAGE05_REPORT/abi-symbols-expected.txt"
    )"

    actual_symbols="$(
        grep -c '^sh_' \
            "$STAGE05_REPORT/abi-symbols.txt"
    )"

    [[ "$expected_symbols" -eq 23 ]] || \
        fail "esperados 23 símbolos no contrato; encontrados $expected_symbols."

    [[ "$actual_symbols" -eq 23 ]] || \
        fail "esperados 23 símbolos exportados; encontrados $actual_symbols."

    diff \
        -u \
        "$STAGE05_REPORT/abi-symbols-expected.txt" \
        "$STAGE05_REPORT/abi-symbols.txt" \
        > "$CHECKPOINT_REPORT/validated-abi-symbols.diff" || {

        cat "$CHECKPOINT_REPORT/validated-abi-symbols.diff" >&2
        fail "os símbolos da ABI não correspondem ao contrato."
    }

    (
        cd "$REPO_ROOT"

        sha256sum \
            --check \
            "$STAGE05_REPORT/SOURCE_SHA256SUMS.txt"
    ) > "$CHECKPOINT_REPORT/source-checksums-validation.log" 2>&1 || {

        cat "$CHECKPOINT_REPORT/source-checksums-validation.log" >&2
        fail "os fontes locais diferem dos fontes testados na etapa 05."
    }

    BASELINE_COMMIT="$(
        awk -F': ' '
            /^Commit: / {
                print $2;
                exit;
            }
        ' "$STAGE05_REPORT/summary.txt"
    )"

    [[ "$BASELINE_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]] || \
        fail "commit-base inválido no relatório da etapa 05."

    git cat-file -e "$BASELINE_COMMIT^{commit}" 2>/dev/null || \
        fail "o commit-base não existe neste clone."

    git merge-base \
        --is-ancestor \
        "$BASELINE_COMMIT" \
        HEAD || \
        fail "a branch atual não descende do baseline validado."
}

validate_repository_scope() {
    local path
    local invalid=0

    while IFS= read -r path; do
        [[ -n "$path" ]] || continue

        if ! is_allowed_path "$path"; then
            printf 'Alteração rastreada fora do checkpoint: %s\n' \
                "$path" >&2
            invalid=1
        fi
    done < <(
        {
            git diff --name-only
            git diff --cached --name-only
        } |
            sort -u
    )

    while IFS= read -r path; do
        [[ -n "$path" ]] || continue

        if ! is_allowed_path "$path"; then
            printf 'Arquivo não rastreado fora do checkpoint: %s\n' \
                "$path" >&2
            invalid=1
        fi
    done < <(
        git ls-files \
            --others \
            --exclude-standard
    )

    [[ "$invalid" -eq 0 ]] || \
        fail "foram encontradas alterações fora do escopo seguro."
}

validate_source_tree_safety() {
    local root
    local path
    local size
    local invalid=0

    for root in \
        docs/portability \
        include/silent_hill \
        portable \
        tests/portable; do

        [[ -e "$root" ]] || \
            fail "diretório obrigatório ausente: $root"

        while IFS= read -r -d '' path; do
            if [[ -L "$path" ]]; then
                printf 'Link simbólico não permitido: %s\n' "$path" >&2
                invalid=1
                continue
            fi

            case "$path" in
                *.bin|*.BIN|*.iso|*.ISO|*.cue|*.CUE|\
                *.img|*.IMG|*.rom|*.ROM|*.exe|*.EXE|\
                *.elf|*.ELF|*.o|*.obj|*.a|*.so|*.dll|\
                *.zip|*.7z|*.rar|*.tar|*.gz|*.xz)
                    printf 'Arquivo binário não permitido: %s\n' \
                        "$path" >&2
                    invalid=1
                    ;;
            esac

            if [[ -f "$path" ]]; then
                size="$(stat -c '%s' "$path")"

                if [[ "$size" -gt 1048576 ]]; then
                    printf \
                        'Arquivo acima de 1 MiB não permitido: %s (%s bytes)\n' \
                        "$path" \
                        "$size" >&2
                    invalid=1
                fi
            fi
        done < <(find "$root" -mindepth 1 -print0)
    done

    [[ "$invalid" -eq 0 ]] || \
        fail "a árvore de fontes contém itens incompatíveis com o checkpoint."
}

validate_git_identity() {
    local user_name
    local user_email

    user_name="$(git config --get user.name || true)"
    user_email="$(git config --get user.email || true)"

    if [[ -z "$user_name" && -n "${GIT_USER_NAME:-}" ]]; then
        git config user.name "$GIT_USER_NAME"
        user_name="$GIT_USER_NAME"
    fi

    if [[ -z "$user_email" && -n "${GIT_USER_EMAIL:-}" ]]; then
        git config user.email "$GIT_USER_EMAIL"
        user_email="$GIT_USER_EMAIL"
    fi

    if [[ -z "$user_name" || -z "$user_email" ]]; then
        cat >&2 <<'EOF'

Erro: identidade do Git não configurada.

Configure somente neste repositório, por exemplo:

  git config user.name "Luiz Silva"
  git config user.email "seu-email@example.com"

Depois execute novamente o script.

Também é possível executar passando:

  GIT_USER_NAME="Luiz Silva" \
  GIT_USER_EMAIL="seu-email@example.com" \
  ./scripts/stage05_commit_checkpoint.sh
EOF
        exit 1
    fi

    printf 'Autor Git: %s <%s>\n' "$user_name" "$user_email"
}

run_validation_builds() {
    PHASE="recompilação nativa"

    rm -rf -- "$REPO_ROOT/$BUILD_DIR_REL"

    cmake \
        -S "$REPO_ROOT/portable" \
        -B "$REPO_ROOT/$BUILD_DIR_REL" \
        -DCMAKE_BUILD_TYPE=Debug \
        -DBUILD_TESTING=ON \
        -DSH_ENABLE_WERROR=ON \
        -DSH_ENABLE_SANITIZERS=OFF \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
        2>&1 | tee "$CHECKPOINT_REPORT/cmake-configure.log"

    cmake \
        --build "$REPO_ROOT/$BUILD_DIR_REL" \
        --parallel "$(nproc)" \
        2>&1 | tee "$CHECKPOINT_REPORT/cmake-build.log"

    ctest \
        --test-dir "$REPO_ROOT/$BUILD_DIR_REL" \
        --output-on-failure \
        2>&1 | tee "$CHECKPOINT_REPORT/ctest.log"

    grep -q '100% tests passed, 0 tests failed out of 6' \
        "$CHECKPOINT_REPORT/ctest.log" || \
        fail "a revalidação dos seis testes normais falhou."

    PHASE="recompilação com sanitizers"

    rm -rf -- "$REPO_ROOT/$SANITIZER_BUILD_DIR_REL"

    cmake \
        -S "$REPO_ROOT/portable" \
        -B "$REPO_ROOT/$SANITIZER_BUILD_DIR_REL" \
        -DCMAKE_BUILD_TYPE=Debug \
        -DBUILD_TESTING=ON \
        -DSH_ENABLE_WERROR=ON \
        -DSH_ENABLE_SANITIZERS=ON \
        2>&1 | tee "$CHECKPOINT_REPORT/cmake-sanitizers-configure.log"

    cmake \
        --build "$REPO_ROOT/$SANITIZER_BUILD_DIR_REL" \
        --parallel "$(nproc)" \
        2>&1 | tee "$CHECKPOINT_REPORT/cmake-sanitizers-build.log"

    ASAN_OPTIONS="detect_leaks=1:halt_on_error=1" \
    UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
    ctest \
        --test-dir "$REPO_ROOT/$SANITIZER_BUILD_DIR_REL" \
        --output-on-failure \
        2>&1 | tee "$CHECKPOINT_REPORT/ctest-sanitizers.log"

    grep -q '100% tests passed, 0 tests failed out of 6' \
        "$CHECKPOINT_REPORT/ctest-sanitizers.log" || \
        fail "a revalidação dos testes com sanitizers falhou."
}

validate_current_abi() {
    local shared_library

    PHASE="validação dos símbolos da ABI"

    shared_library="$(
        find "$REPO_ROOT/$BUILD_DIR_REL" \
            -maxdepth 2 \
            -type f \
            -name 'libsilent_hill_core.so*' \
            -print |
            sort |
            head -n 1
    )"

    [[ -n "$shared_library" ]] || \
        fail "biblioteca compartilhada portátil não encontrada."

    nm \
        -D \
        --defined-only \
        "$shared_library" |
        awk '$3 ~ /^sh_/ { print $3 }' |
        sort -u \
        > "$CHECKPOINT_REPORT/current-abi-symbols.txt"

    diff \
        -u \
        "$STAGE05_REPORT/abi-symbols-expected.txt" \
        "$CHECKPOINT_REPORT/current-abi-symbols.txt" \
        > "$CHECKPOINT_REPORT/current-abi-symbols.diff" || {

        cat "$CHECKPOINT_REPORT/current-abi-symbols.diff" >&2
        fail "a ABI recompilada difere do contrato da etapa 05."
    }
}

run_matching_regression() {
    local matching_count

    PHASE="regressão do build matching"

    if [[ -f "$REPO_ROOT/.venv/bin/activate" ]]; then
        # shellcheck disable=SC1091
        source "$REPO_ROOT/.venv/bin/activate"
    fi

    make checksum \
        2>&1 | tee "$CHECKPOINT_REPORT/matching-checksum.log"

    matching_count="$(
        grep -c ': OK$' \
            "$CHECKPOINT_REPORT/matching-checksum.log" || true
    )"

    printf '%s\n' "$matching_count" \
        > "$CHECKPOINT_REPORT/matching-checksum-ok-count.txt"

    [[ "$matching_count" -eq 50 ]] || \
        fail "esperados 50 checksums matching; encontrados $matching_count."
}

stage_safe_paths() {
    local -a paths=()
    local candidate

    for candidate in \
        docs/portability \
        include/silent_hill \
        portable \
        tests/portable \
        scripts/stage01_portability_audit.sh \
        scripts/stage01_prepare_matching_build.sh \
        scripts/stage02_create_portable_architecture.sh \
        scripts/stage03_create_portable_core.sh \
        scripts/stage04_create_deterministic_timing.sh \
        scripts/stage05_create_input_io.sh \
        scripts/stage05_commit_checkpoint.sh; do

        if [[ -e "$candidate" ]]; then
            paths+=("$candidate")
        fi
    done

    [[ "${#paths[@]}" -gt 0 ]] || \
        fail "nenhum arquivo seguro foi encontrado para o checkpoint."

    git add -- "${paths[@]}"
}

validate_staged_snapshot() {
    local path
    local invalid=0
    local total_bytes=0
    local added
    local deleted
    local staged_count

    while IFS= read -r path; do
        [[ -n "$path" ]] || continue

        if ! is_allowed_path "$path"; then
            printf 'Arquivo indevido no stage: %s\n' "$path" >&2
            invalid=1
        fi
    done < <(git diff --cached --name-only)

    [[ "$invalid" -eq 0 ]] || \
        fail "o stage contém arquivos fora do escopo."

    git diff --cached --check || \
        fail "o diff preparado contém erro de whitespace."

    if git diff \
        --cached \
        --numstat |
        awk '$1 == "-" || $2 == "-" { exit 1 }'; then
        :
    else
        fail "o checkpoint contém arquivo binário."
    fi

    while IFS=$'\t' read -r added deleted path; do
        [[ -n "${path:-}" ]] || continue

        if [[ -f "$path" ]]; then
            total_bytes=$((total_bytes + $(stat -c '%s' "$path")))
        fi
    done < <(git diff --cached --numstat)

    [[ "$total_bytes" -le 5242880 ]] || \
        fail "o checkpoint excede o limite seguro de 5 MiB."

    staged_count="$(
        git diff \
            --cached \
            --name-only |
            wc -l |
            tr -d ' '
    )"

    printf '%s\n' "$staged_count" \
        > "$CHECKPOINT_REPORT/staged-file-count.txt"

    git diff \
        --cached \
        --name-status \
        > "$CHECKPOINT_REPORT/staged-files.txt"

    git diff \
        --cached \
        --stat \
        > "$CHECKPOINT_REPORT/staged-stat.txt"

    git diff \
        --cached \
        > "$CHECKPOINT_REPORT/staged.patch"

    printf '%s\n' "$total_bytes" \
        > "$CHECKPOINT_REPORT/staged-source-bytes.txt"
}

create_commit() {
    PHASE="criação do commit"

    PREVIOUS_HEAD="$(git rev-parse HEAD)"

    if git diff --cached --quiet; then
        COMMIT_CREATED=0
        CHECKPOINT_COMMIT="$(git rev-parse HEAD)"

        log
        log "Nenhuma alteração nova para commit."
        log "Usando o HEAD atual como checkpoint:"
        log "  $CHECKPOINT_COMMIT"

        return 0
    fi

    git commit \
        -m "$COMMIT_SUBJECT" \
        -m "Document the portable architecture and migration roadmap." \
        -m "Add the versioned C ABI, opaque runtime, deterministic RNG and fixed-step timing." \
        -m "Add portable input snapshots and host-backed asset/save I/O." \
        -m "Validate 6 native tests, 6 sanitizer tests, 23 ABI symbols and 50 matching checksums." \
        2>&1 | tee "$CHECKPOINT_REPORT/git-commit.log"

    CHECKPOINT_COMMIT="$(git rev-parse HEAD)"
    COMMIT_CREATED=1

    [[ "$CHECKPOINT_COMMIT" != "$PREVIOUS_HEAD" ]] || \
        fail "o Git não criou um novo commit."
}

validate_commit_result() {
    PHASE="validação do commit"

    git cat-file -e "$CHECKPOINT_COMMIT^{commit}" || \
        fail "o objeto de commit não pode ser lido."

    git fsck \
        --no-progress \
        --no-dangling \
        2>&1 | tee "$CHECKPOINT_REPORT/git-fsck.log"

    validate_repository_scope

    if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
        git status \
            --short \
            --branch \
            > "$CHECKPOINT_REPORT/post-commit-status.txt"

        cat "$CHECKPOINT_REPORT/post-commit-status.txt" >&2

        fail "a árvore de trabalho não ficou limpa após o checkpoint."
    fi

    git show \
        --no-ext-diff \
        --stat \
        --summary \
        --decorate \
        "$CHECKPOINT_COMMIT" \
        > "$CHECKPOINT_REPORT/commit-show.txt"

    git show \
        --no-ext-diff \
        --format=fuller \
        --no-patch \
        "$CHECKPOINT_COMMIT" \
        > "$CHECKPOINT_REPORT/commit-metadata.txt"

    git diff \
        --name-status \
        "$BASELINE_COMMIT..$CHECKPOINT_COMMIT" \
        > "$CHECKPOINT_REPORT/baseline-to-checkpoint-files.txt"

    git diff \
        --stat \
        "$BASELINE_COMMIT..$CHECKPOINT_COMMIT" \
        > "$CHECKPOINT_REPORT/baseline-to-checkpoint-stat.txt"

    git ls-tree \
        -r \
        --name-only \
        "$CHECKPOINT_COMMIT" \
        -- \
        docs/portability \
        include/silent_hill \
        portable \
        tests/portable \
        scripts \
        > "$CHECKPOINT_REPORT/checkpoint-tree.txt"

    git format-patch \
        -1 \
        --stdout \
        "$CHECKPOINT_COMMIT" \
        > "$REPO_ROOT/$CHECKPOINT_PATCH_REL"

    sha256sum \
        "$REPO_ROOT/$CHECKPOINT_PATCH_REL" \
        > "$CHECKPOINT_REPORT/checkpoint-patch.sha256"
}

write_final_report() {
    local current_subject
    local changed_count

    current_subject="$(
        git show \
            -s \
            --format='%s' \
            "$CHECKPOINT_COMMIT"
    )"

    changed_count="$(
        git diff \
            --name-only \
            "$BASELINE_COMMIT..$CHECKPOINT_COMMIT" |
            wc -l |
            tr -d ' '
    )"

    {
        echo "SILENT HILL DECOMP — CHECKPOINT APÓS ETAPA 05"
        echo "=============================================="
        echo
        echo "Data UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "Repositório: $REPO_ROOT"
        echo "Branch: $(git branch --show-current)"
        echo "Baseline: $BASELINE_COMMIT"
        echo "Checkpoint: $CHECKPOINT_COMMIT"
        echo "Assunto: $current_subject"
        echo "Novo commit criado: $([[ "$COMMIT_CREATED" -eq 1 ]] && echo sim || echo não)"
        echo "Arquivos diferentes do baseline: $changed_count"
        echo
        echo "Validações:"
        echo "- fontes iguais ao manifesto testado: aprovado"
        echo "- 6 testes normais: aprovado"
        echo "- 6 testes ASan/UBSan: aprovado"
        echo "- 23 símbolos da ABI: aprovado"
        echo "- 50 checksums matching: aprovado"
        echo "- diff sem binários: aprovado"
        echo "- git fsck: aprovado"
        echo "- árvore de trabalho limpa: aprovado"
        echo
        echo "Push remoto executado: não"
        echo "Tag criada: não"
        echo
        echo "Patch portátil:"
        echo "$REPO_ROOT/$CHECKPOINT_PATCH_REL"
    } > "$CHECKPOINT_REPORT/summary.txt"

    {
        echo "Este pacote contém somente:"
        echo
        echo "- metadados do commit local;"
        echo "- lista e estatística dos arquivos versionados;"
        echo "- logs das validações pré-commit;"
        echo "- resultado do git fsck;"
        echo "- checksum do patch portátil."
        echo
        echo "Não contém ROM, BIOS, assets extraídos ou builds do jogo."
        echo "O script não executa push remoto."
    } > "$CHECKPOINT_REPORT/CONTENTS.txt"

    git status \
        --short \
        --branch \
        > "$CHECKPOINT_REPORT/final-git-status.txt"

    (
        cd "$CHECKPOINT_REPORT"

        find . \
            -maxdepth 1 \
            -type f \
            ! -name SHA256SUMS.txt \
            -printf '%P\0' |
            sort -z |
            xargs -0 sha256sum
    ) > "$CHECKPOINT_REPORT/SHA256SUMS.txt"
}

finalize() {
    local result=$?

    trap - EXIT
    set +e

    if [[ "$REPORT_ACTIVE" -eq 1 ]]; then
        if [[ -n "${REPO_ROOT:-}" && -d "${CHECKPOINT_REPORT:-}" ]]; then
            if [[ ! -f "$CHECKPOINT_REPORT/summary.txt" ]]; then
                {
                    echo "SILENT HILL DECOMP — CHECKPOINT APÓS ETAPA 05"
                    echo "=============================================="
                    echo
                    echo "Data UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
                    echo "Fase final: $PHASE"
                    echo "Estado: $FINAL_STATUS"
                    echo "Código de saída: $result"
                    echo "Commit criado: $COMMIT_CREATED"
                    echo
                    echo "Git status:"
                    git status --short --branch 2>/dev/null || true
                } > "$CHECKPOINT_REPORT/summary.txt"
            fi

            rm -f -- "$REPO_ROOT/$CHECKPOINT_ARCHIVE_REL"

            tar -czf "$REPO_ROOT/$CHECKPOINT_ARCHIVE_REL" \
                -C "$REPO_ROOT" \
                "$CHECKPOINT_REPORT_DIR_REL" \
                2>/dev/null || true

            echo
            echo "Relatório do checkpoint:"
            echo "  $REPO_ROOT/$CHECKPOINT_ARCHIVE_REL"
        fi
    fi

    cleanup_temp
    exit "$result"
}

trap finalize EXIT

[[ -d "$REPO" ]] || \
    fail "diretório do projeto não encontrado: $REPO"

cd "$REPO"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || \
    fail "o caminho informado não é um repositório Git válido."

cd "$REPO_ROOT"

CHECKPOINT_REPORT="$REPO_ROOT/$CHECKPOINT_REPORT_DIR_REL"

rm -rf -- "$CHECKPOINT_REPORT"
rm -f -- \
    "$REPO_ROOT/$CHECKPOINT_ARCHIVE_REL" \
    "$REPO_ROOT/$CHECKPOINT_PATCH_REL"

mkdir -p "$CHECKPOINT_REPORT"

REPORT_ACTIVE=1
exec > >(tee "$CHECKPOINT_REPORT/run.log") 2>&1

log "============================================================"
log " SILENT HILL DECOMP — COMMIT SEGURO APÓS ETAPA 05"
log "============================================================"
log
log "Repositório: $REPO_ROOT"
log "Branch atual: $(git branch --show-current)"
log "HEAD atual: $(git rev-parse HEAD)"
log

PHASE="validação das ferramentas"
require_tools
write_local_excludes

PHASE="validação da branch"

CURRENT_BRANCH="$(git branch --show-current)"

if [[ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        fail "não é seguro trocar de branch com alterações rastreadas."
    fi

    if git show-ref \
        --verify \
        --quiet \
        "refs/heads/$TARGET_BRANCH"; then

        git switch "$TARGET_BRANCH"
    else
        fail "a branch esperada não existe: $TARGET_BRANCH"
    fi
fi

PHASE="localização do relatório da etapa 05"
locate_stage05_report

PHASE="validação do relatório e dos fontes"
validate_stage05_report

PHASE="proteção do escopo"
validate_repository_scope
validate_source_tree_safety
validate_git_identity

PHASE="revalidação técnica"
run_validation_builds
validate_current_abi
run_matching_regression

PHASE="preparação seletiva do stage"
stage_safe_paths
validate_staged_snapshot

create_commit
validate_commit_result

PHASE="relatório final"
FINAL_STATUS="checkpoint criado e validado"
write_final_report

log
log "Commit seguro concluído."
log
log "Branch:"
log "  $(git branch --show-current)"
log
log "Commit:"
log "  $CHECKPOINT_COMMIT"
log
log "Patch portátil:"
log "  $REPO_ROOT/$CHECKPOINT_PATCH_REL"
log
log "Push remoto:"
log "  não executado"
