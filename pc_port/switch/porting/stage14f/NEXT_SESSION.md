# Silent Hill Switch — checkpoint 14F (retomada)

**Branch:** `playable/switch-experimental` (fork `lfdjs/silent-hill-decomp`)
**Base:** `bd8d8842f6aeeb38659c21c190857120dd19236c`
**Linha PC funcional:** `playable/psycross-pilot`, commit `e6a39b877425585f8c79ba173345d987aa13e386`, **NÃO ALTERAR**.
**Runtime portátil anterior:** `portability/core-api`, também separado.

## Validado pelo usuário no Ryubing Snap (NVIDIA Vulkan)
- Framebuffer libnx: faixas RGB e quadrado em movimento exibidos.
- `src/main/rng.c` e `src/main/memmove32.c`: PASS real ARM64 (Etapa 14B.1).
- Decodificador TIM: imagem DEMO.TIM exibida em ARM64 (Etapa 14B.2).
- Acesso `sdmc:/`: log `probe.log` gravado em execução anterior.

## Ainda NÃO validado
- Nenhum `.nro` contém o gameplay completo.
- PsyCross GLES3 Switch/renderer/context lifecycle, SPU/CD/SDL no ambiente Switch, todos os mapas ARM64 vinculados, BODYPROG completo, menu de jogo, saves e cenas FMV.
- PGXP desativado em tempo de compilação pelo port de referência (regressões), 60 FPS e MSAA dependem de medição.

## Último bloqueio (Etapa 14E)
- Configuração CMake da PsyCross e do jogo: PASS.
- `SH_STATIC_MAPS` registrou 43 overlays; 37 estavam compilados na última inspeção.
- `PsyX_render.h`: `#error` porque `__SWITCH__` não selecionava nenhum renderer; `TextureID`/`ShaderID` não eram definidos.
- Etapa 14F aplica **apenas no espelho externo** uma seleção `RENDERER_OGLES/OGLES_VERSION(3)`; é um avanço de compilação, **não uma implementação pronta do backend gráfico**.

## Reproduzir em nova sessão
Na branch Switch, após baixar/extrair o ZIP 14F (ou atualizar o fork), definir:

```bash
export SH_PILOT_ROOT="$HOME/Documentos/projetos_decompilacao/_silent_hill_playable_pilot"
export SH_REPO="$SH_PILOT_ROOT/source-20261012T230037Z"
F="$SH_REPO/pc_port/switch/porting/stage14f"
python3 "$F/prepare_overlay.py"
bash "$F/02_configurar_arm64.sh"
bash "$F/03_compilar_psycross.sh"
bash "$F/04_configurar_jogo.sh"
bash "$F/05_compilar_jogo.sh"
bash "$F/06_relatorio.sh"
```

Os builds podem falhar. Ao recomeçar, **inspecionar primeiro erro real** nos logs de `switch-14f-logs` e prosseguir incrementalmente. O pacote não inclui ROM ou dados da Konami; a imagem `pc_port/Nintendo_SH1.png` já existe no port de referência para futuro menu de controles.
