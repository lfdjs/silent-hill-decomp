# Etapa 09 — Host PC de diagnóstico (Linux/X11)

## Escopo efetivamente implementado

- `silent-hill-pc`: executável host separado do `silent_hill_core`.
- `--headless --fast --max-ticks N`: CI e testes sem servidor gráfico.
- Janela X11 opcional no Linux, sem afetar o build matching do PS1.
- Teclado: setas/WASD, Enter, Espaço, Shift; Esc fecha a janela.
- Consumo total por tick das filas de apresentação e áudio da ABI 0.6.
- Texto e placeholders gráficos que deixam claro que os recursos originais não estão carregados.
- Transições determinísticas de BOOT a KONAMI e KCET, interrompendo em KCET não implementado.
- Métricas de ticks, frames, comandos e tarefas 160/162.

## Compilação

```bash
cmake -S portable -B build-portable-pc -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build build-portable-pc --parallel
ctest --test-dir build-portable-pc --output-on-failure
./build-portable-pc/silent-hill-pc --headless --fast --max-ticks 300
./build-portable-pc/silent-hill-pc --max-ticks 300
```

Caso X11 não esteja presente na etapa de configuração, a ferramenta ainda
pode ser compilada no modo headless, mas a janela não ficará disponível.
Para janela no Debian/Ubuntu: instale `libx11-dev` e reconfigure o CMake.
O teste de janela em ambiente sem desktop pode utilizar `xvfb-run`.

## Limites deliberados

**Este não é um jogo jogável.** Não desenha texturas reais nem executa
primitivas/order tables do PS1; o texto KONAMI é ilustrativo. As tarefas de
áudio são apenas consumidas e registradas; não há SPU/mixer nem som reproduzido.
A lógica das condições de fade e da fila de arquivos no host é uma simulação
controlada para diagnóstico, não um sistema real de assets. Também não há
persistência de savegame, gamepad, FMV ou gameplay. Não se deve usar este
marco para afirmar que o port está completo.

## Atualizações upstream

A Etapa 09 se aplica ao checkpoint da branch portátil após a Etapa 08. O
upstream oficial recebeu novas mudanças e requer sincronização separada e
validação do matching antes da conclusão do roteiro.
