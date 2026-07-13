# prc_legal_data

Rails 8, API-only. Registro de advogados (OAB), sociedades e monitoramento DJEN.

## Regras de negócio

- **Principal x suplementar**: um advogado pode ter várias inscrições OAB, todas apontando para um único `principal_lawyer`. Qualquer OAB do cluster resolve para o principal — nunca trate uma suplementar como pessoa separada.
- **Auth**: toda rota exige `X-API-KEY`, exceto `/api/v1/version` e `/up`. Key `admin` escreve; `read` só GET.
- **DJEN**: um monitoramento por pessoa, sempre no principal. `POST /djen/monitorings` é idempotente e é a **exceção à regra de auth** — qualquer key ativa pode ativar (o ProcStudio só tem key `read`); pausar (`DELETE`) continua `admin`, pois pausar em silêncio significa intimação perdida.
- Mensagens de erro voltam em pt-BR.

## DJEN
- Issue de cancelamento: Não é tão preocupante não saber os cancelamentos. A janela da varredura diária é de **15 dias** (`SweepLawyerJob::DAILY_WINDOW_DAYS`); cancelamentos fora dela são risco aceito — raramente ocorrem, não há riscos a partir deste ponto.
- **Entrega multi-advogado**: uma comunicação que cita 2+ advogados monitorados vira uma linha no ledger **por monitoramento** (unique `[djen_monitoring_id, djen_id]`) e é enviada uma vez no lote de cada `advogado_monitorado`. Dedupe/atribuição por time é responsabilidade do ProcStudio (usar o array `advogados` do payload).

## Versionamento (obrigatório)

Toda PR que muda o comportamento público da API adiciona uma entrada no topo de `config/changelog.yml` (`version`, `date` dd/mm/yyyy, `note` em pt-BR, `pr`). Minor para endpoint/campo novo, major para quebra. O commit SHA vem do deploy — não mexer.

## Arquivos centrais

- `config/routes.rb` — superfície da API
- `app/controllers/concerns/api_authentication.rb` — auth, roles, ApiLog
- `app/models/lawyer.rb` — cluster principal/suplementar
- `app/services/djen/` — client, sweep, push para o ProcStudio
- `infra/deploy.sh` — deploy + stamp do REVISION

## TODO
- **Etiquetas cross-repo**: contrato atualizado em `prc_djean/PROMPT-endpoint-intimacoes.md` (campo `etiquetas` + semântica de "nova" com `ativo=false`). Falta o lado ProcStudio: `Djen::IngestBatchService::CAMPOS_INTIMACAO` descarta `etiquetas` hoje — persistir (coluna/migração) e exibir como badges.
- **DELETE /djen/monitorings vs key read**: o toggle "desligar" do ProcStudio chama DELETE com a key `read` e recebe 403 (admin-only por design) — o flag local desliga, mas o legal_data segue varrendo e empurrando. Decidir: filtrar exibição no ProcStudio (guard local) x refcount por consumidor aqui x relaxar auth do DELETE.
- **GET /api/v1/djen/monitorings (index)**: listar OABs ativas da key, para o job de reconciliação do ProcStudio (handoff 2026-07-13, questão 4).
- **Dedupe por time no ProcStudio**: `djen_intimacoes` tem unique global em `djen_id`; precisa ser por time (`[team_id, djen_id]`) e marcar todos os advogados do time citados via array `advogados` — hoje a intimação fica com o primeiro advogado entregue e some para o segundo.

