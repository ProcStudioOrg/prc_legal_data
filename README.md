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

**Destinos de entrega.** Cada comunicação é entregue a *todos* os ProcStudios configurados, com carimbo por destino (`djen_deliveries`), então HML e produção coexistem sem um roubar a intimação do outro:

```
PROCSTUDIO_DESTINATIONS="https://api-hml.procstudio.com.br|<token hml>,https://api.procstudio.com.br|<token prod>"
```

Sem essa variável vale o par legado `PROCSTUDIO_BASE_URL` + `INTEGRATION_DJEN_TOKEN` (um destino só). O destino é identificado pela `base_url` normalizada: trocar a URL equivale a criar um destino novo. Um destino recém-adicionado recebe **todo o ledger** de todos os monitoramentos na próxima varredura; para começar só com o que vier daqui em diante, ou para reenviar o histórico de um advogado:

```
bundle exec rake "djen:deliveries:mark_delivered[https://api.procstudio.com.br]"   # carimba o histórico como entregue
bundle exec rake "djen:deliveries:reset[https://api.procstudio.com.br,PR_54159]"   # próxima varredura reenvia o ledger dele
```

`comunicacoes.pending_push` no status abaixo conta o que ainda falta em **pelo menos um** destino.

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
POST   /api/v1/society/:inscricao/crm    # Write CRM data (admin only)
DELETE /api/v1/society/:inscricao        # Delete society (admin only)
```

**Two identifiers, one param.** The `:inscricao` segment accepts either the OAB
registration number (numeric, sourced from the CNA) or the `oab_id` in the
`MG_<ordem>_SOCIEDADE` form. Societies discovered through the OAB-MG portal have
no registration number — the portal does not expose it — so they are reached by
`oab_id`.

**CRM.** Societies carry the same `crm_data` JSONB column as lawyers, and
`POST /api/v1/society/:inscricao/crm` behaves exactly like its lawyer counterpart:
nested `scraper` / `outreach` / `signals` hashes are deep-merged, so a partial
write never clobbers untouched keys.

`crm_data` is deliberately separate from `cnpja_data`. The latter holds the raw
Receita Federal payload and is overwritten on every CNPJA sync; keeping prospecting
state out of it means a sync never erases contact history.

### Lawyer-Society Relationship Endpoints

```
GET    /api/v1/lawyer_societies/:id   # Show relationship
POST   /api/v1/lawyer_societies       # Create relationship (admin only)
PATCH  /api/v1/lawyer_societies/:id   # Update relationship (admin only)
DELETE /api/v1/lawyer_societies/:id   # Delete relationship (admin only)
```

## Receita Federal (OpenCNPJ)

Dados de CNPJ vêm do dump público do [OpenCNPJ](https://opencnpj.org), recortado para advocacia (CNAE 6911701) e importado em `receita_companies` / `receita_partners`. Todas as rotas exigem `X-API-KEY` (leitura basta). Mudança nos nomes dos campos abaixo é mudança pública (changelog 1.7).

### Confiança do vínculo sociedade ↔ CNPJ

`match_confidence` (e `cnpja_match_confidence` na sociedade) assume:

- `verified` — match inequívoco; só neste caso a sociedade recebe `cnpj` e os blocos `receita` / `partners` no payload do advogado.
- `ambiguous` — mais de um candidato plausível; **nunca é promovido** automaticamente.
- `unmatched` — sem candidato.

### Sociedade no payload do advogado

Cada item de `societies[]` em `GET /api/v1/lawyer/:oab` (e demais respostas que usam `LawyerSerializer`) ganha `cnpj`, `receita` e `partners`. Sem match `verified`, `cnpj` e `receita` vêm `null` e `partners` vem `[]`.

```json
{
  "id": 123,
  "name": "Silva & Souza Advogados",
  "cnpj": "12345678000199",
  "receita": {
    "situacao_cadastral": "Ativa",
    "data_situacao_cadastral": "2015-03-02",
    "data_inicio_atividade": "2015-03-02",
    "natureza_juridica": "Sociedade Simples Pura",
    "capital_social": "10000.00",
    "porte_empresa": "Demais",
    "opcao_simples": "N",
    "opcao_mei": "N",
    "email": "contato@silvasouza.adv.br",
    "telefones": [{ "ddd": "11", "numero": "33334444", "is_fax": false }],
    "endereco": {
      "tipo_logradouro": "RUA", "logradouro": "EXEMPLO", "numero": "100", "complemento": null,
      "bairro": "CENTRO", "cep": "01000000", "municipio": "SAO PAULO", "uf": "SP"
    },
    "release": "2026-09"
  },
  "partners": [
    {
      "nome": "FULANO DE TAL",
      "qualificacao": "Sócio-Administrador",
      "data_entrada": "2015-03-02",
      "faixa_etaria": "41 a 50 anos",
      "identificador": "Pessoa Física",
      "oab_id": "SP123456",
      "lawyer_id": 77
    }
  ]
}
```

`telefones` é uma lista de objetos `{ddd, numero, is_fax}` (lista vazia quando não há). `source` indica a origem da linha: `dump` (carga mensal do OpenCNPJ) ou `opencnpj_api` (consulta pontual em `GET /cnpj/:cnpj`, cache de 30 dias).

(Os valores acima são ilustrativos; as chaves são as reais de `ReceitaCompanySerializer`.) `oab_id` / `lawyer_id` só vêm preenchidos quando o sócio foi ligado a um advogado principal com nome único na UF.

### GET /api/v1/cnpj/:cnpj

Consulta um CNPJ qualquer: tabela local primeiro (dump, ou cache da API), API pública do OpenCNPJ na falta. Envie os 14 caracteres limpos (sem `/`); a rota só aceita dígitos, letras, pontos e hífens, então a máscara com barra não chega ao controller. Linha vinda da API vale 30 dias; "não existe" fica em cache negativo por 7 dias; falha de rede ou 429 nunca grava nada.

| Status | Corpo |
|---|---|
| 200 | objeto da empresa (mesmas chaves de `companies[]` abaixo) |
| 404 | `{"error": "CNPJ não encontrado na Receita"}` |
| 422 | `{"error": "CNPJ inválido"}` |
| 503 | `{"error": "Receita indisponível no momento", "retry_after": <segundos ou null>}` e header `Retry-After` quando houver. Após uma falha da API (timeout, erro, 429) o lookup fica 60 s sem consultá-la (`retry_after: 60`); linhas já na tabela seguem sendo servidas |

### GET /api/v1/receita/companies

Listagem para prospecção (só linhas do dump), ordenada por `cnpj` com cursor.

| Parâmetro | Descrição |
|---|---|
| `uf` | **Obrigatório.** UF válida; senão 400 |
| `situacao` | vazio = `Ativa`; `all` = sem filtro; ou o valor exato da situação cadastral |
| `matriz` | por padrão só matrizes; `false` inclui filiais |
| `natureza` | por padrão a lista de naturezas de sociedade de advogados; `all` = sem filtro; ou lista separada por vírgula |
| `founded_since` | data ISO 8601 (`2026-01-01`); filtra `data_inicio_atividade >= ` |
| `updated_since` | timestamp ISO 8601; filtra `updated_at >= `. Com offset de fuso, **URL-encode** o `+` (`%2B`); sem isso vira espaço. Prefira `Z` (`2026-10-01T00:00:00Z`) |
| `unmatched` | `true` = só empresas sem sociedade casada (nem outra filial da mesma raiz) |
| `known_lawyer` | `true` = só empresas com algum sócio ligado a advogado |
| `from_cnpj` | cursor: traz `cnpj > from_cnpj` |
| `limit` | padrão 100, máximo 500 |

Datas inválidas retornam 400.

```json
{
  "companies": [
    {
      "cnpj": "12345678000199",
      "razao_social": "SILVA & SOUZA ADVOGADOS",
      "nome_fantasia": null,
      "matriz": true,
      "cnae_principal": "6911701",
      "society_id": 123,
      "match_confidence": "verified",
      "source": "dump",
      "situacao_cadastral": "Ativa",
      "...": "demais chaves do bloco receita acima",
      "partners": [ { "nome": "FULANO DE TAL", "oab_id": null, "lawyer_id": null } ]
    }
  ],
  "meta": {
    "returned": 100,
    "next_from_cnpj": "12345678000199",
    "filters_applied": {
      "uf": "SP", "limit": 100, "situacao": "Ativa", "matriz": true,
      "natureza": ["Sociedade Unipessoal de Advocacia", "Sociedade Simples Pura", "..."], "founded_since": null, "updated_since": null,
      "unmatched": false, "known_lawyer": false
    }
  }
}
```

`filters_applied.natureza` é o array de naturezas efetivamente aplicado, ou a string `"all"` quando `natureza=all` (sem filtro). `source` de cada item é sempre `dump` nesta listagem.

`next_from_cnpj` é `null` na última página; senão, repasse-o em `from_cnpj`.

### Operação (carga mensal)

```bash
ssh -i ~/.ssh/deploy_prc_legal brpl@168.231.90.14
cd ~/code/prc_legal_data   # fonte da verdade: WorkingDirectory de infra/legal_data_api.service
mkdir -p storage/receita/2026-09
RAILS_ENV=production nohup bundle exec rake receita:refresh RELEASE=2026-09 \
  > storage/receita/2026-09/refresh.log 2>&1 &
tail -f storage/receita/2026-09/refresh.log
```

O refresh dura horas (download e extração de ~124 GB): rode sempre sob `nohup` (ou tmux), nunca numa sessão SSH solta. Reexecutar é seguro: empresas sem mudança são puladas e sociedades `verified` não são recasadas. Falha em qualquer etapa também envia o relatório ao painel, com o campo `error`. Se o MD5 do download divergir, o `.part` é removido e o download recomeça do zero na próxima execução.

Tasks (`lib/tasks/receita.rake`), todas com `RELEASE=AAAA-MM` (`receita:refresh` exige só `RELEASE` e não tem `DRY_RUN`, `STATE` nem `FILE`; `CNAE`, `INFO_URL` e `MD5` do ambiente chegam às etapas de extract e download):

| Task | Variáveis |
|---|---|
| `receita:download` | `INFO_URL`, `MD5` opcionais; sem info.json usa a URL fixa do zip e imprime `AVISO` (MD5 não conferido) |
| `receita:extract` | `CNAE` opcional (padrão 6911701) |
| `receita:import` | `FILE` (NDJSON), `DRY_RUN=true` |
| `receita:match_societies` | `STATE` opcional, `DRY_RUN=true` |
| `receita:link_partners` | `STATE` opcional, `DRY_RUN=true` |
| `receita:refresh` | encadeia download, extract, import, match, link e relatório |

Primeira carga sem baixar o dump no servidor: extraia o NDJSON localmente, envie com `scp` para `storage/receita/<release>/advocacia.ndjson` e rode `receita:refresh`; ele pula download e extract quando o NDJSON já existe.

Números da carga local de validação: 261.347 empresas e 436.441 sócios importados; 148.018 sociedades `verified` e 2.079 `ambiguous`; 156.819 sócios ligados a advogados.

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
