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
