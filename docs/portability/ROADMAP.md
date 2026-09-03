# Roadmap do Runtime Portátil

## Etapa 01 — Baseline matching

Status: concluída.

- auditoria executada;
- submódulos inicializados;
- toolchain instalada;
- build original reproduzido;
- checksums aprovados.

## Etapa 02 — Arquitetura

Status: concluída.

- modelo de dois builds documentado;
- limites de plataforma definidos;
- estratégia de memória e overlays definida;
- rascunho da ABI criado;
- primeiro corte vertical escolhido.

## Etapa 03 — ABI e esqueleto nativo

Status: concluída.

- headers públicos versionados;
- `ShRuntime` opaco;
- serviços do host;
- CMake independente;
- RNG determinístico;
- testes nativos.

## Etapa 04 — Timing determinístico

Status: concluída.

- acumulador inteiro exato de 60 Hz;
- avanço por tempo fornecido pelo host;
- clamp de frames longos;
- pausa e avanço unitário;
- callback headless por tick;
- testes de subdivisão equivalente.

## Etapa 05 — Entrada e arquivos

Status: concluída.

- estado portátil de controles;
- transições `pressed`, `held` e `released`;
- deadzone analógica;
- callbacks de arquivos;
- domínio separado para assets e saves;
- escrita atômica de armazenamento.

## Etapa 06 — Memória e registro de overlays

Status: concluída.

- espaço PS1 lógico independente de ponteiros host;
- RAM padrão de 2 MiB;
- tradução endereço/offset;
- leitura, escrita e fill validados;
- slots de overlay `ENGINE`, `SCREEN` e `MAP`;
- callbacks `init`, `tick` e `shutdown`;
- troca determinística de módulos linkados estaticamente.

## Etapa 07 — Máquina de estados headless

Status: concluída.

- IDs de `GameState` e `SysState` espelhados na ABI portátil;
- módulo `BODYPROG_REFERENCE_HEADLESS` no slot `ENGINE`;
- fluxo de `GameState_Boot_Update` portado como referência;
- transição determinística `Init/Boot -> KonamiLogo`;
- runner `silent-hill-headless`;
- snapshot observável de estado/steps/ações;
- fixture determinística `reference_trace`;
- estados ainda não portados marcados explicitamente como não implementados.

## Etapa 08 — Vídeo e áudio de referência

Status: concluída.

- ABI 0.6 com filas de comandos de apresentação e áudio;
- fronteira de display/fade/logo/present sem API de plataforma;
- tarefas de áudio do boot expostas para o host;
- `GameState_KonamiLogo_Update` portado como referência;
- transição determinística `KonamiLogo -> KcetLogo`;
- testes de filas e trace do logo;
- captura de primitivas/order tables permanece como expansão da camada de apresentação na Etapa 09.

## Etapa 09 — Runner de PC

- janela e controles;
- persistência;
- vídeo e áudio de plataforma;
- validação de progressão do jogo.

## Etapa 10 — Template de ports

- isolar implementação de plataforma;
- documentar contrato;
- criar template reutilizável.
