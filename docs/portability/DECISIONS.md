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
