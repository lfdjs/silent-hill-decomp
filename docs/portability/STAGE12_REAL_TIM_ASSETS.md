# Etapa 12A — Primeiros assets reais: decodificacao PlayStation TIM

A implementacao esta em `ports/pc/` e **nao altera** o runtime PS1,
`portable/src/` ou a ABI publica 0.6.0. E um primeiro passo concreto
para remover placeholders do host PC.

## Origem dos assets

No codigo original, `GameState_Init_Update` solicita `FILE_1ST_KONAMI_TIM`
e `GameState_KonamiLogo_Update` solicita `FILE_1ST_KONAMI2_TIM`.
Esses arquivos sao extraidos do disco original pelo fluxo de `make setup`.
O patch NAO inclui ROM, imagens ou assets protegidos.

Localize o arquivo apos a extracao (a estrutura de pastas pode variar):

```bash
find assets/USA -type f -iname '*KONAMI*.TIM' -print
```

Execute a partir da raiz do repositorio:

```bash
cmake -S portable -B build-portable-stage12 -DBUILD_TESTING=ON -DSH_ENABLE_WERROR=ON
cmake --build build-portable-stage12 --parallel
ctest --test-dir build-portable-stage12 --output-on-failure

# Troque o caminho pelo encontrado no comando find.
./build-portable-stage12/silent-hill-tim --info assets/USA/1ST/KONAMI.TIM
./build-portable-stage12/silent-hill-tim --ppm assets/USA/1ST/KONAMI.TIM /tmp/konami.ppm
./build-portable-stage12/silent-hill-pc --konami-tim assets/USA/1ST/KONAMI.TIM --max-ticks 300
```

Na ausencia de X11, use `--headless` para validar o carregamento.

## Detalhes e limites

- O decoder reconhece cabecalho PS1 TIM, bloco CLUT e blocos de imagem,
  validando o comprimento de cada bloco. A primeira linha CLUT e usada.
- Modos de 4 e 8 bpp usam indices e CLUT; 16 bpp usa RGB555; 24 bpp
  interpreta triplas RGB por scanline. A representacao e ARGB32 no host.
- Os dados sao copiados para um buffer separado, sem modificar a imagem
  extraida. Imagens malformadas sao rejeitadas antes de serem desenhadas.
- A exibicao X11 e uma composicao 2D aproximada, **nao** GPU PS1. Nao ha
  ordering tables, semitransparencia STP, dither, VRAM ou CLUT animada.
- O asset carregado e exclusivamente o `--konami-tim` fornecido pelo host.
  Nao ha acesso a ROM ou arquivos originais por parte do core.
- O KCET segue nao implementado. Introducao, SPU, FMV, menus e gameplay
  ainda nao estao portados. Nao e uma versao jogavel.

## Validacao

`sh_tim_tests` usa buffers sinteticos validos e truncados nos quatro modos,
sem redistribuir graficos do jogo. O teste pode executar sob sanitizers.
A API permanece com os mesmos 49 simbolos de `sh_`.
