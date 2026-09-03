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

- inicializar estado mínimo do jogo;
- registrar primeiros módulos reais;
- executar transições selecionadas;
- criar runner headless;
- criar testes diferenciais.

## Etapa 08 — Vídeo e áudio de referência

- capturar ordering tables;
- implementar renderer de referência;
- criar fronteira de áudio.

## Etapa 09 — Runner de PC

- janela e controles;
- persistência;
- vídeo e áudio de plataforma;
- validação de progressão do jogo.

## Etapa 10 — Template de ports

- isolar implementação de plataforma;
- documentar contrato;
- criar template reutilizável.
