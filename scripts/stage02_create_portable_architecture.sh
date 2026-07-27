#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

REPO="${REPO:-$HOME/Documentos/projetos_decompilacao/silent-hill-decomp}"
TARGET_BRANCH="portability/core-api"
DOC_DIR_REL="docs/portability"
REPORT_DIR_REL="stage02-architecture-report"
PACKAGE_REL="stage02-architecture-report.tar.gz"
BASELINE_DIR_REL="stage01-build-baseline"
BASELINE_ARCHIVE_REL="stage01-build-baseline.tar.gz"

log() {
    printf '%s\n' "$*"
}

fail() {
    printf 'Erro: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR:-}" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}
trap cleanup EXIT

[[ -d "$REPO" ]] || fail "diretório do projeto não encontrado: $REPO"
cd "$REPO"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || \
    fail "o diretório informado não é um repositório Git válido."

cd "$REPO_ROOT"

DOC_DIR="$REPO_ROOT/$DOC_DIR_REL"
REPORT_DIR="$REPO_ROOT/$REPORT_DIR_REL"
PACKAGE="$REPO_ROOT/$PACKAGE_REL"
BASELINE_SUMMARY="$REPO_ROOT/$BASELINE_DIR_REL/summary.txt"
TEMP_DIR=""

log "============================================================"
log " SILENT HILL DECOMP — ETAPA 02 — ARQUITETURA PORTÁTIL"
log "============================================================"
log
log "Repositório: $REPO_ROOT"
log "Branch atual: $(git branch --show-current)"
log "Commit atual: $(git rev-parse HEAD)"
log

# ---------------------------------------------------------------------------
# Localiza e valida o baseline da etapa 01.
# ---------------------------------------------------------------------------

if [[ ! -f "$BASELINE_SUMMARY" ]]; then
    if [[ -f "$REPO_ROOT/$BASELINE_ARCHIVE_REL" ]]; then
        TEMP_DIR="$(mktemp -d)"

        tar -xzf "$REPO_ROOT/$BASELINE_ARCHIVE_REL" \
            -C "$TEMP_DIR" \
            "$BASELINE_DIR_REL/summary.txt"

        BASELINE_SUMMARY="$TEMP_DIR/$BASELINE_DIR_REL/summary.txt"
    else
        fail "não foi encontrado $BASELINE_DIR_REL/summary.txt nem $BASELINE_ARCHIVE_REL."
    fi
fi

grep -q '^Estado: baseline matching concluído com sucesso$' "$BASELINE_SUMMARY" || {
    printf '\nResumo encontrado:\n' >&2
    sed -n '1,100p' "$BASELINE_SUMMARY" >&2
    fail "o baseline matching não está marcado como concluído com sucesso."
}

BASELINE_COMMIT="$(
    awk -F': ' '
        /^Commit: / {
            print $2;
            exit;
        }
    ' "$BASELINE_SUMMARY"
)"

[[ "$BASELINE_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]] || \
    fail "não foi possível identificar o commit de baseline."

git cat-file -e "$BASELINE_COMMIT^{commit}" 2>/dev/null || \
    fail "o commit de baseline não existe neste clone: $BASELINE_COMMIT"

log "Baseline confirmado:"
log "  $BASELINE_COMMIT"
log

# ---------------------------------------------------------------------------
# Protege alterações locais fora do escopo da etapa.
# ---------------------------------------------------------------------------

is_allowed_path() {
    case "$1" in
        "$DOC_DIR_REL"/*|scripts/stage02_create_portable_architecture.sh)
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
                printf 'Alteração preparada fora do escopo: %s\n' "$changed_path" >&2
                invalid=1
            fi
        done < <(git diff --cached --name-only)
    else
        while IFS= read -r changed_path; do
            [[ -n "$changed_path" ]] || continue
            if ! is_allowed_path "$changed_path"; then
                printf 'Alteração local fora do escopo: %s\n' "$changed_path" >&2
                invalid=1
            fi
        done < <(git diff --name-only)
    fi

    [[ "$invalid" -eq 0 ]]
}

check_changed_paths unstaged || \
    fail "salve, reverta ou mova as alterações indicadas antes de executar a etapa 02."

check_changed_paths staged || \
    fail "remova do stage as alterações indicadas antes de executar a etapa 02."

# ---------------------------------------------------------------------------
# Cria ou reutiliza a branch de portabilidade.
# ---------------------------------------------------------------------------

CURRENT_BRANCH="$(git branch --show-current)"

if [[ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        fail "existem alterações rastreadas locais; não é seguro trocar de branch."
    fi

    if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
        git switch "$TARGET_BRANCH"
    else
        git switch -c "$TARGET_BRANCH" "$BASELINE_COMMIT"
    fi
fi

git merge-base --is-ancestor "$BASELINE_COMMIT" HEAD || \
    fail "a branch $TARGET_BRANCH não descende do baseline validado."

# ---------------------------------------------------------------------------
# Exclusões locais para relatórios.
# ---------------------------------------------------------------------------

GIT_EXCLUDE="$(git rev-parse --git-path info/exclude)"
mkdir -p "$(dirname "$GIT_EXCLUDE")"
touch "$GIT_EXCLUDE"

for entry in \
    "/stage01-portability-audit/" \
    "/stage01-portability-audit.tar.gz" \
    "/stage01-build-baseline/" \
    "/stage01-build-baseline.tar.gz" \
    "/stage02-architecture-report/" \
    "/stage02-architecture-report.tar.gz"; do

    if ! grep -qxF "$entry" "$GIT_EXCLUDE"; then
        printf '%s\n' "$entry" >> "$GIT_EXCLUDE"
    fi
done

# ---------------------------------------------------------------------------
# Criação da documentação.
# ---------------------------------------------------------------------------

mkdir -p "$DOC_DIR"
rm -rf -- "$REPORT_DIR"
rm -f -- "$PACKAGE"
mkdir -p "$REPORT_DIR"

cat > "$DOC_DIR/README.md" <<'DOC'
# Portabilidade do Silent Hill

Este diretório documenta o segundo caminho de build do projeto: o runtime
portátil para futuros ports.

O build matching de PlayStation continua sendo a referência comportamental e
binária. A camada portátil não substitui o Makefile original e não inclui ROM,
BIOS ou assets proprietários.

## Documentos

- `ARCHITECTURE.md`: camadas e limites do runtime.
- `ABI_DRAFT.md`: primeiro rascunho da API C pública.
- `DECISIONS.md`: decisões arquiteturais aceitas.
- `MIGRATION_MATRIX.tsv`: subsistemas e estratégia de migração.
- `ROADMAP.md`: etapas principais do projeto.
DOC

cat > "$DOC_DIR/ARCHITECTURE.md" <<'DOC'
# Arquitetura do Runtime Portátil

## Objetivo

Adicionar ao projeto uma biblioteca portátil capaz de hospedar a lógica do
jogo e servir de base para ports, preservando integralmente o build matching do
PlayStation.

## Dois caminhos de build

### Build matching

- continua usando o Makefile original;
- usa a toolchain MIPS e os linkers originais;
- mantém endereços, overlays e layout binário;
- precisa continuar passando todos os checksums.

### Build portátil

- será independente e baseado em CMake;
- usará compiladores modernos;
- produzirá uma biblioteca com ABI C;
- receberá serviços da plataforma por callbacks;
- não interpretará endereços do PS1 como ponteiros do host.

## Camadas

```text
Port específico
  PC / Switch / Android / outras plataformas
        |
Host da plataforma
  tempo, arquivos, saves, entrada, vídeo, áudio e log
        |
ABI C pública
  lifecycle e estruturas versionadas
        |
Runtime portátil
  estado, timing, módulos e compatibilidade
        |
Núcleo do jogo
  gameplay, eventos, mapas e telas decompiladas
        |
Build matching do PS1
  referência de comportamento e checksums
```

## Organização proposta

```text
include/silent_hill/
    sh_api.h
    sh_host.h
    sh_input.h
    sh_result.h
    sh_types.h

portable/
    core/
    compatibility/
    overlays/
    runtime/

ports/
    pc/
    platform-template/

tests/
    api/
    portable/
    differential/
```

## Limites de plataforma

O núcleo portátil não deverá chamar diretamente Psy-Q, SDL, OpenGL, Vulkan ou
SDKs de console. O host fornecerá:

- relógio monotônico;
- logging;
- leitura de arquivos;
- armazenamento persistente;
- estado de controles;
- envio de comandos de vídeo;
- envio de áudio;
- eventos de ciclo de vida.

## Estado do runtime

A API pública usará um `ShRuntime` opaco. No início, parte dos globais do jogo
poderá permanecer internamente. A migração será gradual e coberta por testes.

## Timing

A simulação será separada da apresentação. O host fornecerá tempo decorrido,
mas o runtime preservará a escala lógica original de 60 ticks e o comportamento
de 30 FPS quando exigido pelo jogo.

## Overlays

No build portátil, overlays serão módulos estaticamente vinculados e
registrados por ID. O carregamento por cópia de código para endereços fixos
continuará existindo apenas no build matching.

## Memória

Serão distinguidos:

- ponteiros reais do host;
- offsets do espaço de endereços do PS1;
- memória temporária por frame;
- estado persistente;
- estado local de overlays.

## Estratégia de vídeo

A primeira implementação capturará comandos equivalentes aos primitivos do
PS1 e às ordering tables. Um backend de referência no PC interpretará esses
comandos antes de qualquer reescrita gráfica de alto nível.

## Estratégia de áudio

A lógica de sequenciamento será separada da saída. Um backend de compatibilidade
poderá representar a SPU inicialmente, enquanto o host recebe os buffers finais.

## Primeiro corte vertical

A primeira fatia executável conterá:

1. tipos portáteis de largura fixa;
2. lifecycle de `ShRuntime`;
3. tabela versionada de serviços do host;
4. logging;
5. RNG determinístico;
6. testes da ABI;
7. build nativo Linux por CMake.

Ela ainda não carregará nem renderizará o jogo completo.
DOC

cat > "$DOC_DIR/ABI_DRAFT.md" <<'DOC'
# Rascunho da ABI C

Este documento descreve a forma inicial da API. Os headers reais serão criados
na etapa 03.

```c
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct ShRuntime ShRuntime;

typedef enum ShResult
{
    SH_RESULT_OK = 0,
    SH_RESULT_INVALID_ARGUMENT,
    SH_RESULT_UNSUPPORTED_VERSION,
    SH_RESULT_HOST_ERROR,
    SH_RESULT_OUT_OF_MEMORY,
    SH_RESULT_NOT_READY
} ShResult;

typedef struct ShHostServices
{
    uint32_t struct_size;
    uint32_t abi_version;
    void* userdata;

    uint64_t (*time_now_us)(void* userdata);
    void (*log)(void* userdata, int level, const char* message);

    bool (*file_read)(
        void* userdata,
        const char* path,
        uint64_t offset,
        void* destination,
        size_t size);
} ShHostServices;

typedef struct ShRuntimeConfig
{
    uint32_t struct_size;
    uint32_t abi_version;
    const ShHostServices* host;
} ShRuntimeConfig;

ShResult sh_runtime_create(
    const ShRuntimeConfig* config,
    ShRuntime** out_runtime);

void sh_runtime_destroy(ShRuntime* runtime);

ShResult sh_runtime_boot(ShRuntime* runtime);

ShResult sh_runtime_update(
    ShRuntime* runtime,
    uint64_t elapsed_us);
```

## Regras

- estruturas públicas começam com `struct_size` e `abi_version`;
- o runtime é opaco;
- a API não expõe tipos Psy-Q;
- callbacks não mantêm ponteiros temporários fornecidos pelo runtime;
- funções retornam `ShResult` para falhas recuperáveis;
- destruição aceita `NULL`;
- nenhuma ROM ou asset é embutido na biblioteca.
DOC

cat > "$DOC_DIR/DECISIONS.md" <<'DOC'
# Decisões Arquiteturais

## ADR-001 — Preservar dois builds independentes

Status: aceita.

O build matching permanece intacto e é a referência de regressão. O build
portátil é adicionado em paralelo.

## ADR-002 — Usar ABI C pública

Status: aceita.

A ABI C reduz acoplamento entre compiladores e facilita integração com C++,
Rust e SDKs de plataformas.

## ADR-003 — Usar runtime opaco

Status: aceita.

O consumidor recebe apenas `ShRuntime*`, sem depender do layout interno.

## ADR-004 — Serviços fornecidos pelo host

Status: aceita.

Tempo, arquivos, saves, entrada, vídeo, áudio e logging entram por callbacks.

## ADR-005 — Overlays como módulos registrados

Status: aceita.

O build portátil vincula os módulos normalmente e os seleciona por IDs e
tabelas de funções.

## ADR-006 — Endereços do PS1 não são ponteiros do host

Status: aceita.

Quando a identidade do endereço for relevante, será usado um espaço de
endereços traduzido explicitamente.

## ADR-007 — Separar simulação e apresentação

Status: aceita.

O host fornece o tempo; o runtime preserva a semântica lógica original.

## ADR-008 — Migrar primeiro o RNG

Status: aceita.

O RNG existente é pequeno, determinístico e não depende diretamente de
hardware Psy-Q, sendo adequado ao primeiro teste nativo.

## ADR-009 — Não versionar dados proprietários

Status: aceita.

ROM, BIOS e assets extraídos continuam locais e ignorados pelo Git.
DOC

cat > "$DOC_DIR/MIGRATION_MATRIX.tsv" <<'TSV'
Subsistema	Limite original	Limite portátil	Risco	Primeira ação
Build	Makefile e toolchain MIPS	CMake independente	Médio	Preservar build matching
Tipos	Tipos Psy-Q e suposições de 32 bits	Tipos de largura fixa	Médio	Criar sh_types.h
Runtime	Globais e MainLoop	ShRuntime opaco	Alto	Criar lifecycle mínimo
Timing	VSync e GsGetVcount	Relógio monotônico do host	Alto	Criar adaptador determinístico
Entrada	Joy_ReadP1 e libkpad	ShInputState	Médio	Receber estado pelo host
Arquivos	Fs_Queue e CD-ROM	Callbacks do host	Alto	Definir API de leitura
Vídeo	GPU e ordering tables	Fila portátil de comandos	Muito alto	Capturar comandos do PS1
Áudio	SPU e tarefas SD	Saída de áudio do host	Muito alto	Separar lógica e saída
Overlays	Destinos fixos na RAM	Registro estático de módulos	Muito alto	Criar IDs e descritores
RNG	g_RngSeed e Rng_Rand32	Módulo determinístico	Baixo	Primeiro corte vertical
Estados	g_GameStateUpdateFuncs	Dispatcher do runtime	Médio	Encapsular após lifecycle
Save	Memory card	Armazenamento persistente do host	Alto	Definir callbacks versionados
TSV

cat > "$DOC_DIR/ROADMAP.md" <<'DOC'
# Roadmap do Runtime Portátil

## Etapa 01 — Baseline matching

Status: concluída.

- auditoria executada;
- submódulos inicializados;
- toolchain instalada;
- build original reproduzido;
- checksums aprovados.

## Etapa 02 — Arquitetura

Status: concluída por este script.

- modelo de dois builds documentado;
- limites de plataforma definidos;
- estratégia de memória e overlays definida;
- rascunho da ABI criado;
- primeiro corte vertical escolhido.

## Etapa 03 — ABI e esqueleto nativo

- criar headers públicos;
- criar `ShRuntime` opaco;
- criar serviços do host;
- criar CMake independente;
- portar o RNG;
- adicionar testes.

## Etapa 04 — Timing determinístico

- extrair fronteira de um frame;
- fornecer tempo pelo host;
- preservar ticks originais;
- permitir execução headless.

## Etapa 05 — Entrada e arquivos

- criar estado portátil de controles;
- adicionar callbacks de arquivos;
- isolar CD-ROM e memory card.

## Etapa 06 — Registro de overlays

- criar IDs estáveis;
- registrar mapas e telas;
- remover cópia de código no build portátil.

## Etapa 07 — Máquina de estados headless

- inicializar estado mínimo;
- executar transições selecionadas;
- criar testes diferenciais.

## Etapa 08 — Vídeo e áudio de referência

- capturar ordering tables;
- implementar renderer de referência;
- criar fronteira de áudio.

## Etapa 09 — Runner de PC

- janela e controles;
- persistência;
- validação de progressão do jogo.

## Etapa 10 — Template de ports

- isolar implementação de plataforma;
- documentar contrato;
- criar template reutilizável.
DOC

# ---------------------------------------------------------------------------
# Validação.
# ---------------------------------------------------------------------------

DOCUMENTS=(
    "$DOC_DIR/README.md"
    "$DOC_DIR/ARCHITECTURE.md"
    "$DOC_DIR/ABI_DRAFT.md"
    "$DOC_DIR/DECISIONS.md"
    "$DOC_DIR/MIGRATION_MATRIX.tsv"
    "$DOC_DIR/ROADMAP.md"
)

for document in "${DOCUMENTS[@]}"; do
    [[ -s "$document" ]] || fail "arquivo ausente ou vazio: $document"
done

for document in "${DOCUMENTS[@]}"; do
    if grep -nE '[[:blank:]]+$' "$document" >/dev/null; then
        grep -nE '[[:blank:]]+$' "$document" >&2 || true
        fail "espaços finais encontrados em $document"
    fi
done

if grep -Il $'\r' "${DOCUMENTS[@]}" | grep -q .; then
    fail "um ou mais documentos foram gravados com CRLF."
fi

awk -F '\t' '
    NR == 1 {
        expected = NF;
        next;
    }

    NF != expected {
        printf \
            "Linha TSV inválida: %d; campos: %d; esperado: %d\n", \
            NR, NF, expected > "/dev/stderr";
        failed = 1;
    }

    END {
        exit failed;
    }
' "$DOC_DIR/MIGRATION_MATRIX.tsv" || fail "matriz TSV inválida."

# ---------------------------------------------------------------------------
# Relatórios.
# ---------------------------------------------------------------------------

{
    echo "SILENT HILL DECOMP — ETAPA 02"
    echo "=============================="
    echo
    echo "Data UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Repositório: $REPO_ROOT"
    echo "Branch: $(git branch --show-current)"
    echo "Commit atual: $(git rev-parse HEAD)"
    echo "Commit do baseline: $BASELINE_COMMIT"
    echo "Baseline matching: confirmado"
    echo "Documentos criados: ${#DOCUMENTS[@]}"
    echo "Validação de conteúdo: aprovada"
    echo "Validação da matriz TSV: aprovada"
    echo "Dados proprietários incluídos: não"
    echo
    echo "Arquivos da etapa:"
    printf '%s\n' "${DOCUMENTS[@]#"$REPO_ROOT/"}"
    echo
    echo "Próxima etapa:"
    echo "Etapa 03 — ABI C, CMake nativo, ShRuntime e teste do RNG."
} > "$REPORT_DIR/summary.txt"

{
    echo "Git status:"
    git status --short --branch
    echo
    echo "Arquivos relevantes:"
    git status \
        --short \
        --untracked-files=all \
        -- \
        "$DOC_DIR_REL" \
        scripts/stage02_create_portable_architecture.sh || true
} > "$REPORT_DIR/git-state.txt"

{
    printf 'Documento\tLinhas\tBytes\n'
    for document in "${DOCUMENTS[@]}"; do
        printf '%s\t%s\t%s\n' \
            "${document#"$REPO_ROOT/"}" \
            "$(wc -l < "$document" | tr -d ' ')" \
            "$(stat -c '%s' "$document")"
    done
} > "$REPORT_DIR/document-inventory.tsv"

sha256sum \
    "${DOCUMENTS[@]}" \
    scripts/stage02_create_portable_architecture.sh \
    > "$REPORT_DIR/SHA256SUMS.txt"

cat > "$REPORT_DIR/CONTENTS.txt" <<'EOF'
Este pacote contém somente:

- documentação da arquitetura portátil;
- relatório textual da etapa 02;
- script persistente usado para gerar a etapa.

Não contém ROM, BIOS, executáveis do jogo nem assets extraídos.
EOF

tar -czf "$PACKAGE" \
    -C "$REPO_ROOT" \
    "$DOC_DIR_REL" \
    scripts/stage02_create_portable_architecture.sh \
    "$REPORT_DIR_REL"

log
log "Etapa 02 concluída com sucesso."
log
log "Branch:"
log "  $(git branch --show-current)"
log
log "Documentação:"
log "  $DOC_DIR"
log
log "Relatório:"
log "  $REPORT_DIR"
log
log "Pacote para envio:"
log "  $PACKAGE"
log
log "Nenhum commit foi criado automaticamente."
