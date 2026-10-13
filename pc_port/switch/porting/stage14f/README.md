# Etapa 14F — PsyCross GLES3 Switch, checkpoint para continuar depois

**Escopo real:** Corrige a seleção do backend `__SWITCH__` no `PsyX_render.h` e o cabeçalho SDL no `platform.h` dentro de um **espelho externo**. Configura novamente a PsyCross e o jogo por ferramentas devkitPro, registrando os bloqueios seguintes. **Não entrega um `.nro` de Silent Hill jogável.**

Este pacote não modifica `pc_port/PsyCross` nem o código do port PC. A branch `playable/switch-experimental` preserva as alterações 14C condicionadas a `SH_SWITCH`. Também não contém os arquivos de disco de Silent Hill nem SDK proprietário.

## Comandos (em ordem, separados)

1. `bash ~/Downloads/stage14f-switch-gles-checkpoint/00_INSTALAR_NO_REPOSITORIO.sh`
2. `python3 "$REPO/pc_port/switch/porting/stage14f/prepare_overlay.py"` (substitua `$REPO` pelo caminho do clone ou defina a variável)
3. `bash "$REPO/pc_port/switch/porting/stage14f/02_configurar_arm64.sh"`
4. `bash "$REPO/pc_port/switch/porting/stage14f/03_compilar_psycross.sh"`
5. `bash "$REPO/pc_port/switch/porting/stage14f/04_configurar_jogo.sh"`
6. `bash "$REPO/pc_port/switch/porting/stage14f/05_compilar_jogo.sh"`
7. `bash "$REPO/pc_port/switch/porting/stage14f/06_relatorio.sh"` (sempre, inclusive quando build falhar)
8. `bash "$REPO/pc_port/switch/porting/stage14f/07_checkpoint_github.sh"` (somente após inspecionar o Git; faz commit/push seguro)

Os comandos de compilação podem falhar por funcionalidades ainda não portadas; use o script 06 para coletar o primeiro bloqueio e, mesmo assim, salvar o checkpoint no GitHub com o script 07. O build explora compatibilidade de fontes, **não configura automaticamente um launcher NRO com gameplay**.

O script 07 adiciona arquivos de código e documentação por **lista explícita**, nunca `git add .`, não publica `.nro`, `.elf`, `.bin` ou `.cue`, não usa force push e aborta se o remoto tiver avançado. Só execute após conferir `git diff` e `git status`. Se o push falhar, o commit fica disponível localmente.

O perfil Switch de 720p handheld/1080p dock, alvo de 60 FPS e PC Options oculto foi preparado na 14C, mas requer backend gráfico funcional e testes no jogo completo. PGXP está desligado no build PC porque a configuração de compilação `USE_PGXP=0` evita regressões; `msaa=8` a 1080p não pode ser garantido a 60 FPS.
