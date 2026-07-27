# Etapa 04 — Timing Determinístico

## Objetivo

Separar o avanço lógico do jogo da apresentação e do `VSync` do PlayStation.

## Modelo adotado

O runtime usa um acumulador inteiro exato:

```text
accumulator += elapsed_microseconds * 60
ticks = accumulator / 1.000.000
accumulator %= 1.000.000
```

Esse modelo evita depender de um timestep arredondado de 16.666 ou 16.667
microssegundos. Um segundo exato sempre produz 60 ticks.

## Clamp

O padrão aceita no máximo 133.333 microssegundos por chamada, permitindo até
oito ticks de recuperação. O restante é contabilizado como tempo descartado.

O clamp evita uma espiral de atualização depois de pausas longas do host.

## Pausa

Quando pausado:

- o tempo recebido não entra no acumulador;
- nenhum tick automático é executado;
- o tempo é contabilizado separadamente;
- `sh_runtime_step` executa exatamente um tick.

## Interpolação

`interpolation_units` varia de 0 a 999.999. A fração de apresentação é:

```text
interpolation_units / 1.000.000
```

## Compatibilidade

`sh_runtime_update` permanece exportada e funciona como um atalho para
`sh_runtime_advance` sem solicitar o relatório detalhado.

## Limitações

O callback de tick ainda é um gancho headless. Ele não executa `MainLoop`,
mapas, áudio ou renderização. Essa integração será feita nas etapas seguintes.
