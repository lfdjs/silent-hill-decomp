# Etapa 08 — Apresentação e Áudio de Referência

## Objetivo

A etapa 08 cria fronteiras portáteis para apresentação e áudio e usa essas
fronteiras para portar o controle de `GameState_KonamiLogo_Update`.

O core continua sem SDL, OpenGL, Vulkan, ALSA, PulseAudio ou APIs equivalentes.
Em vez disso, a lógica de jogo produz comandos observáveis que um futuro host
PC, Android ou outra plataforma poderá consumir.

## Correspondência com a decompilação

O estado Konami possui quatro passos no código atual:

1. `KonamiLogoStateStep_Init`;
2. `KonamiLogoStateStep_WaitForFade`;
3. `KonamiLogoStateStep_LogoDelay`;
4. `KonamiLogoStateStep_FinishAfterFade`.

A referência portátil preserva essa sequência. No passo inicial são modelados
`Screen_Init(640, true)`, `ScreenFade_Start(true, true, false)`, timestep Q12 de
0.2 e a solicitação dos assets necessários. A cada iteração do estado são
emitidos comandos de desenho do logo Konami e apresentação de frame.

A saída do logo ocorre por input ou após mais de 180 ticks no estado, refletindo
a condição original de três segundos a 60 Hz. Depois do fade final e da fila de
arquivos vazia ocorre a transição para `KcetLogo`.

## Fila de apresentação

`ShPresentationCommand` descreve quatro operações iniciais:

- configuração de display;
- início de fade preservando os três argumentos originais;
- desenho de um logo de boot;
- apresentação de frame.

A fila é limitada a 64 comandos. Se o host deixar de consumi-la, novos comandos
são descartados de forma determinística e contabilizados em
`ShPresentationStats::dropped_count`.

## Fila de áudio

`ShAudioCommand` começa com o comando `TASK`, suficiente para transportar as
tarefas 160 e 162 usadas durante o boot de referência.

A fila é limitada a 32 comandos e segue a mesma política de drop-new da fila de
apresentação.

## Headless

O runner agora avança por:

```text
Init/Boot -> KonamiLogo -> KcetLogo
```

`KcetLogo` continua explicitamente não implementado. A etapa não simula memory
card, FMV, streaming ou o próximo logo.

## Limitações

Ainda não existem backends gráficos ou sonoros reais. Também não são portados:

- `GameState_KcetLogo_Update`;
- intro e FMV;
- menu principal;
- renderização de primitivas PS1;
- mixer/SPU;
- gameplay.

A etapa 09 poderá consumir estas filas em um runner PC real, mantendo o core
independente da plataforma.
