# ABI C Portátil

A etapa 06 implementa a ABI experimental `0.4.0`.

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
