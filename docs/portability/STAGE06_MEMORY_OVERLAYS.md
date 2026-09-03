# Etapa 06 — Memória Portátil e Overlays

## Objetivo

A etapa 06 introduz a primeira representação explícita do espaço de endereços
do PlayStation dentro do runtime portátil e substitui, no caminho nativo, a
ideia de copiar código executável para endereços fixos por um registro de
módulos C já linkados ao programa.

O build matching original continua inalterado e segue usando a organização de
memória e overlays necessária ao PlayStation.

## Espaço de endereços lógico

O runtime portátil usa `ShPsxAddress`, um inteiro de 32 bits. Ele representa um
endereço do espaço lógico do jogo, mas nunca é convertido diretamente em um
ponteiro do processo host.

A configuração padrão modela 2 MiB de RAM:

```text
base: 0x80000000
size: 0x00200000
fim exclusivo: 0x80200000
```

A memória nativa correspondente é alocada pelo runtime e permanece privada.
A API pública oferece operações de validação, tradução endereço/offset,
leitura, escrita e preenchimento.

## Motivo para não usar ponteiros nativos

Um valor como `0x80024B60` tinha significado no mapa de memória do PlayStation.
Em Linux x86-64, Windows, Android ou outro sistema, esse número não deve ser
tratado como um endereço virtual válido do processo.

Separar valor lógico de ponteiro host permite:

- detectar acessos fora do intervalo;
- preservar identidade de endereços quando ela for relevante para a lógica;
- executar em arquiteturas de 32 ou 64 bits;
- criar testes determinísticos;
- futuramente mapear regiões especiais sem depender do layout virtual do SO.

## Registro de overlays

O caminho portátil passa a possuir três slots iniciais:

```text
ENGINE
SCREEN
MAP
```

Cada `ShOverlayDescriptor` contém:

- ID estável;
- slot;
- nome;
- endereço PS1 lógico associado;
- tamanho da região;
- opção de limpar a região na ativação;
- callback `init`;
- callback `tick`;
- callback `shutdown`;
- `userdata` opaco.

Os callbacks representam código C já linkado à biblioteca. Portanto, ativar
um overlay no runtime portátil não significa copiar bytes de código e saltar
para uma região de RAM executável.

## Troca de overlay

Ao ativar um novo overlay em um slot:

1. o overlay ativo anterior recebe `shutdown`;
2. o slot é liberado;
3. a região lógica do novo overlay pode ser zerada;
4. o novo overlay torna-se ativo;
5. seu callback `init` é executado.

Se o `init` falhar, o slot fica vazio. O runtime não tenta executar rollback
implícito para o overlay anterior.

## Integração com ticks

A cada tick lógico de 60 Hz, overlays ativos são chamados na ordem:

```text
ENGINE -> SCREEN -> MAP
```

Depois disso, o callback de tick externo já existente no runtime é executado.
Essa ordem é deliberadamente simples nesta fase e poderá ser refinada quando
o `MainLoop` real for integrado.

## Segurança

A etapa adiciona validações para:

- ranges fora da RAM lógica;
- overflow de endereço;
- IDs duplicados;
- slots inválidos;
- nomes grandes demais;
- ativação de overlay inexistente;
- remoção de overlay ainda ativo;
- contadores de operações de memória.

Nenhum ponteiro para a RAM interna é exposto pela ABI pública.

## Limitações

Ainda não foram portados nesta etapa:

- `MainLoop` real;
- tabelas reais de overlays de mapas e telas;
- relocação de dados globais;
- GPU;
- SPU;
- streaming de CD;
- gameplay.

A etapa 07 deverá usar esta infraestrutura para construir uma máquina de
estados headless e começar a registrar módulos reais do jogo.
