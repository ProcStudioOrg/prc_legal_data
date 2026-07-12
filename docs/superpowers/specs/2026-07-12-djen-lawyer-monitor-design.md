# DJEN Lawyer Monitor — Design Spec

Date: 2026-07-12
Status: Approved (user, 2026-07-12)
Research source: `/Users/brpl/code/ProcStudio/prc_djean` (ARQUITETURA.md, bruno-DJEN collection, PROMPT-endpoint-intimacoes.md)

## Goal

prc_legal_data becomes the DJEN monitor for ProcStudio. ProcStudio tells legal_data
"watch this lawyer"; legal_data sweeps the DJEN public API (comunicaapi.pje.jus.br)
daily for every watched lawyer (principal + supplementary OABs) and pushes new and
cancelled intimações to ProcStudio's ingestion endpoint
(`POST /api/v1/integracoes/djen/intimacoes`, Bearer `INTEGRATION_DJEN_TOKEN`,
branch `intimacoes-endpoint-frontend`, considered done).

Scope is lawyer fetch only. Out of scope (postponed): caderno bulk ingestion,
search by customer/parte, prazo calculation, push notifications.

## Decisions (all confirmed by user)

| Topic | Decision |
|---|---|
| Delivery | legal_data pushes batches to ProcStudio's specced endpoint |
| Cadence | Daily sweep, 7-day lookback window |
| Onboarding backfill | 60 days |
| Storage | Ledger + raw DJEN JSON per comunicação |
| Watch model | `DjenMonitoring` (dedicated table, not `is_procstudio`) |
| Supplementary OABs | Watch attaches to principal; sweep queries every OAB (principal + supplementaries); results dedup by `djen_id` |
| Disambiguation | Learn national `djen_advogado_id` per lawyer row from first response; log loudly on mismatch |
| Labels (etiquetas) | `novo_processo`, `processo_conhecido`, `ambiguo` — computed at sweep, sent as `etiquetas` per item |
| Rate limit | Staggered per-lawyer jobs + Redis token/spacing limiter driven by `x-ratelimit-remaining` headers + 429/5xx backoff. Single egress IP, nothing hardcoded |

## Data model

```
djen_monitorings
  lawyer_id       FK -> lawyers, unique (always the PRINCIPAL lawyer)
  active          boolean, default true   -- pause without losing history
  source          string, default "procstudio"  -- future: paid tiers, other products
  last_swept_at   datetime
  onboarded_at    datetime               -- when the 60-day backfill finished
  timestamps

djen_comunicacoes
  djen_monitoring_id       FK
  djen_id                  bigint, unique  -- official DJEN id (dedupe key)
  djen_hash                string          -- for certidão PDF later
  numero_processo          string
  sigla_tribunal           string
  data_disponibilizacao    date
  ativo                    boolean, default true
  labels                   jsonb []        -- etiquetas
  raw                      jsonb           -- full DJEN item, untransformed
  pushed_at                datetime        -- "nova" delivered to ProcStudio
  cancellation_pushed_at   datetime        -- "cancelada" delivered
  timestamps

lawyers + djen_advogado_id bigint, indexed
  -- learned per lawyer ROW (principal and each supplementary learn their own,
  --  so we can observe whether supplementary OABs share the national id)
```

## API (X-API-KEY auth, write ops require admin key)

```
POST   /api/v1/djen/monitorings         { "oab": "PR_54159" }
       -> resolves supplementary to principal; creates or reactivates the watch;
          enqueues Djen::OnboardJob; 201 (created) / 200 (already active)
GET    /api/v1/djen/monitorings/:oab    -> status, djen_advogado_id, monitored_oabs,
                                           last_swept_at, comunicacoes counts
DELETE /api/v1/djen/monitorings/:oab    -> active: false (never deletes history)
```

Lawyer must already exist in legal_data (404 otherwise — ProcStudio registers
lawyers via the existing lawyer endpoints first).

## Jobs (solid_queue)

- `Djen::OnboardJob(monitoring)` — sweep 60 days, set `onboarded_at`, push lote.
- `Djen::DailySweepJob` — recurring (config/recurring.yml, early morning
  America/Sao_Paulo): enqueue one `Djen::SweepLawyerJob` per active monitoring,
  staggered by `DJEN_SWEEP_STAGGER_SECONDS` (default 120s) to spread requests
  across the day.
- `Djen::SweepLawyerJob(monitoring, window_days: 7)` — sweep + push; retries with
  polynomial backoff on client errors.

## Services (one responsibility per file, app/services/djen/)

- `Djen::Client` — GET `/api/v1/comunicacao?numeroOab&ufOab&dataDisponibilizacaoInicio&Fim`,
  paginate (itensPorPagina=100, stop on empty page — never trust `count`),
  429 -> sleep 60s+jitter and retry, 5xx -> exponential backoff, all requests pass
  through the rate limiter.
- `Djen::RateLimiter` — Redis-backed global spacing (min interval between requests
  across all jobs) + cooldown driven by `x-ratelimit-remaining` response headers.
  Degrades gracefully (logs + no-op) if Redis is unavailable.
- `Djen::Sweep` — for one monitoring: collect OAB/UF pairs (principal +
  supplementaries), query each over the window, upsert ledger rows, compute labels,
  detect cancellations (ativo true->false), learn djen_advogado_id.
- `Djen::AdvogadoIdLearner` — extract the national advogado id matching the queried
  OAB/UF from `destinatarioadvogados[]`; persist on first sight; warn on mismatch
  (feeds the `ambiguo` label).
- `Djen::LoteBuilder` — build the batch payload exactly per
  PROMPT-endpoint-intimacoes.md (evento nova/cancelada, texto raw, + etiquetas).
- `Djen::ProcstudioPusher` — POST lote with Bearer token; on 2xx stamp
  `pushed_at` / `cancellation_pushed_at`. At-least-once delivery: unstamped rows are
  re-sent next sweep; ProcStudio's endpoint is idempotent by djen_id.

## Push semantics

- nova: `pushed_at IS NULL`
- cancelada: `pushed_at NOT NULL AND ativo = false AND cancellation_pushed_at IS NULL`
- never pushed but already cancelled -> sent once as nova with `ativo: false`
  (both stamps set)
- lote skipped entirely when there is nothing to send

## Config (dotenv)

- `DJEN_BASE_URL` (default https://comunicaapi.pje.jus.br)
- `PROCSTUDIO_BASE_URL`
- `INTEGRATION_DJEN_TOKEN`
- `DJEN_SWEEP_STAGGER_SECONDS` (default 120)
- `REDIS_URL`

## Error handling

- DJEN unreachable: job retries (solid_queue); `last_swept_at` not advanced; the
  7-day lookback covers gaps.
- ProcStudio push failure: raises -> job retry; rows stay unstamped.
- Inflection: `comunicacao -> comunicacoes` registered in
  config/initializers/inflections.rb.

## Testing

RSpec + webmock (test group). Fixtures derived from real DJEN payloads in the
research repo. Coverage: models, request specs (auth, idempotency, supplementary
resolution), client pagination/backoff, sweep (labels, cancellation, id learning),
lote builder contract, pusher stamping.
