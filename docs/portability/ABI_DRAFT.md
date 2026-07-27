# ABI C Portátil

A etapa 04 implementa a ABI experimental `0.2.0`.

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

## Regras

- estruturas públicas começam com `struct_size` e `abi_version`;
- `ShRuntime` é opaco;
- a API não expõe tipos Psy-Q;
- `sh_runtime_update` permanece como compatibilidade;
- o host controla a cadência e fornece o tempo decorrido;
- o runtime produz ticks lógicos determinísticos de 60 Hz;
- nenhuma ROM ou asset é embutido na biblioteca.
