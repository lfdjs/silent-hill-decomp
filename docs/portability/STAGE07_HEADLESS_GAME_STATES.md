# Etapa 07 — Estados de Jogo Headless

## Objetivo

A etapa 07 conecta o runtime portátil à primeira fatia de lógica de controle
extraída diretamente da decompilação atual: os IDs de `e_GameState` e
`e_SysState` e o fluxo de `GameState_Boot_Update` em
`src/bodyprog/sys/game_main.c`.

A meta desta etapa não é tornar o jogo jogável. O objetivo é provar que uma
máquina de estados derivada da lógica real pode executar de forma
determinística no runtime nativo, usando os overlays e o clock já portados,
sem incluir Psy-Q, GPU, SPU ou endereços host fixos.

## Correspondência com a decompilação

`ShGameState` preserva os valores numéricos usados por `e_GameState`:

```text
Init / Boot          0
KonamiLogo           1
MainMenu             7
InGame              11
Credits             21
RemovedDebug        22
```

`ShSysState` preserva os valores de `e_SysState`, incluindo:

```text
Gameplay             0
OptionsMenu          1
StatusMenu           2
MapScreen            3
GamePaused          14
Invalid             15
```

Os nomes públicos usam o prefixo `SH_` para não misturar diretamente tipos do
build matching com a ABI portátil.

## Primeiro módulo de referência

A função original `GameState_Boot_Update` possui quatro passos principais. O
módulo `BODYPROG_REFERENCE_HEADLESS`, registrado no slot `ENGINE`, espelha esse
controle:

1. inicialização da tela;
2. espera de áudio e solicitação das tarefas 160 e 162;
3. fila dos assets de boot e início do fade;
4. espera do fade/fila e transição para `KonamiLogo`.

No PS1, essas operações chamam diretamente subsistemas como `Screen_Init`,
`SD_Call`, `Fs_QueueStartReadTim`, `ScreenFade_Start` e
`Fs_QueueWaitForEmpty`. No runtime headless elas são representadas por ações e
sinais explícitos, permitindo testar o controle sem fingir que GPU, áudio ou
filesystem do jogo já foram portados.

## Sinais de boot

`ShGameBootSignals` representa apenas condições externas observadas pela
máquina de boot:

- `audio_streaming_idle`;
- `fade_finished`;
- `file_queue_empty`.

Esses sinais não substituem os futuros backends. Eles são uma fronteira
temporária e determinística para a execução headless.

## Snapshot

`ShGameSnapshot` expõe o estado observável necessário para testes e ferramentas:

- estado anterior e atual;
- três `state_steps`, equivalentes ao formato usado por `g_GameWork`;
- `sys_state`;
- último tick;
- ticks no estado atual;
- quantidade de transições;
- ações produzidas no último tick;
- último ID de tarefa de áudio;
- indicação de módulo de referência ativo;
- indicação de estado atualmente implementado.

## Runner headless

O CMake passa a produzir:

```text
silent-hill-headless
```

Exemplo:

```text
Silent Hill portable headless ABI 0.5.0
reference: GameState_Init/Boot=0 -> KonamiLogo=1
tick=1 state=0(Init/Boot) step=1/0/0 actions=0x00000001
tick=2 state=0(Init/Boot) step=1/1/0 actions=0x00000002 audio_task=160
tick=3 state=0(Init/Boot) step=1/2/0 actions=0x00000002 audio_task=162
...
tick=6 state=1(KonamiLogo) step=0/0/0 actions=0x00000040 implemented=no
```

Ao chegar a `KonamiLogo`, o runner não inventa a implementação do próximo
estado. Ele o marca como não implementado. A expansão dos estados será feita
incrementalmente conforme os subsistemas necessários forem isolados.

## Testes diferenciais de estrutura

O teste `reference_trace` fixa uma sequência esperada de estados, steps, ações
e IDs de tarefas para o boot. Ele funciona como uma fixture de referência para
evitar alterações acidentais no fluxo portado.

A etapa também mantém os testes anteriores de RNG, timing, input, I/O, memória
e overlays.

## Limitações

Ainda não são executados nativamente:

- `GameState_KonamiLogo_Update`;
- menu principal;
- `GameState_InGame_Update`;
- `SysState_Gameplay_Update`;
- eventos e scripts de mapa;
- renderização PS1;
- áudio SPU;
- streaming de CD;
- vídeos FMV.

A etapa 08 deverá começar a criar as fronteiras de apresentação necessárias
para avançar além do boot sem contaminar o core portátil com APIs de
plataforma.
