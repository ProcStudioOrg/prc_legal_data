# Lawyer CRM Endpoint — Design Spec

**Date:** 2026-04-25
**Status:** Approved
**Owner:** Bruno Pellizzetti

## Goal

Add three coordinated capabilities to the legal data API to support the AI-driven scraper → CRM flow:

1. A token-lean **read endpoint** for the AI scraper (`GET /api/v1/lawyer/:oab/crm`) that returns just enough lawyer + society + partner data to perform enrichment, with aggressive null-filtering and partner truncation to control token cost.
2. An **extended write endpoint** (`POST /api/v1/lawyer/:oab/crm`) that accepts arbitrary nested hashes under `scraper`, `outreach`, and `signals` keys inside `crm_data`.
3. A **CRM-feed listing** (`GET /api/v1/lawyers/crm`) that returns scraper-enriched lawyers filtered by `crm_data` JSON paths plus presence of `instagram`/`website`, with cursor pagination and a 1–100 limit.

These changes do not introduce migrations, models, or background jobs. All work lives in one controller and three new serializers.

## Architecture

```
                                                ┌──────────────────────┐
              GET /lawyer/:oab/crm  ─────────►  │ LawyerCrmSerializer  │
                                                │  (+ partner sub)     │
                                                └──────────────────────┘
              POST /lawyer/:oab/crm ─────────►  Api::V1::LawyersController
                                                  • show_crm   (new)
                                                  • update_crm (extended)
                                                  • crm_index  (new)
                                                ┌──────────────────────┐
              GET /lawyers/crm     ─────────►  │ LawyerCrmListSerializer│
                                                └──────────────────────┘
```

**Files touched:**

| File | Change |
|---|---|
| `app/controllers/api/v1/lawyers_controller.rb` | Add `show_crm`, add `crm_index`, extend `update_crm` permits with deep-permit helper |
| `app/serializers/lawyer_crm_serializer.rb` | New — heavy lean shape for `show_crm` |
| `app/serializers/lawyer_crm_partner_serializer.rb` | New — partner shape inside societies (no recursion) |
| `app/serializers/lawyer_crm_list_serializer.rb` | New — single-row shape for `crm_index` |
| `config/routes.rb` | Add `GET /lawyer/:oab/crm` and `GET /lawyers/crm` |
| `spec/serializers/lawyer_crm_serializer_spec.rb` | New |
| `spec/requests/api/v1/lawyer_crm_spec.rb` | New |
| `spec/requests/api/v1/lawyers_crm_index_spec.rb` | New |
| `spec/requests/api/v1/lawyer_update_crm_spec.rb` | Extend or add for new permits |

## Routes

```ruby
namespace :api do
  namespace :v1 do
    # existing routes preserved...
    get  'lawyer/:oab/crm', to: 'lawyers#show_crm'   # NEW
    post 'lawyer/:oab/crm', to: 'lawyers#update_crm' # existing, unchanged path
    get  'lawyers/crm',     to: 'lawyers#crm_index'  # NEW
  end
end
```

`set_lawyer` `before_action` whitelist gains `:show_crm`. `authorize_write!` is **not** applied to `show_crm` or `crm_index` (read-only).

## `GET /api/v1/lawyer/:oab/crm` — `show_crm`

### Behavior

1. Look up lawyer by `oab_id` with eager loading: `principal_lawyer`, `supplementary_lawyers`, `lawyer_societies: { society: { lawyer_societies: :lawyer } }`.
2. If found record has `principal_lawyer_id`, walk to the principal (matches `show_by_oab` logic).
3. Run `verify_lawyer_status` on the principal — return 422 if cancelled/deceased.
4. Render via `LawyerCrmSerializer.new(principal).as_json` wrapped in `{ principal: … }`.

### Field rules

**Universal null-filter rule:** every field except those in the always-emit list is **omitted from the JSON entirely** when the value is `nil` or an empty string `""`. **Boolean `false` is emitted.** Do not use Ruby's `blank?` here — `false.blank?` is `true`, which would incorrectly drop legitimate boolean signals like `is_procstudio: false` or `phone_1_has_whatsapp: false`. Implementation must check `value.nil? || value == ""` explicitly. This rule applies to the principal *and* every partner inside societies.

**Always emitted (even if empty/nil):**
- `crm_data` → `@lawyer.crm_data || {}`
- `supplementaries` → array of `oab_id` strings; `[]` if none
- Society identity: `name`, `oab_id`, `inscricao`
- Society truncation flags: `truncated_partners`, `truncated_partner_oabs`

**Null-filtered (omitted when blank):**

Principal & partners:
- `full_name`, `oab_id`, `state`, `city`, `situation`, `profession`, `address`, `zip_code`, `phone_number_1`, `phone_number_2`
- `phone_1_has_whatsapp`, `phone_2_has_whatsapp`, `email`, `specialty`, `bio`, `instagram`, `website`, `is_procstudio`

Society:
- `state`, `city`, `address`, `phone`, `situacao`, `number_of_partners`, `partnership_type`

> Note: `oab_id`, `full_name`, and `state` are required at the model level so they will always render in practice. The universal rule keeps the serializer logic uniform — no two-class field split.

### Societies

For each `LawyerSociety` of the principal, render:

```json
{
  "name": "...",
  "oab_id": "...",
  "inscricao": 123456,
  "state": "PR",
  "city": "...",
  "address": "...",
  "phone": "...",
  "situacao": "Ativo",
  "number_of_partners": 2,
  "partnership_type": "socio",
  "partners": [...up to 6 partner objects...],
  "truncated_partners": false,
  "truncated_partner_oabs": []
}
```

`partnership_type` here represents **this principal's role** in this society (`ls.partnership_type`).

### Partners

For each society's `lawyer_societies`:

1. Reject the principal lawyer's own membership entry.
2. Sort remaining partners by:
   - Partnership type bucket: `socio` → `socio_de_servico` → `associado`
   - Within bucket: `oab_id` ASC
3. Take first 6.
4. If more than 6 remain after step 1, set `truncated_partners: true` and populate `truncated_partner_oabs` with `[{ "oab_id": "XX_NNNNN" }, …]` for each dropped partner. Otherwise `truncated_partners: false` and `truncated_partner_oabs: []`.

Each rendered partner uses `LawyerCrmPartnerSerializer`, which produces:
- All principal fields (always-emit + null-filtered) **except** `societies` (no recursion)
- `partnership_type` — that partner's role in this society
- `crm_data` — always emit (default `{}`)
- `supplementaries` — array of `oab_id` strings; `[]` if none

### Sample (2-partner society)

```json
{
  "principal": {
    "full_name": "BRUNO PELLIZZETTI",
    "oab_id": "PR_54159",
    "state": "PR",
    "city": "CURITIBA",
    "situation": "situação regular",
    "profession": "ADVOGADO",
    "address": "RUA EXEMPLO 123, CENTRO",
    "zip_code": "80010000",
    "phone_number_1": "(41) 3333-4444",
    "phone_number_2": "(41) 99999-8888",
    "phone_1_has_whatsapp": true,
    "email": "bruno@example.com",
    "instagram": "@brunopellizzetti",
    "crm_data": {
      "scraper": { "scraped": true, "lead_score": 75 },
      "outreach": { "stage": "contacted" }
    },
    "supplementaries": ["SP_412300"],
    "societies": [
      {
        "name": "PELLIZZETTI E WALBER ADVOGADOS ASSOCIADOS",
        "oab_id": "12345/6",
        "inscricao": 567890,
        "state": "PR",
        "city": "CURITIBA",
        "address": "RUA EXEMPLO 123, SALA 502, CENTRO",
        "phone": "(41) 3333-4444",
        "situacao": "Ativo",
        "number_of_partners": 2,
        "partnership_type": "socio",
        "partners": [
          {
            "full_name": "WALBER OLIVEIRA SILVA",
            "oab_id": "PR_88231",
            "state": "PR",
            "city": "CURITIBA",
            "situation": "situação regular",
            "profession": "ADVOGADO",
            "address": "RUA EXEMPLO 123, SALA 502, CENTRO",
            "zip_code": "80010000",
            "phone_number_1": "(41) 3333-4444",
            "phone_number_2": "(41) 98888-7777",
            "phone_1_has_whatsapp": true,
            "email": "walber@example.com",
            "partnership_type": "socio",
            "crm_data": {},
            "supplementaries": []
          }
        ],
        "truncated_partners": false,
        "truncated_partner_oabs": []
      }
    ]
  }
}
```

### Sample (8-partner society, truncation)

```json
{
  "principal": {
    "full_name": "ANA MARTINS",
    "oab_id": "SP_100200",
    "state": "SP",
    "city": "SÃO PAULO",
    "situation": "situação regular",
    "profession": "ADVOGADA",
    "address": "AV PAULISTA 1000",
    "zip_code": "01310100",
    "phone_number_1": "(11) 3000-1000",
    "phone_number_2": "(11) 99000-1000",
    "crm_data": {},
    "supplementaries": [],
    "societies": [
      {
        "name": "MARTINS, COSTA & ASSOCIADOS",
        "oab_id": "55555/8",
        "inscricao": 778899,
        "state": "SP",
        "city": "SÃO PAULO",
        "address": "AV PAULISTA 1000, 12º ANDAR",
        "phone": "(11) 3000-1000",
        "situacao": "Ativo",
        "number_of_partners": 8,
        "partnership_type": "socio",
        "partners": [
          { "full_name": "BRUNO COSTA",    "oab_id": "SP_100201", "state": "SP", "city": "SÃO PAULO", "situation": "situação regular", "profession": "ADVOGADO",  "address": "AV PAULISTA 1000", "zip_code": "01310100", "phone_number_1": "(11) 3000-1001", "partnership_type": "socio",            "crm_data": {}, "supplementaries": [] },
          { "full_name": "CARLA DIAS",     "oab_id": "SP_100202", "state": "SP", "city": "SÃO PAULO", "situation": "situação regular", "profession": "ADVOGADA", "address": "AV PAULISTA 1000", "zip_code": "01310100", "phone_number_1": "(11) 3000-1002", "partnership_type": "socio",            "crm_data": {}, "supplementaries": [] },
          { "full_name": "DIEGO ESPÍRITO", "oab_id": "SP_100203", "state": "SP", "city": "SÃO PAULO", "situation": "situação regular", "profession": "ADVOGADO",  "address": "AV PAULISTA 1000", "zip_code": "01310100", "phone_number_1": "(11) 3000-1003", "partnership_type": "socio",            "crm_data": {}, "supplementaries": [] },
          { "full_name": "ELIANA FARIAS",  "oab_id": "SP_100204", "state": "SP", "city": "SÃO PAULO", "situation": "situação regular", "profession": "ADVOGADA", "address": "AV PAULISTA 1000", "zip_code": "01310100", "phone_number_1": "(11) 3000-1004", "partnership_type": "socio_de_servico", "crm_data": {}, "supplementaries": [] },
          { "full_name": "FERNANDO GOMES", "oab_id": "SP_100205", "state": "SP", "city": "SÃO PAULO", "situation": "situação regular", "profession": "ADVOGADO",  "address": "AV PAULISTA 1000", "zip_code": "01310100", "phone_number_1": "(11) 3000-1005", "partnership_type": "associado",        "crm_data": {}, "supplementaries": [] },
          { "full_name": "GABRIELA HORTA", "oab_id": "SP_100206", "state": "SP", "city": "SÃO PAULO", "situation": "situação regular", "profession": "ADVOGADA", "address": "AV PAULISTA 1000", "zip_code": "01310100", "phone_number_1": "(11) 3000-1006", "partnership_type": "associado",        "crm_data": {}, "supplementaries": [] }
        ],
        "truncated_partners": true,
        "truncated_partner_oabs": [
          { "oab_id": "SP_100207" }
        ]
      }
    ]
  }
}
```

### Errors

| Condition | Status | Body |
|---|---|---|
| Missing `:oab` | 400 | `{ "error": "Número OAB obrigatório" }` |
| Lawyer not found | 404 | `{ "error": "Advogado Não Encontrado - Verifique o OAB ID" }` |
| Principal cancelled/deceased | 422 | `{ "error": "Status Inválido (Principal): …" }` |
| Internal error | 500 | Existing envelope with `request_id` |

## `POST /api/v1/lawyer/:oab/crm` — `update_crm` (extended)

### Change

Extend the permits list to accept three nested hashes:

```ruby
crm_params = params.permit(
  :researched, :last_research_date, :trial_active,
  :tried_procstudio, :mail_marketing, :contacted,
  :contacted_by, :contacted_when, :contact_notes,
  mail_marketing_origin: []
).to_h

# Free-form deep-permit for AI-driven sub-hashes.
%i[scraper outreach signals].each do |key|
  raw = params[key]
  next if raw.blank?
  crm_params[key.to_s] = deep_permit_hash(raw)
end
```

### `deep_permit_hash` helper (new private method)

Walks an `ActionController::Parameters` (or plain hash) and returns a plain Ruby hash with stringified keys, preserving arbitrary nesting and array-of-scalars / array-of-hashes values. Required because Rails' `permit(scraper: {})` only accepts a single level of arbitrary keys; deeper nesting is silently dropped.

```ruby
def deep_permit_hash(value)
  case value
  when ActionController::Parameters
    value.to_unsafe_h.transform_values { |v| deep_permit_hash(v) }.deep_stringify_keys
  when Hash
    value.transform_values { |v| deep_permit_hash(v) }.deep_stringify_keys
  when Array
    value.map { |v| deep_permit_hash(v) }
  else
    value
  end
end
```

> `to_unsafe_h` is acceptable here because the entire `crm_data` field is intentionally free-form — there is no schema we are bypassing. The safety boundary is the explicit list of three top-level keys (`scraper`/`outreach`/`signals`); anything outside them is rejected by Rails normally.

### Merge semantics

Base behavior unchanged: `current_crm.deep_merge(crm_params)`. Arrays replace; scalars and inner keys persist unless explicitly overwritten.

**Decision on `compact` and key deletion:** the existing implementation calls `crm_params.compact`, which strips top-level `nil` values before merge. This means a client sending `{ "contacted": null }` cannot un-set `contacted` — the key is dropped from the patch before merge.

For the new free-form sub-hashes, **deep-key deletion is out of scope for this change**. Clients can:
- **Overwrite** with a new value (including empty strings or empty arrays).
- **Replace** an entire sub-hash by sending the full desired state (deep_merge will keep keys not mentioned, so this isn't strictly a replace — it's an overlay).

If true deep-key deletion becomes necessary later, add a sentinel convention (e.g., `"__delete__"` marker) or a separate `DELETE` endpoint. Not in this spec.

Top-level fields keep current behavior (`compact` drops `nil`s; partial updates preserve existing values).

### Behavior contract examples

| Existing `crm_data.scraper` | Incoming `scraper` | Result |
|---|---|---|
| `nil` | `{ scraped: true }` | `{ scraped: true }` |
| `{ scraped: true, lead_score: 80 }` | `{ lead_score: 90 }` | `{ scraped: true, lead_score: 90 }` |
| `{ sources: ["instagram"] }` | `{ sources: ["linkedin"] }` | `{ sources: ["linkedin"] }` (array replace) |
| `{ social: { instagram: "@a", linkedin: "..." } }` | `{ social: { facebook: "..." } }` | `{ social: { instagram: "@a", linkedin: "...", facebook: "..." } }` (deep merge) |

## `GET /api/v1/lawyers/crm` — `crm_index`

### Filters (all optional, AND-combined)

| Param | SQL fragment | Validation |
|---|---|---|
| `scraped=true` | `crm_data->'scraper'->>'scraped' = 'true'` | string compare |
| `stage=<value>` | `crm_data->'outreach'->>'stage' = ?` | exact match |
| `min_lead_score=<int>` | `crm_data->'scraper'->>'lead_score' ~ '^\d+$' AND (crm_data->'scraper'->>'lead_score')::int >= ?` | regex pre-filter avoids `PG::InvalidTextRepresentation` on non-numeric values; reject non-numeric param with 400 |
| `has_instagram=true` | `instagram IS NOT NULL AND instagram != ''` | |
| `has_website=true` | `website IS NOT NULL AND website != ''` | |
| `state=<XX>` | `state = ?` | optional; if present must be in `VALID_STATES` |
| `from_oab=<oab_id>` | `oab_id < ?` (when paginating; lexicographic OK because cursor is the actual `oab_id`, not the integer number) | |
| `limit=<n>` | clamp `[1, 100]`, default `50` | matches existing `index` formula |

### Default scope (always applied)

```ruby
Lawyer
  .where("is_procstudio IS NULL OR is_procstudio = false")
  .where(principal_lawyer_id: nil)   # principals only — supplementary records excluded
```

### Pagination

Cursor pattern, mirrors existing `index`:

1. Order by `oab_id DESC` (stable, indexed).
2. Fetch `limit + 1` rows.
3. If `length > limit`, set `meta.next_from_oab` to the last returned row's `oab_id` and trim to `limit`.
4. Otherwise `meta.next_from_oab` is `nil`.

### Response shape

```json
{
  "lawyers": [
    {
      "oab_id": "PR_54159",
      "full_name": "BRUNO PELLIZZETTI",
      "state": "PR",
      "city": "CURITIBA",
      "phone_number_1": "(41) 3333-4444",
      "phone_number_2": "(41) 99999-8888",
      "email": "bruno@example.com",
      "instagram": "@brunopellizzetti",
      "has_society": true,
      "crm_data": { "scraper": { "scraped": true, "lead_score": 75 }, "outreach": { "stage": "contacted" } }
    }
  ],
  "meta": {
    "returned": 1,
    "next_from_oab": null,
    "filters_applied": { "scraped": true, "min_lead_score": 70 }
  }
}
```

Same null-filter rule as `LawyerCrmSerializer`: any nil/blank field key is dropped except `crm_data`. No `societies`, no `partners`, no `supplementaries` — list view only.

`LawyerCrmListSerializer` fields:
- `oab_id`, `full_name`, `state`, `city`
- `phone_number_1`, `phone_number_2`, `email`
- `instagram`, `website`
- `has_society`
- `crm_data`

### Errors

| Condition | Status | Body |
|---|---|---|
| `min_lead_score` non-numeric | 400 | `{ "error": "min_lead_score deve ser numérico" }` |
| `state` not in `VALID_STATES` | 400 | matches existing `index` |
| Internal | 500 | existing envelope |

## Auth

| Endpoint | `ApiAuthentication` | `authorize_write!` |
|---|---|---|
| `GET /lawyer/:oab/crm` | yes (existing) | no |
| `POST /lawyer/:oab/crm` | yes (existing) | yes (existing) |
| `GET /lawyers/crm` | yes (existing) | no |

## Testing strategy

### `spec/serializers/lawyer_crm_serializer_spec.rb`

- All always-emit fields render (`crm_data`, `supplementaries`, society identity, truncation flags).
- Null-filter: each conditional field present when set; **absent from the hash** (not `nil`) when blank/nil/empty-string.
- `supplementaries` shape: `[]` when none; `[oab_id strings]` when present; correctly walks principal → supplementaries when queried OAB is supplementary.
- Partner sort: `socio` → `socio_de_servico` → `associado`, `oab_id` ASC within bucket.
- Truncation boundary: exactly 6 partners → no truncation. Exactly 7 → 6 returned + truncation flag + 1 stub.
- Principal exclusion: queried lawyer never appears in `partners`.
- Nested partner has no recursive `societies` key.

### `spec/requests/api/v1/lawyer_crm_spec.rb`

- Happy path 200 with `principal:` envelope.
- 404 unknown OAB.
- 422 cancelled/deceased principal.
- Auth required.
- N+1 guard with `ActiveRecord::QueryRecorder` — total queries bounded regardless of society size.

### `spec/requests/api/v1/lawyers_crm_index_spec.rb`

- Each filter independently and in combination.
- `min_lead_score` regex pre-filter: row with `lead_score: "abc"` excluded, no exception raised.
- `is_procstudio = true` excluded.
- Supplementary rows (with `principal_lawyer_id`) excluded.
- Cursor pagination: `from_oab` returns next page; `next_from_oab` `nil` on last page.
- `limit` clamp: `0 → 1`, `999 → 100`.
- 400 for non-numeric `min_lead_score`.

### `spec/requests/api/v1/lawyer_update_crm_spec.rb`

- `scraper: { scraped: true, lead_score: 75 }` persists.
- Sequential calls with `scraper: { sources: ["instagram"] }` then `scraper: { lead_score: 80 }` deep-merges (sources preserved).
- 2-level deep nesting: `scraper: { social: { instagram: "@foo" } }` persists in full.
- Key removal via `null` payload is **not supported** in this iteration; test that sending `{ scraper: { lead_score: null } }` is a no-op for that key (existing value preserved). Document the limitation.

## Out of scope

- No migrations. `crm_data` is already a JSONB-backed `store_accessor`.
- No model logic changes.
- No background jobs, no caching layer.
- No batch/bulk update endpoint — AI calls `POST /lawyer/:oab/crm` per OAB.
- No society endpoint changes — society partner enrichment happens via individual lawyer crm endpoints.
- No changes to the existing scraper-batch flow (`GET /lawyers`, `ScraperLawyerSerializer`).

## Risks & open questions resolved

- **Deep-key deletion is not supported in this iteration.** `compact` strips top-level nils; deep_merge keeps inner nils only if explicitly delivered, but the current `compact` call breaks that. Punted by design — overwrite values rather than deleting keys. Re-open if a real use case appears.
- **Partner shape redundancy with `partnership_type`:** intentional. Society-level value is the principal's role; partner-level value is that partner's role. Different facts.
- **No batch update for society partners:** the AI is expected to issue one POST per partner OAB after enrichment. Acceptable given society sizes are bounded by the `ENTERPRISE_THRESHOLD` rule and the truncation cap of 6 in this endpoint.
