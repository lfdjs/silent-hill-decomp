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
