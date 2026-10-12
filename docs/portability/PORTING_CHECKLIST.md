# Checklist de preparação de uma plataforma

Este checklist cobre a **infraestrutura portátil experimental**, não a
execução completa do jogo.

## Build

- [ ] C11, ponteiros/inteiros e convenções de chamadas da plataforma auditados
- [ ] `SH_BUILD_PC_RUNNER=OFF` e `SH_BUILD_PORT_TEMPLATE=ON` compilam
- [ ] Testes nativos do core e smoke do template passam
- [ ] ABI 0.6 mantém exatamente os 49 exports planejados

## Integração

- [ ] Relógio monotônico do host e política de suspensão integrados
- [ ] Botões, controle analógico, desconexão e foco da janela integrados
- [ ] Paths e leitura de assets com validação de tamanho e limites
- [ ] Saves com persistência/transação apropriados à plataforma
- [ ] Comandos de apresentação drenados a cada frame/tick
- [ ] Comandos de áudio drenados sem assumir que tarefas SPU são amostras PCM
- [ ] Feedback real de fade/carregamento substitui sinais sintéticos do template
- [ ] Descarregamento de overlays e destruição ordenada do runtime validados

## Conteúdo ainda pendente de port

- [ ] Renderer PS1, primitivas e ordering tables
- [ ] Decodificação real dos assets de vídeo e modelos
- [ ] Driver/mixer de áudio SPU e músicas
- [ ] CD/streaming e vídeos FMV
- [ ] KCET, introdução, menu principal, gameplay, mapas e eventos
- [ ] Smoke com controlador e janela em máquina real

Não copie assets comerciais para o repositório. Use dumps próprios, verificações
locais de integridade e instruções de extração documentadas.
