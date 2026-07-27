# Portabilidade do Silent Hill

Este diretório documenta o segundo caminho de build do projeto: o runtime
portátil para futuros ports.

O build matching de PlayStation continua sendo a referência comportamental e
binária. A camada portátil não substitui o Makefile original e não inclui ROM,
BIOS ou assets proprietários.

## Documentos

- `ARCHITECTURE.md`: camadas e limites do runtime.
- `ABI_DRAFT.md`: primeiro rascunho da API C pública.
- `DECISIONS.md`: decisões arquiteturais aceitas.
- `MIGRATION_MATRIX.tsv`: subsistemas e estratégia de migração.
- `ROADMAP.md`: etapas principais do projeto.
