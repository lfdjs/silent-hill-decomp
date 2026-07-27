#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Erro: o script deve ser executado dentro do repositório Git." >&2
    exit 1
}

cd "$REPO_ROOT"

OUTPUT_DIR="$REPO_ROOT/stage01-build-baseline"
PACKAGE_PATH="$REPO_ROOT/stage01-build-baseline.tar.gz"

ROM_PATH="$REPO_ROOT/rom/image/SLUS-00707.bin"
EXPECTED_SHA1="34278d31d9b9b12b3b5db5e45bcbe548991ecbc7"
EXPECTED_SIZE="616494480"

PHASE="inicialização"
FINAL_STATUS="falha"

mkdir -p "$OUTPUT_DIR"
rm -f "$PACKAGE_PATH"

exec > >(tee "$OUTPUT_DIR/run.log") 2>&1

finish() {
    local result=$?

    {
        echo "SILENT HILL DECOMP — BASELINE MATCHING"
        echo "======================================"
        echo
        echo "Data UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "Repositório: $REPO_ROOT"
        echo "Commit: $(git rev-parse HEAD 2>/dev/null || echo desconhecido)"
        echo "Branch: $(git branch --show-current 2>/dev/null || echo desconhecida)"
        echo "Última fase: $PHASE"
        echo "Estado: $FINAL_STATUS"
        echo "Código de saída: $result"
        echo
        echo "ROM encontrada: $([[ -f "$ROM_PATH" ]] && echo sim || echo não)"
        echo
        echo "Git status:"
        git status --short --branch 2>/dev/null || true
        echo
        echo "Submódulos:"
        git submodule status --recursive 2>/dev/null || true
        echo
        echo "Ferramentas:"
        for tool in \
            make python3 \
            mips-linux-gnu-as \
            mips-linux-gnu-ld \
            mips-linux-gnu-objcopy \
            mips-linux-gnu-objdump \
            mips-linux-gnu-cpp \
            bchunk 7z; do

            if command -v "$tool" >/dev/null 2>&1; then
                printf '%-28s %s\n' "$tool" "$(command -v "$tool")"
            else
                printf '%-28s %s\n' "$tool" "(não encontrado)"
            fi
        done
    } > "$OUTPUT_DIR/summary.txt"

    tar -czf "$PACKAGE_PATH" \
        -C "$REPO_ROOT" \
        "$(basename "$OUTPUT_DIR")" 2>/dev/null || true

    echo
    echo "Resumo: $OUTPUT_DIR/summary.txt"
    echo "Log: $OUTPUT_DIR/run.log"
    echo "Pacote: $PACKAGE_PATH"

    exit "$result"
}

trap finish EXIT

echo "============================================================"
echo " SILENT HILL DECOMP — PREPARAÇÃO DO BASELINE MATCHING"
echo "============================================================"
echo
echo "Repositório: $REPO_ROOT"
echo "Commit: $(git rev-parse HEAD)"
echo

PHASE="configuração das exclusões locais"

GIT_EXCLUDE="$(git rev-parse --git-path info/exclude)"
mkdir -p "$(dirname "$GIT_EXCLUDE")"
touch "$GIT_EXCLUDE"

for ignored_path in \
    "/stage01-portability-audit/" \
    "/stage01-portability-audit.tar.gz" \
    "/stage01-build-baseline/" \
    "/stage01-build-baseline.tar.gz"; do

    if ! grep -qxF "$ignored_path" "$GIT_EXCLUDE"; then
        echo "$ignored_path" >> "$GIT_EXCLUDE"
    fi
done

PHASE="instalação das dependências do sistema"

echo
echo "Instalando dependências oficiais para Debian/Ubuntu..."
echo

sudo apt-get update

sudo apt-get install -y \
    git \
    build-essential \
    binutils-mips-linux-gnu \
    cpp-mips-linux-gnu \
    python3 \
    python3-venv \
    bchunk \
    p7zip-full

PHASE="inicialização dos submódulos"

echo
echo "Sincronizando e inicializando submódulos..."
echo

git submodule sync --recursive
git submodule update --init --recursive

if git submodule status --recursive | grep -q '^-'; then
    echo "Erro: ainda existem submódulos não inicializados." >&2
    git submodule status --recursive >&2
    exit 1
fi

PHASE="configuração do ambiente Python"

echo
echo "Criando ambiente virtual Python..."
echo

if [[ ! -d .venv ]]; then
    python3 -m venv .venv
fi

if [[ ! -x .venv/bin/python ]]; then
    echo "Erro: o ambiente virtual não foi criado corretamente." >&2
    exit 1
fi

.venv/bin/python -m pip install -r requirements.txt

PHASE="validação das ferramentas"

echo
echo "Validando ferramentas obrigatórias..."
echo

REQUIRED_COMMANDS=(
    make
    python3
    mips-linux-gnu-as
    mips-linux-gnu-ld
    mips-linux-gnu-objcopy
    mips-linux-gnu-objdump
    mips-linux-gnu-cpp
    bchunk
    7z
)

missing_tools=0

for tool in "${REQUIRED_COMMANDS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf '[OK]   %-28s %s\n' "$tool" "$(command -v "$tool")"
    else
        printf '[ERRO] %-28s não encontrado\n' "$tool"
        missing_tools=1
    fi
done

if [[ "$missing_tools" -ne 0 ]]; then
    echo "Erro: uma ou mais ferramentas obrigatórias estão ausentes." >&2
    exit 1
fi

PHASE="verificação da imagem do jogo"

echo
echo "Verificando a imagem fornecida pelo usuário..."
echo

if [[ ! -f "$ROM_PATH" ]]; then
    echo "A imagem do jogo não foi encontrada em:"
    echo
    echo "  $ROM_PATH"
    echo
    echo "A preparação do ambiente foi concluída, mas o build matching"
    echo "não será executado até que uma imagem própria e válida esteja"
    echo "presente nesse caminho."
    echo
    echo "Nenhuma ROM ou arquivo proprietário foi baixado pelo script."

    FINAL_STATUS="ambiente preparado; build aguardando imagem válida"
    exit 0
fi

ACTUAL_SHA1="$(sha1sum "$ROM_PATH" | awk '{print tolower($1)}')"
ACTUAL_SIZE="$(stat -c '%s' "$ROM_PATH")"

echo "SHA-1 esperado: $EXPECTED_SHA1"
echo "SHA-1 obtido:  $ACTUAL_SHA1"
echo
echo "Tamanho esperado: $EXPECTED_SIZE bytes"
echo "Tamanho obtido:    $ACTUAL_SIZE bytes"

if [[ "$ACTUAL_SHA1" != "$EXPECTED_SHA1" ]]; then
    echo
    echo "Erro: a imagem não corresponde à edição NTSC-U 1.1 esperada." >&2
    echo "O build não será iniciado para evitar resultados inválidos." >&2
    exit 2
fi

if [[ "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]]; then
    echo
    echo "Erro: o tamanho da imagem não corresponde ao esperado." >&2
    exit 2
fi

PHASE="extração e geração do projeto"

echo
echo "Imagem validada."
echo "Executando make setup..."
echo

source .venv/bin/activate
make setup 2>&1 | tee "$OUTPUT_DIR/make-setup.log"

PHASE="build matching"

echo
echo "Executando build matching..."
echo

MAKE_JOBS="${MAKE_JOBS:-$(nproc)}"

make -j"$MAKE_JOBS" 2>&1 | tee "$OUTPUT_DIR/make-build.log"

PHASE="coleta dos checksums"

echo
echo "Coletando artefatos e checksums..."
echo

find build \
    -type f \
    \( -name '*.BIN' -o \
       -name '*.bin' -o \
       -name '*.elf' -o \
       -name '*.map' \) \
    -print \
    2>/dev/null |
    sort > "$OUTPUT_DIR/generated-artifacts.txt"

if [[ -d build ]]; then
    find build \
        -type f \
        \( -name '*.BIN' -o \
           -name '*.bin' -o \
           -name '*.elf' \) \
        -print0 \
        2>/dev/null |
        sort -z |
        xargs -0 -r sha256sum \
        > "$OUTPUT_DIR/generated-checksums.sha256"
fi

FINAL_STATUS="baseline matching concluído com sucesso"

echo
echo "Baseline matching concluído."
