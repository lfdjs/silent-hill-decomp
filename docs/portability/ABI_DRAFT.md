# ABI C Portátil

A etapa 12B implementa a ABI experimental `0.7.0` (50 símbolos públicos).

## Lifecycle

```c
ShResult sh_runtime_create(
    const ShRuntimeConfig* config,
    ShRuntime** out_runtime);

ShResult sh_runtime_boot(ShRuntime* runtime);

ShResult sh_runtime_advance(
    ShRuntime* runtime,
    uint64_t elapsed_us,
    ShAdvanceInfo* out_info);

ShResult sh_runtime_set_paused(
    ShRuntime* runtime,
    bool paused);

ShResult sh_runtime_step(
    ShRuntime* runtime,
    ShAdvanceInfo* out_info);

void sh_runtime_destroy(ShRuntime* runtime);
```

## Memória lógica

```c
ShResult sh_runtime_memory_read(...);
ShResult sh_runtime_memory_write(...);
ShResult sh_runtime_memory_fill(...);
ShResult sh_runtime_memory_address_to_offset(...);
ShResult sh_runtime_memory_offset_to_address(...);
```

`ShPsxAddress` é um valor lógico de 32 bits. A ABI não expõe o ponteiro host
que armazena a RAM portátil.

## Overlays

```c
ShResult sh_runtime_overlay_register(...);
ShResult sh_runtime_overlay_unregister(...);
ShResult sh_runtime_overlay_activate(...);
ShResult sh_runtime_overlay_deactivate(...);
ShResult sh_runtime_overlay_get_active(...);
```

Os overlays portáteis são módulos C linkados estaticamente e selecionados por
ID/slot. Não existe cópia de código executável para endereços PS1 no caminho
nativo.

## Estados de jogo headless

```c
ShResult sh_runtime_game_enable_reference(...);
ShResult sh_runtime_game_disable_reference(...);
ShResult sh_runtime_game_set_boot_signals(...);
ShResult sh_runtime_game_get_snapshot(...);
const char* sh_game_state_name(...);
const char* sh_sys_state_name(...);
```

`ShGameState` e `ShSysState` preservam os valores numéricos dos enums atuais da
decompilação. O módulo de referência porta o controle de boot, Konami e, mediante opt-in,
KCET. Sem `ShGameKcetSignals`, o KCET mantém o comportamento anterior de
estado não implementado. A introdução/FMVs ainda não foram portados.

## Apresentacao e audio

A ABI 0.6 adiciona filas observaveis de comandos. O core emite intencoes de
apresentacao (`configure-display`, `fade-start`, `draw-boot-logo`,
`present-frame`) e tarefas de audio. O host consome essas filas; nenhuma API de
SDL, OpenGL, Vulkan, ALSA ou outra plataforma entra no core.

## KCET opt-in — ABI 0.7.0

`sh_runtime_game_set_kcet_signals` recebe `ShGameKcetSignals`, incluindo o
resultado de memory card fornecido pelo host (`ShKcetCardRoute`) e os sinais
de fade/fila. Não escaneia dispositivos nem carrega saves por si só. As rotas
`NO_CARD` e `NO_SPACE` apontam para `MovieIntroFadeIn`; `NO_SAVE` aponta
para `MovieIntro`; `HAS_SAVE` permanece bloqueada até existir suporte real
a autoload. Isso acrescenta **um** símbolo público à ABI 0.6.0.

## Regras

- estruturas públicas começam com `struct_size` e `abi_version`;
- `ShRuntime` é opaco;
- a API não expõe tipos Psy-Q;
- endereços PS1 não são ponteiros host;
- `sh_runtime_update` permanece como compatibilidade;
- o host controla a cadência e fornece o tempo decorrido;
- o runtime produz ticks lógicos determinísticos de 60 Hz;
- entrada é congelada por tick;
- arquivos e saves são acessados por callbacks do host;
- nenhuma ROM ou asset é embutido na biblioteca.
