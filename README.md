# Legal Data API

## Setup

```bash
bundle install
bin/rails db:create db:migrate
```

### Create user and API keys

```bash
bundle exec rake db:seed_user
```

This creates an admin user with two API keys: one **admin** (full CRUD) and one **read-only** (GET only).

### API Key Management

```bash
# List all active keys
bundle exec rake api_keys:list

# Create a read-only key
bundle exec rake api_keys:create_read[user@example.com]

# Create an admin key
bundle exec rake api_keys:create_admin[user@example.com]

# Rotate all keys for a user (deactivates old, creates new with same roles)
bundle exec rake api_keys:rotate[user@example.com]

# Rotate keys for all users
bundle exec rake api_keys:rotate
```

## Authentication & Authorization

All endpoints require an API key in the `X-API-KEY` header:

```
X-API-KEY: your_api_key_here
```

### API Key Roles

| Role | Permissions | Use case |
|------|-------------|----------|
| `admin` | Full CRUD (GET, POST, PUT, PATCH, DELETE) | Scraping, data ingestion, management |
| `read` | Read-only (GET) | Application frontend, public queries |

A read-only key attempting a write operation receives `403 Forbidden`.

## Endpoints

### Version & Health

Both are **public** — no `X-API-KEY` required.

```
GET /api/v1/version   # Deployed version, commit SHA, and full changelog
GET /up               # Liveness probe (Rails health check)
```

```json
{
  "version": "1.2",
  "released_at": "13/07/2026",
  "note": "Monitoramento DJEN: onboarding de advogados, varredura diária e push para o ProcStudio",
  "pr": null,
  "commit": "7cb45fe",
  "branch": "main",
  "deployed_at": "2026-07-13T18:04:11Z",
  "environment": "production",
  "changelog": [ ... ]
}
```

The human version and changelog come from `config/changelog.yml`. `commit`, `branch`, and `deployed_at` come from the `REVISION` file stamped by `infra/deploy.sh` (git-ignored; absent in dev, where `commit` falls back to local git HEAD). See [Versioning](#versioning).

### Lawyer Endpoints

#### Individual lookup

```
GET  /api/v1/lawyer/:oab              # Lookup by OAB ID (e.g. PR_54159)
GET  /api/v1/lawyer/:oab/debug        # Extended debug info
GET  /api/v1/lawyer/state/:state/last # Last registered lawyer by state
POST /api/v1/lawyer/create            # Create lawyer (admin only)
POST /api/v1/lawyer/:oab/update       # Update lawyer (admin only)
POST /api/v1/lawyer/:oab/crm          # Update CRM data (admin only)
```

**Principal + supplementary resolution.** A lawyer registered in multiple state sections (a *suplementar* inscription) is linked in the DB to a single principal record. `GET /api/v1/lawyer/:oab` always responds with both:

```json
{
  "principal":       { "oab_id": "CE_16477", "full_name": "DAVID SOMBRA PEIXOTO", ... },
  "supplementaries": [ { "oab_id": "SP_388253", ... }, { "oab_id": "RJ_185026", ... } ]
}
```

- Fetching any OAB in a cluster — principal or any supplementary — returns the same payload.
- Clusters are produced offline by a face-match batch run (`rake lawyers:link_face_matches`). Newly scraped supplementaries remain unlinked until the batch is re-run, and are returned as their own `principal` with an empty `supplementaries` array.

#### Batch (scraper ingestion)

```
GET /api/v1/lawyers?state=PR&limit=100&from_oab=<n>&scraped=false
```

Cursor-paginated list of lawyers filtered by state. Intended for the scraper pipeline.

| Param      | Description                                                                 |
|------------|-----------------------------------------------------------------------------|
| `state`    | **Required.** 2-letter UF (one of the 27 Brazilian states).                 |
| `limit`    | 1–100, default 50.                                                          |
| `from_oab` | Numeric cursor. Returns lawyers with `oab_number < from_oab` (sorted desc). |
| `scraped`  | `false` filters out lawyers already CRM-scraped.                            |

Response:

```json
{
  "lawyers": [ ... ],
  "meta": { "returned": 100, "state": "PR", "from_oab": null, "next_from_oab": "519174" }
}
```

#### CRM

Supports the AI scraper → `prc_legal_data` → CRM ingester flow. CRM data lives in the `crm_data` JSONB column.

```
GET  /api/v1/lawyer/:oab/crm   # Token-lean payload for the AI scraper (nulls stripped, partners capped at 6)
POST /api/v1/lawyer/:oab/crm   # Write CRM data (admin only)
GET  /api/v1/lawyers/crm       # CRM ingester listing, cursor-paginated
```

`POST` accepts nested `scraper` / `outreach` / `signals` hashes and deep-merges them into `crm_data`, so a partial write never clobbers untouched keys. Flat legacy fields still work.

`GET /api/v1/lawyers/crm` filters (all optional; excludes ProcStudio-owned lawyers and supplementaries):

| Param            | Description                                              |
|------------------|----------------------------------------------------------|
| `state`          | 2-letter UF.                                             |
| `limit`          | 1–100, default 50.                                       |
| `from_oab`       | Numeric cursor (`oab_number < from_oab`, sorted desc).   |
| `scraped`        | `true` returns only lawyers already scraped.             |
| `stage`          | Filters `crm_data.outreach.stage`.                       |
| `min_lead_score` | Numeric floor on `crm_data.scraper.lead_score`.          |
| `has_instagram`  | `true` returns only lawyers with an Instagram handle.    |
| `has_website`    | `true` returns only lawyers with a website.              |

### DJEN Monitoring Endpoints

Watches the Diário de Justiça Eletrônico Nacional for a lawyer's publications. ProcStudio onboards a lawyer here; a daily sweep pulls new *comunicações* and pushes them back to ProcStudio.

```
POST   /api/v1/djen/monitorings       # Start watching (any active key) — body: { "oab": "PR_54159" }
GET    /api/v1/djen/monitorings/:oab  # Watch status
DELETE /api/v1/djen/monitorings/:oab  # Pause watching (admin only) — history is kept
```

**Auth here is deliberately asymmetric.** ProcStudio holds only a read key, so *starting* a watch is allowed to any active key. *Pausing* one stays admin-only — silently stopping a watch means missed intimações.

Any OAB in a lawyer's cluster (principal **or** supplementary) resolves to the principal, so one person can never end up with two watches. `POST` is idempotent: re-activating an existing watch returns `200` instead of `201`.

```json
{
  "oab_id": "PR_54159",
  "full_name": "FULANO DE TAL",
  "active": true,
  "source": "procstudio",
  "djen_advogado_id": 123456,
  "monitored_oabs": ["PR_54159", "SP_388253"],
  "last_swept_at": "2026-07-13T06:00:00Z",
  "onboarded_at": "2026-07-01T12:30:00Z",
  "comunicacoes": { "total": 42, "pending_push": 3, "cancelled": 1 }
}
```

### Society Endpoints

```
GET    /api/v1/society/:inscricao        # Lookup by inscricao
POST   /api/v1/society/create            # Create society (admin only)
POST   /api/v1/society/:inscricao/update # Update society (admin only)
DELETE /api/v1/society/:inscricao        # Delete society (admin only)
```

### Lawyer-Society Relationship Endpoints

```
GET    /api/v1/lawyer_societies/:id   # Show relationship
POST   /api/v1/lawyer_societies       # Create relationship (admin only)
PATCH  /api/v1/lawyer_societies/:id   # Update relationship (admin only)
DELETE /api/v1/lawyer_societies/:id   # Delete relationship (admin only)
```

## Versioning

Two independent numbers, both served by `GET /api/v1/version`:

- **Commit SHA** — stamped automatically at deploy time. Nothing to maintain.
- **Human version** (`1.2`) — the top entry of `config/changelog.yml`. Maintained by hand.

Every PR that changes public API behaviour **must** add an entry to the top of `config/changelog.yml`:

```yaml
- version: "1.3"
  date: "20/07/2026"
  note: "Uma linha em pt-BR descrevendo a mudança"
  pr: "https://github.com/ProcStudioOrg/prc_legal_data/pull/12"
```

The AI agent writes the entry as part of the PR it ships (see `CLAUDE.md`); the human reviews it in the diff. Bump the minor for new endpoints or fields, the major for breaking changes. `pr` may be empty when a change lands without a PR.

## Security

- **Authentication**: API key via `X-API-KEY` header
- **Authorization**: Role-based (admin/read) enforced at controller level
- **Rate limiting, IP blocking, CORS, SSL, security headers**: Handled by NGINX
