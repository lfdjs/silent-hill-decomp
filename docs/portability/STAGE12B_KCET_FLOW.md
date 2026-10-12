# Etapa 12B — KCET de referência, opt-in

Esta etapa porta a lógica de controle verificável de `GameState_KcetLogo_Update`
(`src/screens/b_konami/b_konami.c`) no runtime nativo. **Não** implementa
memory cards, FMV, overlays STREAM ou menu. O host fornece os resultados
desses subsistemas através de `ShGameKcetSignals`, API experimental 0.7.0.

## Estados e rotas

- `Init` (0): restaurar configurações, iniciar fade-in, solicitar assets;
- `CheckMemCards` (1): esperar fade e fila vazia; escolher rota;
- `NoMemCard` (2): imagem de aviso + STREAM -> `MovieIntroFadeIn` (3);
- `NoMemCardFreeSpace` (3): aviso + STREAM -> `MovieIntroFadeIn` (3);
- `NoSavegame` (4): STREAM + busca de título -> `MovieIntro` (6);
- `HasSavegame` (5): **parada explícita**; autoload ainda não portado;
- `LogoDelay` (6): input ou mais de 180 ticks; fade-out;
- `FinishAfterFade` (7): aguardar fade e arquivos; display 320x240;
  emitir transição para o estado selecionado.

O fluxo acima corresponde às condições e transições originais; os sinais de
fade/arquivos/cartão são **sintéticos no runner PC** e não comprovam que os
subsistemas PS1 estejam executando. `--kcet` habilita a referência apenas
quando solicitado. Sem ele, o runner mantém o trace anterior e termina em KCET.

```bash
cmake -S portable -B build-pc -DBUILD_TESTING=ON
cmake --build build-pc --parallel
ctest --test-dir build-pc --output-on-failure
./build-pc/silent-hill-pc --headless --fast --kcet --max-ticks 500
./build-pc/silent-hill-pc --headless --fast --kcet --kcet-card no-save --max-ticks 500
./build-pc/silent-hill-pc --kcet --konami-tim assets/USA/1ST/KONAMI.TIM \
  --kcet-tim assets/USA/1ST/KONAMI2.TIM --max-ticks 500
```

A última linha usa o caminho do asset original como exemplo; localize o
arquivo real no seu sistema. A nova renderização X11 mostra o KCET TIM
quando fornecido, sem GPU PS1, VRAM, OT ou fades reproduzidos.

## Limites

- Não existe varredura de cartão real nem gerenciamento de savegame;
- não existe carregamento verdadeiro dos recursos de KCET, STREAM ou título;
- intro/MovieIntroFadeIn são próximos estados **não implementados**;
- nenhuma tela de menu ou gameplay é executada;
- o build original PS1 permanece isolado e deve preservar 50/50.
