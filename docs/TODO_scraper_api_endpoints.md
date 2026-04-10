# TODO: Scraper API Endpoints

## Context

External AI-powered scraper needs to fetch lawyers in batch (descending OAB order, newest first) and get concise responses with disambiguation info. These endpoints serve a social information scraper that processes lawyers as our target audience.

---

## 1. GET /api/v1/lawyers

Batch fetch lawyers with filters. Used by scraper to process lawyers in descending OAB number order.

### Query params

| Param | Required | Default | Description |
|-------|----------|---------|-------------|
| state | yes | — | State filter (PR, SP, etc) |
| from_oab | no | highest | Start from this OAB number going downward |
| limit | no | 50 | Max lawyers to return |
| scraped | no | — | Filter by `crm_data->>'scraped'`. When `false`, return only unscraped |

### Behavior

- Order by `oab_number DESC` (cast to integer)
- Only return lawyers with `situation = 'REGULAR'` (case-insensitive — DB stores as "situação regular")
- Exclude lawyers where `is_procstudio = true`
- If `from_oab` provided, only return lawyers with `oab_number < from_oab` (integer comparison)

### Response (200)

```json
{
  "lawyers": [
    {
      "id": 1,
      "full_name": "DAVID SOMBRA PEIXOTO",
      "oab_number": "131009",
      "oab_id": "PR_131009",
      "city": "CURITIBA",
      "state": "PR",
      "phone_number_1": "(41) 99999-9999",
      "situation": "REGULAR",
      "instagram": null,
      "website": null,
      "has_society": false,
      "similar_names": ["CE_16477", "SP_388253"],
      "crm_data": {}
    }
  ],
  "meta": {
    "total": 117921,
    "returned": 50,
    "state": "PR",
    "from_oab": "131010"
  }
}
```

### Notes

- Response must be **concise** — this feeds an AI agent, context window matters
- No nested objects for societies/supplementaries in this endpoint
- `similar_names` field: array of OAB IDs that share the same `full_name` (different people, same name). Populated after face matcher processing. Helps the AI scraper avoid confusing homonimos.

---

## 2. `similar_names` field

Instead of a separate disambiguation endpoint, include a `similar_names` array in the lawyer response.

**Logic:**
- For a given lawyer, find all other lawyers with the exact same `full_name`
- Exclude supplementaries of the same person (those linked via `principal_lawyer_id`)
- Only include OABs that belong to **different people** (different `principal_lawyer_id` clusters)

**Example:**
```
PAULO ROBERTO DOS SANTOS has 18 records:
  - Cluster A: DF_11837 (principal) + MG_164361 (supp) → same person
  - Cluster B: MG_171899 (principal) + PR_33243, SC_51334, SP_383455 → same person
  - Unlinked: 12 others

When fetching DF_11837:
  similar_names: ["MG_171899", ...unlinked OABs]
  (excludes MG_164361 because it's the same person)
```

**Implementation approach:**
- Query `lawyers` where `full_name = self.full_name AND id != self.id`
- Group by `principal_lawyer_id` cluster
- Exclude OABs in the same cluster as the requested lawyer
- Return one representative OAB per cluster (the anchor/principal)

---

## 3. Implementation priorities

1. `GET /api/v1/lawyers` — batch endpoint (needed first for scraper)
2. `similar_names` field — add after face matcher batch is complete for all 64K groups
3. Consider caching `similar_names` in a JSON field to avoid heavy queries at request time

---

## Dependencies

- Face matcher batch must complete for all 64K groups before `similar_names` is reliable
- `crm_data->>'scraped'` field needs to be populated by the scraper as it processes
