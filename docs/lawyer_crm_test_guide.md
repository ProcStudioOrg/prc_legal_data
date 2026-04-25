# Lawyer CRM Endpoints — Testing Guide

End-to-end test scenarios for the three new endpoints introduced on `feat/lawyer-crm-endpoints`. Use Bruno or curl. Each scenario shows: purpose → request → expected response shape → what to verify.

## Setup

The existing Bruno environment files already cover this:

```
collection/LegalDataAPI/environments/Local.bru
  base_url: http://localhost:3004/api/v1
  api_key:  <admin-role API key>
```

Boot the API first:
```bash
bin/rails s -p 3004
```

For raw curl, set:
```bash
export BASE_URL=http://localhost:3004/api/v1
export API_KEY=255e60ded2bc42980d13cb512765e2a9419ba5fab19db192
```

> The same key that works for `POST /lawyer/:oab/update` will work for the new write paths — they share `authorize_write!` which checks `api_key.role == "admin"`. Read endpoints accept any active key.

---

## Endpoint 1: `GET /api/v1/lawyer/:oab/crm` — token-lean read

**Purpose:** AI scraper pulls the minimum-necessary lawyer payload to perform enrichment. Aggressively null-filtered. Society partners capped at 6 with truncation flag.

### Scenario 1.1 — Lawyer without society (smallest payload)

Pick a real OAB you know exists with no society membership.

```bash
curl -s "$BASE_URL/lawyer/PR_54159/crm" \
  -H "X-API-KEY: $API_KEY" | jq .
```

**Bruno path:** `GET {{base_url}}/lawyer/PR_54159/crm`
**Headers:** `X-API-KEY: {{api_key}}`

**What to verify:**
- Response has top-level `principal` key
- `principal.crm_data` is always present (defaults to `{}`)
- `principal.supplementaries` is always present (`[]` or array of strings)
- `principal.societies` is always present (`[]` or array)
- Any field with `null` or `""` is **omitted from the JSON entirely** — only `crm_data`, `supplementaries`, `societies`, society identity (`name`/`oab_id`/`inscricao`), and the truncation flags are always emitted
- Boolean `false` values (e.g. `is_procstudio: false`, `phone_1_has_whatsapp: false`) ARE present in the JSON

### Scenario 1.2 — Supplementary OAB walks to principal

If `PR_54159` has supplementary records (e.g., `SP_412300`), call the endpoint with the **supplementary** OAB:

```bash
curl -s "$BASE_URL/lawyer/SP_412300/crm" \
  -H "X-API-KEY: $API_KEY" | jq '.principal | {oab_id, supplementaries}'
```

**Verify:** the response's `principal.oab_id` is the **principal's** OAB (`PR_54159`), not the queried supplementary. The queried supplementary appears inside `principal.supplementaries`.

### Scenario 1.3 — Lawyer with multi-partner society

Pick a lawyer whose society has multiple members (e.g., the Pellizzetti & Walber society):

```bash
curl -s "$BASE_URL/lawyer/PR_54159/crm" \
  -H "X-API-KEY: $API_KEY" | jq '.principal.societies[0]'
```

**Verify:**
- `partners` array contains all society members **except the queried lawyer**
- Each partner has the same field shape as the principal (no `societies` key — partners don't recurse)
- Each partner has its own `crm_data` and `supplementaries` arrays
- `partnership_type` appears both at the society level (queried lawyer's role) and inside each partner object (that partner's role)

### Scenario 1.4 — Society with > 6 other partners (truncation)

Find a lawyer in a large society (e.g., `MEGA ADVOCACIA` with 8+ partners). Query that lawyer:

```bash
curl -s "$BASE_URL/lawyer/<oab>/crm" \
  -H "X-API-KEY: $API_KEY" | jq '.principal.societies[0] | {partners_count: (.partners | length), truncated_partners, truncated_partner_oabs}'
```

**Verify:**
- `partners` length is exactly 6
- `truncated_partners: true`
- `truncated_partner_oabs` is an array of `{oab_id: "..."}` stubs (one per dropped partner)
- The 6 rendered partners are sorted by `partnership_type` (socio → socio_de_servico → associado), then by `oab_id` ASC within each bucket
- The truncated stubs continue the same sort sequence

### Scenario 1.5 — Error paths

```bash
# 404
curl -s -o /dev/null -w "%{http_code}\n" "$BASE_URL/lawyer/XX_99999/crm" -H "X-API-KEY: $API_KEY"

# 401
curl -s -o /dev/null -w "%{http_code}\n" "$BASE_URL/lawyer/PR_54159/crm" -H "X-API-KEY: invalid"

# 422 (cancelled / deceased lawyer)
# Pick an OAB with situation matching cancelado/falecido, e.g.:
curl -s "$BASE_URL/lawyer/<cancelled-oab>/crm" -H "X-API-KEY: $API_KEY" | jq .
```

**Expected:** `404` for unknown OAB, `401` for bad key, `422` for cancelled/deceased principal.

---

## Endpoint 2: `POST /api/v1/lawyer/:oab/crm` — extended write

**Purpose:** Scraper writes back enriched data. New: accepts arbitrary nested hashes under `scraper`, `outreach`, `signals`. Existing flat fields (`researched`, `contacted`, etc.) still work.

### Scenario 2.1 — Write a flat scraper sub-hash

```bash
curl -s -X POST "$BASE_URL/lawyer/PR_54159/crm" \
  -H "X-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"scraper": {"scraped": true, "lead_score": 75, "sources": ["instagram"]}}' | jq .
```

**Bruno body (json):**
```json
{
  "scraper": {
    "scraped": true,
    "lead_score": 75,
    "sources": ["instagram"]
  }
}
```

**Verify response 200 with:**
```json
{
  "message": "Dados CRM atualizados com sucesso",
  "oab_id": "PR_54159",
  "crm_data": {
    "scraper": { "scraped": true, "lead_score": 75, "sources": ["instagram"] }
  }
}
```

### Scenario 2.2 — Deep merge preserves untouched keys

After 2.1 ran, send only `lead_score`:

```bash
curl -s -X POST "$BASE_URL/lawyer/PR_54159/crm" \
  -H "X-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"scraper": {"lead_score": 92}}' | jq .crm_data.scraper
```

**Verify:**
- `scraped: true` is **preserved** (not overwritten)
- `sources: ["instagram"]` is **preserved**
- `lead_score: 92` is updated

### Scenario 2.3 — Arrays replace, do not concatenate

```bash
curl -s -X POST "$BASE_URL/lawyer/PR_54159/crm" \
  -H "X-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"scraper": {"sources": ["linkedin", "facebook"]}}' | jq .crm_data.scraper.sources
```

**Verify:** `["linkedin", "facebook"]` — the previous `["instagram"]` is gone.

### Scenario 2.4 — 2-level deep nesting (the big one)

```bash
curl -s -X POST "$BASE_URL/lawyer/PR_54159/crm" \
  -H "X-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "scraper": {
      "social": {
        "instagram": "@brunopellizzetti",
        "linkedin": "https://linkedin.com/in/bruno",
        "facebook": null
      }
    }
  }' | jq .crm_data.scraper.social
```

**Verify:** the entire nested `social` hash is persisted (this is the main reason `deep_permit_hash` exists — Rails' default `permit(scraper: {})` would silently drop the `social` sub-hash).

### Scenario 2.5 — Outreach + signals

```bash
curl -s -X POST "$BASE_URL/lawyer/PR_54159/crm" \
  -H "X-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "outreach": { "stage": "contacted", "contacted_at": "2026-04-25", "channel": "email" },
    "signals":  { "has_website": true, "has_linkedin": true, "active_litigator": false }
  }' | jq '.crm_data | {outreach, signals}'
```

**Verify:** both top-level keys are persisted. `false` boolean for `active_litigator` is stored, not dropped.

### Scenario 2.6 — Combined nested + flat update

```bash
curl -s -X POST "$BASE_URL/lawyer/PR_54159/crm" \
  -H "X-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "researched": true,
    "last_research_date": "2026-04-25",
    "scraper": { "lead_score": 88 }
  }' | jq .crm_data
```

**Verify:** all three keys (`researched`, `last_research_date`, `scraper.lead_score`) merge correctly without wiping the existing `scraper.sources`/`scraper.social` from prior scenarios.

### Scenario 2.7 — Confirm read endpoint reflects writes

```bash
curl -s "$BASE_URL/lawyer/PR_54159/crm" \
  -H "X-API-KEY: $API_KEY" | jq .principal.crm_data
```

**Verify:** the `crm_data` from Scenarios 2.1–2.6 is fully reflected when reading via the new lean endpoint.

### Scenario 2.8 — Auth: read-only key gets 403

If you have a non-admin key:
```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$BASE_URL/lawyer/PR_54159/crm" \
  -H "X-API-KEY: <read-only-key>" \
  -H "Content-Type: application/json" \
  -d '{"scraper": {"scraped": true}}'
```

**Expected:** `403`.

---

## Endpoint 3: `GET /api/v1/lawyers/crm` — CRM ingester listing

**Purpose:** CRM-side consumer pulls scraper-enriched lawyers, filtered by what's been scraped and how outreach is going. Cursor pagination. 1–100 limit.

### Scenario 3.1 — Default fetch (no filters)

```bash
curl -s "$BASE_URL/lawyers/crm" \
  -H "X-API-KEY: $API_KEY" | jq '{count: (.lawyers | length), meta}'
```

**Verify:**
- 200 response
- `lawyers` array with up to 50 rows (default limit)
- `meta` envelope with `returned`, `next_from_oab`, `filters_applied`
- Each row uses the `LawyerCrmListSerializer` shape (no `societies`, no `partners`, no `supplementaries` — list view only)
- `is_procstudio = true` rows are excluded
- Supplementary records (those with `principal_lawyer_id IS NOT NULL`) are excluded

### Scenario 3.2 — Filter by scraped flag

After running Scenario 2.1 (which sets `scraper.scraped = true` on PR_54159):

```bash
curl -s "$BASE_URL/lawyers/crm?scraped=true&limit=10" \
  -H "X-API-KEY: $API_KEY" | jq '.lawyers | map(.oab_id)'
```

**Verify:** PR_54159 appears; lawyers without `scraper.scraped = "true"` (note: stored as string) do not.

> Quirk: the JSONB filter compares against the literal string `'true'`. The scraper writes booleans (which JSONB stores as `true` not `"true"`). If the filter returns no rows, your data has booleans not strings — adjust the writer or the filter accordingly. The tests use `"true"` strings to match the SQL.

### Scenario 3.3 — Filter by outreach stage

After running Scenario 2.5:

```bash
curl -s "$BASE_URL/lawyers/crm?stage=contacted" \
  -H "X-API-KEY: $API_KEY" | jq '.lawyers | length, .meta.filters_applied'
```

**Verify:** only lawyers with `crm_data.outreach.stage = "contacted"` returned.

### Scenario 3.4 — `min_lead_score` with regex pre-filter

After running Scenario 2.2 (PR_54159 has `lead_score: 92`):

```bash
# Should include PR_54159 (lead_score >= 70)
curl -s "$BASE_URL/lawyers/crm?min_lead_score=70" \
  -H "X-API-KEY: $API_KEY" | jq '.lawyers | length'

# Should exclude PR_54159 (lead_score < 95)
curl -s "$BASE_URL/lawyers/crm?min_lead_score=95" \
  -H "X-API-KEY: $API_KEY" | jq '.lawyers | length'

# 400 for non-numeric
curl -s -o /dev/null -w "%{http_code}\n" \
  "$BASE_URL/lawyers/crm?min_lead_score=abc" \
  -H "X-API-KEY: $API_KEY"
```

**Verify:** numeric thresholds work; non-numeric param returns `400` with body `{"error": "min_lead_score deve ser numérico"}`. The regex pre-filter (`crm_data->'scraper'->>'lead_score' ~ '^\d+$'`) prevents `PG::InvalidTextRepresentation` from rows that may have stored non-numeric `lead_score` values.

### Scenario 3.5 — Presence filters (instagram / website)

```bash
# Lawyers with non-empty instagram
curl -s "$BASE_URL/lawyers/crm?has_instagram=true&limit=5" \
  -H "X-API-KEY: $API_KEY" | jq '.lawyers | map({oab_id, instagram})'

# Lawyers with non-empty website
curl -s "$BASE_URL/lawyers/crm?has_website=true&limit=5" \
  -H "X-API-KEY: $API_KEY" | jq '.lawyers | map({oab_id, website})'
```

**Verify:** filter excludes both `NULL` and empty-string `''` values (the SQL uses `IS NOT NULL AND != ''`).

### Scenario 3.6 — Combined filters (AND)

```bash
curl -s "$BASE_URL/lawyers/crm?scraped=true&stage=contacted&has_instagram=true&min_lead_score=50&state=PR&limit=20" \
  -H "X-API-KEY: $API_KEY" | jq '{count: (.lawyers | length), filters: .meta.filters_applied}'
```

**Verify:** all filters AND together; `meta.filters_applied` echoes back exactly what you sent (compacted to drop missing params).

### Scenario 3.7 — Cursor pagination

```bash
# First page
curl -s "$BASE_URL/lawyers/crm?state=PR&limit=2" \
  -H "X-API-KEY: $API_KEY" | jq '{rows: (.lawyers | map(.oab_id)), next: .meta.next_from_oab}'

# Use next_from_oab from above
curl -s "$BASE_URL/lawyers/crm?state=PR&limit=2&from_oab=<next_from_oab>" \
  -H "X-API-KEY: $API_KEY" | jq '{rows: (.lawyers | map(.oab_id)), next: .meta.next_from_oab}'
```

**Verify:**
- First page returns the 2 highest `oab_id` values for PR (lexicographic DESC)
- `meta.next_from_oab` is the smallest oab_id on the page
- Second page continues with the next 2 rows in DESC order
- `meta.next_from_oab` is `null` when no more rows remain

### Scenario 3.8 — Limit clamping

```bash
# limit=999 → clamped to 100
curl -s "$BASE_URL/lawyers/crm?limit=999" \
  -H "X-API-KEY: $API_KEY" | jq '.lawyers | length'

# limit=0 → clamped to 1
curl -s "$BASE_URL/lawyers/crm?limit=0" \
  -H "X-API-KEY: $API_KEY" | jq '.lawyers | length'
```

**Verify:** `<= 100` for the first call, `1` for the second.

### Scenario 3.9 — Invalid state

```bash
curl -s -o /dev/null -w "%{http_code}\n" "$BASE_URL/lawyers/crm?state=XX" -H "X-API-KEY: $API_KEY"
```

**Expected:** `400`.

---

## End-to-end smoke sequence

A quick path that exercises all three endpoints together:

1. **Read** baseline state for an OAB:
   ```bash
   curl -s "$BASE_URL/lawyer/PR_54159/crm" -H "X-API-KEY: $API_KEY" | jq .principal.crm_data
   ```
2. **Write** scraper enrichment with deep nesting:
   ```bash
   curl -s -X POST "$BASE_URL/lawyer/PR_54159/crm" \
     -H "X-API-KEY: $API_KEY" -H "Content-Type: application/json" \
     -d '{"scraper":{"scraped":true,"lead_score":85,"social":{"instagram":"@bruno"}},"outreach":{"stage":"contacted"}}'
   ```
3. **Read again** — verify the write persisted as expected:
   ```bash
   curl -s "$BASE_URL/lawyer/PR_54159/crm" -H "X-API-KEY: $API_KEY" | jq .principal.crm_data
   ```
4. **List** scraped+contacted lawyers and confirm PR_54159 is included:
   ```bash
   curl -s "$BASE_URL/lawyers/crm?scraped=true&stage=contacted" \
     -H "X-API-KEY: $API_KEY" | jq '.lawyers | map(.oab_id)'
   ```

If steps 3 and 4 reflect step 2's writes, the full scraper → prc_legal_data → CRM ingester flow is wired correctly.

---

## Reference: known limitations

- **Deep-key deletion is not supported.** Sending `{"scraper":{"lead_score":null}}` is a no-op for that key — the `compact` strip + `deep_merge` semantics preserve the existing value. To "delete" a deep key, overwrite it with the desired explicit value, or send the entire sub-hash with the desired final state.
- **Top-level `null`** values are also stripped before merge (existing behavior).
- **Cross-state pagination** of `crm_index` orders by `oab_id` lexicographically (e.g., `PR_99999 < SP_10000`). Scope to a single state via `?state=PR` for natural numeric ordering within that state.
- **`scraper.scraped`** filter compares against the literal string `'true'`. Make sure the writer stores `"true"` (string) or adjust the filter SQL if you store booleans.
