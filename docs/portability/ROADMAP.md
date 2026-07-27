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

Status: concluída.

- acumulador inteiro exato de 60 Hz;
- avanço por tempo fornecido pelo host;
- clamp de frames longos;
- pausa e avanço unitário;
- callback headless por tick;
- testes de subdivisão equivalente.

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
