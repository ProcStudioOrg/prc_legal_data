# Scraper API — Batch Lawyers Endpoint

## Summary

New `GET /api/v1/lawyers` endpoint for external AI scraper to fetch lawyers in batch, ordered by OAB number descending (newest first). Includes a dedicated serializer with society members and supplementary OABs in a compact format. Also includes a rake task to pre-flag lawyers in large societies (>6 members) as enterprise customers.

## Endpoint: `GET /api/v1/lawyers`

### Route

```
GET /api/v1/lawyers → Api::V1::LawyersController#index
```

Uses plural `lawyers` to distinguish from existing singular `lawyer/:oab` routes.

### Authentication

Same `ApiAuthentication` concern as existing endpoints. Read-only — no `authorize_write!` needed.

### Query Parameters

| Param    | Required | Default  | Description                                                     |
|----------|----------|----------|-----------------------------------------------------------------|
| state    | yes      | —        | State filter (PR, SP, etc)                                      |
| from_oab | no      | highest  | Start from this OAB number going downward (cursor pagination)   |
| limit    | no       | 50       | Max lawyers to return (cap at 100)                              |
| scraped  | no       | —        | Filter by `crm_data->>'scraped'`. `false` = only unscraped      |

### Query Logic

```sql
WHERE state = :state
  AND situation ILIKE '%regular%'
  AND (is_procstudio IS NULL OR is_procstudio = false)
  AND CAST(oab_number AS INTEGER) < :from_oab  -- only if from_oab provided
ORDER BY CAST(oab_number AS INTEGER) DESC
LIMIT :limit
```

### Response (200)

```json
{
  "lawyers": [
    {
      "id": 1,
      "full_name": "BRUNO PELLIZZETTI",
      "oab_number": "30145",
      "oab_id": "PR_30145",
      "situation": "REGULAR",
      "city": "CURITIBA",
      "state": "PR",
      "address": "Rua X, 123",
      "phone_number_1": "(41) 99999-9999",
      "phone_number_2": null,
      "email": "email@example.com",
      "instagram": null,
      "website": null,
      "has_society": true,
      "supplementary_oabs": ["AC_3901"],
      "societies": [
        {
          "name": "PELLIZZETTI E WALBER",
          "members": [
            {"name": "JOAO DA SILVA", "oab_id": "PR_59010"},
            {"name": "MARCOS AURELIO", "oab_id": "PR_390931"}
          ]
        }
      ],
      "crm_data": {}
    }
  ],
  "meta": {
    "returned": 50,
    "state": "PR",
    "from_oab": "131010",
    "next_from_oab": "130960"
  }
}
```

### Society Serialization Rules

- **Societies with ≤6 members**: include `name` + `members` array (each member: `name` + `oab_id`)
- **Societies with >6 members**: include `name`, `enterprise: true`, `member_count: N` — no individual members listed
- Members are fetched from `lawyer_societies` join — all lawyers linked to that society

### Supplementary OABs

Simple array of `oab_id` strings — all other OABs belonging to the same person:
- If the lawyer is the **principal** (`principal_lawyer_id IS NULL`): collect `oab_id` from all `supplementary_lawyers`
- If the lawyer is **supplementary** (`principal_lawyer_id` set): collect the principal's `oab_id` + all sibling supplementaries' `oab_id`

### Meta

- `returned`: number of lawyers in this response
- `state`: the state filter used
- `from_oab`: the from_oab used (or null if starting from top)
- `next_from_oab`: the lowest oab_number in this batch — use as `from_oab` for next page. Null if fewer results than limit (last page).

---

## Serializer: `ScraperLawyerSerializer`

New dedicated serializer in `app/serializers/scraper_lawyer_serializer.rb`. Does NOT modify the existing `LawyerSerializer`.

Fields:
- `id`, `full_name`, `oab_number`, `oab_id`, `situation`, `city`, `state`, `address`
- `phone_number_1`, `phone_number_2`, `email`, `instagram`, `website`
- `has_society`
- `supplementary_oabs` (computed)
- `societies` (computed, with member threshold logic)
- `crm_data`

---

## Rake Task: `data:flag_enterprise_societies`

Iterates all societies, counts members via `lawyer_societies`. For societies with >6 members, sets `crm_data.enterprise_society = true` on each member lawyer.

```bash
rails data:flag_enterprise_societies
```

This runs once to backfill, can be re-run periodically.

---

## Bruno Collection

Add `collection/LegalDataAPI/Lawyers/Listar Advogados (Scraper).bru` with:
- GET request to `{{baseUrl}}/api/v1/lawyers`
- Query params: `state=PR`, `limit=20`
- Same auth headers as existing requests

---

## Verification Test Cases

After implementation, run these requests against real data to verify correctness.

### Test 1: Small society with members listed (≤6)

**Request:** `GET /api/v1/lawyers?state=MG&from_oab=183894&limit=1`

**Expect lawyer:** `MG_183893` — ROZEANE MARTINS MOMOSE

**Verify:**
- Society `SOARES DONATO ADVOGADOS ASSOCIADOS` (id: 337562) appears with individual members listed
- Members should include at least: `MG_62039` (CLAUDIO SOARES DONATO), `MG_65030` (ANA PAULA BATISTA)
- No `enterprise: true` flag (society has ≤6 members)

### Test 2: Large society with enterprise flag (>6)

**Request:** `GET /api/v1/lawyers?state=MG&from_oab=198237&limit=1`

**Expect lawyer:** `MG_198236` — GABRIELA LIMA MOREIRA REIS

**Verify:**
- Society `ANANIAS JUNQUEIRA FERRAZ E ADVOGADOS ASSOCIADOS` (id: 337563, 136 members) appears with `enterprise: true` and `member_count: 136`
- No individual members listed

### Test 3: Supplementary OABs

**Request:** `GET /api/v1/lawyers?state=PR&from_oab=72714&limit=1`

**Expect lawyer:** `PR_72713` — ANA PAULA DE LIMA

**Verify:**
- `supplementary_oabs` includes principal `MT_29604` (she is supplementary of MT_29604)
- Society `ANA P. DE LIMA SOCIEDADE INDIVIDUAL DE ADVOCACIA` listed

### Test 4: Massive society — URBANO VITALINO (466 members)

Pick any PE lawyer who is a member of society 350798.

**Verify:**
- Society appears as `enterprise: true`, `member_count: 466`
- Response stays compact despite huge society

### Test 5: Cursor pagination

**Request 1:** `GET /api/v1/lawyers?state=PR&limit=3`
**Request 2:** `GET /api/v1/lawyers?state=PR&limit=3&from_oab={next_from_oab from request 1}`

**Verify:**
- Request 2 returns lawyers with oab_number strictly less than `next_from_oab`
- No overlap between the two batches
- All returned lawyers have `situation ILIKE '%regular%'` and `is_procstudio` is false/null

### Test 6: Scraped filter

**Request:** `GET /api/v1/lawyers?state=PR&limit=5&scraped=false`

**Verify:**
- Only returns lawyers where `crm_data->>'scraped'` is NULL or not `'true'`

---

## What This Does NOT Include

- `similar_names` field — deferred to face-matcher-on-create task
- Changes to existing `LawyerSerializer` or `show_by_oab`
- Changes to `last_oab_by_state`
