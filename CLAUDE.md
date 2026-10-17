# prc_legal_data

Rails 8, API-only. Registro de advogados (OAB), sociedades e monitoramento DJEN.

## Regras de negócio

- **Principal x suplementar**: um advogado pode ter várias inscrições OAB, todas apontando para um único `principal_lawyer`. Qualquer OAB do cluster resolve para o principal — nunca trate uma suplementar como pessoa separada.
- **Auth**: toda rota exige `X-API-KEY`, exceto `/api/v1/version` e `/up`. Key `admin` escreve; `read` só GET.
- **DJEN**: um monitoramento por pessoa, sempre no principal. `POST /djen/monitorings` é idempotente e é a **exceção à regra de auth** — qualquer key ativa pode ativar (o ProcStudio só tem key `read`, uma por ambiente). Cada key que ativa vira assinante (`djen_monitoring_subscribers`); `DELETE` com key `read` tira só a assinatura dela e o monitoramento pausa quando não sobra assinante (um consumidor nunca pausa o de outro); key que não assina recebe 403; `admin` pausa direto. Monitoramento sem assinantes (anterior a 17/10/2026) lê os assinantes do `api_logs` (POSTs 200/201). A base raspada é informativa: OAB válida fora dela (scraper atrasado) é monitorada pela própria OAB (`djen_monitorings.oab_id`, sem `lawyer_id`) e continua sendo esse o monitoramento quando o scraper alcançar; religar ao `Lawyer` é decisão pendente (PRC-1202).
- Mensagens de erro voltam em pt-BR.

## DJEN
- Issue de cancelamento: Não é tão preocupante não saber os cancelamentos. A janela da varredura diária é de **15 dias** (`SweepLawyerJob::DAILY_WINDOW_DAYS`); cancelamentos fora dela são risco aceito — raramente ocorrem, não há riscos a partir deste ponto.
- **Entrega multi-destino**: cada comunicação vai para TODOS os ProcStudios de `PROCSTUDIO_DESTINATIONS` (`base_url|token,...`; legado: `PROCSTUDIO_BASE_URL` + `INTEGRATION_DJEN_TOKEN`), com carimbo por destino em `djen_deliveries` (`DjenDelivery`). "Pendente" é sempre em relação a um destino (`pending_push_to`). Destino novo recebe o ledger inteiro na próxima varredura — `rake djen:deliveries:mark_delivered[url]` evita isso; `rake djen:deliveries:reset[url,OAB]` força o reenvio de um advogado. Um destino fora do ar não segura os outros (o erro sobe depois de entregar aos saudáveis).
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
- **DELETE /djen/monitorings vs key read**: resolvido em 17/10/2026 (assinatura por key, ver regra DJEN). HML e produção usam keys `read` distintas — nunca compartilhar a key entre ambientes, senão o desligar de um pausa o outro.
- **GET /api/v1/djen/monitorings (index)**: listar OABs ativas da key, para o job de reconciliação do ProcStudio (handoff 2026-07-13, questão 4).
- **Dedupe por time no ProcStudio**: `djen_intimacoes` tem unique global em `djen_id`; precisa ser por time (`[team_id, djen_id]`) e marcar todos os advogados do time citados via array `advogados` — hoje a intimação fica com o primeiro advogado entregue e some para o segundo.

