# Etapa 05 — Entrada, Arquivos e Armazenamento

## Entrada portátil

O host envia um `ShInputState`. O runtime aplica uma deadzone inteira e
determinística e congela o estado no início de cada tick lógico.

Cada `ShInputSnapshot` contém:

- estado de conexão;
- botões mantidos;
- botões pressionados no tick;
- botões liberados no tick;
- quatro eixos analógicos filtrados;
- índice do tick em que o snapshot foi criado.

O núcleo não consulta diretamente SDL, teclado, gamepad ou `libkpad`.

## Deadzone

A região central é convertida para zero. A faixa restante é reescalada para
`[-32767, 32767]`, usando somente aritmética inteira.

## Arquivos

O host recebe caminhos lógicos relativos e um domínio:

- `SH_FILE_DOMAIN_ASSET`;
- `SH_FILE_DOMAIN_SAVE`.

O contrato permite:

- consultar existência e tamanho;
- ler intervalos parciais;
- distinguir arquivo ausente de falha de I/O.

Caminhos absolutos, barras invertidas, `.` e `..` são rejeitados pelo runtime.

## Armazenamento

Saves possuem operações explícitas de:

- escrita atômica;
- remoção;
- consulta e leitura pelo domínio de save.

A implementação de PC poderá usar arquivo temporário, `fsync` e rename. Outras
plataformas poderão mapear o mesmo contrato para seus próprios serviços.

## Limitações atuais

Esta etapa ainda não conecta os snapshots à estrutura `Joy` original e não
substitui `Fs_Queue`. Ela estabelece a fronteira portátil que será usada na
migração real.
