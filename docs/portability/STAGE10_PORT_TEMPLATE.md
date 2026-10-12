# Etapa 10 — Template de ports e validação cruzada

A Etapa 10 conclui a **primeira arquitetura experimental** do projeto, não o
port jogável de Silent Hill. Ela introduz `ports/platform-template` como
referência de integração independente de biblioteca de janela, renderer ou SPU.

## Contrato mínimo para hosts

1. Inicialize `ShPortTemplate port = {0}` e `ShPortHooks hooks = {0}`.
2. Configure `hooks.poll_buttons` para os botões digitais atuais; os valores de
   `ShInputButtons` são os mesmos do core portátil.
3. Configure `hooks.on_video` para receber comandos de apresentação; o host deve
   efetivamente desenhar, produzir buffers e tratar os fades no futuro.
4. Configure `hooks.on_audio` para receber comandos de áudio; `TASK` não contém
   PCM e **não** é reprodução SPU.
5. Configure `hooks.on_transition` opcionalmente para depuração.
6. Chame `sh_port_template_init`, depois `sh_port_template_tick` uma vez por
   tick de simulação. No exemplo, `sh_runtime_step` avança exatamente um tick;
   um host real deve adaptar seu relógio/pausa às APIs do core.
7. Ao sair, chame `sh_port_template_destroy` (idempotente).

O exemplo usa sinais **sintéticos** de fade, carregamento e áudio que reproduzem
apenas o caminho de diagnóstico `Init/Boot -> KonamiLogo -> KcetLogo`.
Substitua-os pelo estado verdadeiro dos subsistemas antes de tentar portar o
restante do jogo. Nenhuma implementação de KCET, FMV, menu ou gameplay é criada.
Os callbacks são síncronos e não devem destruir o runtime durante `tick`.

## Compilar sem interface gráfica

```bash
cmake -S portable -B build-template \
  -DBUILD_TESTING=ON \
  -DSH_BUILD_PC_RUNNER=OFF \
  -DSH_BUILD_PORT_TEMPLATE=ON \
  -DSH_ENABLE_WERROR=ON
cmake --build build-template --parallel
ctest --test-dir build-template --output-on-failure
./build-template/silent-hill-port-template
```

O template pode ser reutilizado em Linux, Windows e Android NDK, desde que o
compilador suporte C11 e as dependências nativas do destino sejam implementadas
no **host**, nunca em `portable/src`.

## Critérios de conclusão da etapa

- compilação C11 com `-Werror` quando disponível;
- testes existentes sem regressão;
- dois novos testes (`sh_port_template_tests` e smoke CLI);
- conjunto de testes sem host PC/X11;
- sanitizer no ambiente Linux;
- exportação da ABI `0.6.0` inalterada (49 símbolos);
- matching PS1 não afetado (50 checksums, na máquina do projeto);
- commit e publicação na branch portátil;
- sincronização upstream tratada como procedimento separado.
