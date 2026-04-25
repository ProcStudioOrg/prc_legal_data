# Lawyer CRM Endpoint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three coordinated capabilities — a token-lean `GET /lawyer/:oab/crm` for the AI scraper, an extended `POST /lawyer/:oab/crm` accepting nested `scraper`/`outreach`/`signals` hashes, and a new `GET /lawyers/crm` listing with JSONB filters and cursor pagination.

**Architecture:** Approach 1 from the spec — one new heavy serializer (`LawyerCrmSerializer`) for the read endpoint with a partner sub-serializer (`LawyerCrmPartnerSerializer`), plus a separate lean `LawyerCrmListSerializer` for the listing. A small `deep_permit_hash` helper unblocks deep nested write payloads. No migrations, no model changes.

**Tech Stack:** Rails 8.1, RSpec, FactoryBot, PostgreSQL JSONB.

**Source spec:** `docs/superpowers/specs/2026-04-25-lawyer-crm-endpoint-design.md`

---

## File Map

| File | Status | Responsibility |
|---|---|---|
| `app/controllers/api/v1/lawyers_controller.rb` | modify | Add `show_crm`, `crm_index`, extend `update_crm` permits, add `deep_permit_hash` private helper |
| `app/serializers/lawyer_crm_serializer.rb` | create | Heavy lean shape for `GET /lawyer/:oab/crm` — principal + societies + partners + truncation |
| `app/serializers/lawyer_crm_partner_serializer.rb` | create | Partner shape inside societies; same fields as principal minus `societies` (no recursion) |
| `app/serializers/lawyer_crm_list_serializer.rb` | create | Single-row shape for `GET /lawyers/crm` |
| `config/routes.rb` | modify | Add two new routes |
| `spec/serializers/lawyer_crm_serializer_spec.rb` | create | Serializer unit specs |
| `spec/requests/api/v1/lawyer_crm_spec.rb` | create | `show_crm` request specs |
| `spec/requests/api/v1/lawyers_crm_index_spec.rb` | create | `crm_index` request specs |
| `spec/requests/api/v1/lawyer_update_crm_spec.rb` | create | `update_crm` request specs (covers new nested permits) |

---

## Conventions used throughout

- Test runner: `bundle exec rspec <path>` (or `<path>:<line>` for a single example).
- Auth header in request specs: `{ "X-API-KEY" => api_key.key }`. Existing fixture pattern: `User.create(...)` + `ApiKey.create(user:, key:, active: true)`.
- After every passing test, **commit** with a conventional-commit-style message before moving to the next step. Frequent commits make subagent reviews easier.
- The null-filter rule throughout: emit a key only if `value` is not `nil` and not `""`. **Boolean `false` IS emitted.** Do not use `value.blank?` or `value.present?` — both mishandle `false`.

---

## Task 1: Routes + empty controller actions + 404/422 happy-path tests

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/api/v1/lawyers_controller.rb`
- Create: `spec/requests/api/v1/lawyer_crm_spec.rb`

- [ ] **Step 1: Write the failing 404 request spec**

Create `spec/requests/api/v1/lawyer_crm_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe "GET /api/v1/lawyer/:oab/crm", type: :request do
  let(:user)    { User.create(email: "crm_test@example.com", password: "password", admin: false) }
  let(:api_key) { ApiKey.create(user: user, key: "test_key_show_crm", active: true) }
  let(:headers) { { "X-API-KEY" => api_key.key } }

  describe "validation" do
    it "returns 401 without valid API key" do
      get "/api/v1/lawyer/PR_99999/crm", headers: { "X-API-KEY" => "invalid" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 404 when lawyer not found" do
      get "/api/v1/lawyer/PR_99999/crm", headers: headers
      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json["error"]).to include("Não Encontrado")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/api/v1/lawyer_crm_spec.rb`
Expected: FAIL — route does not exist (`ActionController::RoutingError`).

- [ ] **Step 3: Add the new routes**

Edit `config/routes.rb` to add the two new routes inside the existing `namespace :api / namespace :v1` block (just below the existing `post 'lawyer/:oab/crm'` line):

```ruby
get  'lawyer/:oab/crm', to: 'lawyers#show_crm'
get  'lawyers/crm',     to: 'lawyers#crm_index'
```

Final `routes.rb` should contain (showing existing + new together):

```ruby
get 'lawyers', to: 'lawyers#index'
get 'lawyers/crm', to: 'lawyers#crm_index'                # NEW
get 'lawyer/:oab', to: 'lawyers#show_by_oab'
get 'lawyer/:oab/crm', to: 'lawyers#show_crm'             # NEW
post 'lawyer/create', to: 'lawyers#create_lawyer'
post 'lawyer/:oab/update', to: 'lawyers#update_lawyer'
post 'lawyer/:oab/crm', to: 'lawyers#update_crm'
get 'lawyer/:oab/debug', to: 'lawyers#_debug'
get 'lawyer/state/:state/last', to: 'lawyers#last_oab_by_state'
```

> Order matters: `get 'lawyers/crm'` must come **before** `get 'lawyer/:oab'` is matched against `/lawyers/crm`. Since the existing route is `lawyer/:oab` (singular), there's no actual conflict, but defensively keep `lawyers/crm` near the top.

- [ ] **Step 4: Add stub `show_crm` action and update `set_lawyer` whitelist**

In `app/controllers/api/v1/lawyers_controller.rb`:

Update the `before_action :set_lawyer` line near the top of the class (currently `before_action :set_lawyer, only: [ :_debug, :update_lawyer, :update_crm ]`) to:

```ruby
before_action :set_lawyer, only: [ :_debug, :update_lawyer, :update_crm, :show_crm ]
```

Add a new `show_crm` action just below `show_by_oab` (line ~240):

```ruby
def show_crm
  unless @lawyer
    render json: { error: "Advogado Não Encontrado - Verifique o OAB ID" }, status: :not_found
    return
  end

  # Resolve principal: walk to principal if @lawyer is supplementary
  principal_lawyer = @lawyer.principal_lawyer_id.present? ? @lawyer.principal_lawyer : @lawyer

  unless principal_lawyer
    Rails.logger.error("Data Integrity: supplementary lawyer #{@lawyer.id} has principal_lawyer_id #{@lawyer.principal_lawyer_id} but principal not found")
    render json: { error: "Erro interno: Registro principal associado não encontrado.", request_id: request.request_id }, status: :internal_server_error
    return
  end

  status_check = verify_lawyer_status(principal_lawyer)
  unless status_check[:valid]
    render json: { error: "Status Inválido (Principal): #{status_check[:message]}" }, status: :unprocessable_entity
    return
  end

  render json: { principal: LawyerCrmSerializer.new(principal_lawyer).as_json }, status: :ok
rescue => e
  Rails.logger.error("Error in show_crm for OAB #{params[:oab]}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
  error_details = Rails.env.production? ? nil : { message: e.message, backtrace: e.backtrace&.first(5) }
  render json: {
    error: "Erro interno ao buscar advogado",
    error_type: e.class.name,
    details: error_details,
    request_id: request.request_id
  }, status: :internal_server_error
end
```

Add a stub `crm_index` action right below `show_crm` (we'll flesh it out later — for now it just needs to exist so the route doesn't 500 when other tests touch it):

```ruby
def crm_index
  render json: { lawyers: [], meta: { returned: 0, next_from_oab: nil, filters_applied: {} } }, status: :ok
end
```

> `LawyerCrmSerializer` doesn't exist yet — it'll fail at runtime when invoked. That's fine; this task only verifies the 404 path which short-circuits before serialization.

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/api/v1/lawyer_crm_spec.rb`
Expected: PASS — both 401 and 404 examples green.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/lawyers_controller.rb spec/requests/api/v1/lawyer_crm_spec.rb
git commit -m "feat: scaffold show_crm and crm_index routes with 404/auth handling"
```

---

## Task 2: `LawyerCrmSerializer` — base fields with universal null-filter

**Files:**
- Create: `app/serializers/lawyer_crm_serializer.rb`
- Create: `spec/serializers/lawyer_crm_serializer_spec.rb`

- [ ] **Step 1: Write the failing serializer unit spec**

Create `spec/serializers/lawyer_crm_serializer_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe LawyerCrmSerializer do
  describe '#as_json — base fields' do
    let(:lawyer) do
      create(:lawyer,
        full_name: "BRUNO PELLIZZETTI",
        oab_number: "54159",
        oab_id: "PR_54159",
        state: "PR",
        city: "CURITIBA",
        situation: "situação regular",
        profession: "ADVOGADO",
        address: "RUA EXEMPLO 123",
        zip_code: "80010000",
        phone_number_1: "(41) 3333-4444",
        phone_number_2: "(41) 99999-8888",
        phone_1_has_whatsapp: true,
        phone_2_has_whatsapp: false,
        email: "bruno@example.com",
        instagram: "@bruno",
        website: nil,
        specialty: nil,
        bio: nil,
        is_procstudio: false,
        crm_data: { "scraper" => { "scraped" => true } }
      )
    end

    it 'emits all populated fields' do
      result = described_class.new(lawyer).as_json
      expect(result[:full_name]).to eq("BRUNO PELLIZZETTI")
      expect(result[:oab_id]).to eq("PR_54159")
      expect(result[:state]).to eq("PR")
      expect(result[:city]).to eq("CURITIBA")
      expect(result[:situation]).to eq("situação regular")
      expect(result[:profession]).to eq("ADVOGADO")
      expect(result[:address]).to eq("RUA EXEMPLO 123")
      expect(result[:zip_code]).to eq("80010000")
      expect(result[:phone_number_1]).to eq("(41) 3333-4444")
      expect(result[:phone_number_2]).to eq("(41) 99999-8888")
      expect(result[:phone_1_has_whatsapp]).to eq(true)
      expect(result[:phone_2_has_whatsapp]).to eq(false)        # boolean false MUST be emitted
      expect(result[:email]).to eq("bruno@example.com")
      expect(result[:instagram]).to eq("@bruno")
      expect(result[:is_procstudio]).to eq(false)               # boolean false MUST be emitted
    end

    it 'always emits crm_data even when empty' do
      lawyer_no_crm = create(:lawyer, oab_id: "PR_77777", crm_data: nil)
      result = described_class.new(lawyer_no_crm).as_json
      expect(result).to have_key(:crm_data)
      expect(result[:crm_data]).to eq({})
    end

    it 'emits crm_data as stored when present' do
      result = described_class.new(lawyer).as_json
      expect(result[:crm_data]).to eq({ "scraper" => { "scraped" => true } })
    end

    it 'omits nil and empty-string fields entirely' do
      result = described_class.new(lawyer).as_json
      expect(result).not_to have_key(:website)        # nil
      expect(result).not_to have_key(:specialty)      # nil
      expect(result).not_to have_key(:bio)            # nil
    end

    it 'omits empty-string fields entirely' do
      lawyer_blank = create(:lawyer, oab_id: "PR_11111", email: "", instagram: "")
      result = described_class.new(lawyer_blank).as_json
      expect(result).not_to have_key(:email)
      expect(result).not_to have_key(:instagram)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/serializers/lawyer_crm_serializer_spec.rb`
Expected: FAIL — `NameError: uninitialized constant LawyerCrmSerializer`.

- [ ] **Step 3: Create the serializer with base + null-filter logic**

Create `app/serializers/lawyer_crm_serializer.rb`:

```ruby
class LawyerCrmSerializer
  PARTNER_LIMIT = 6

  # Field sets — keep in one place so the partner serializer can reuse them.
  ALWAYS_EMIT_FIELDS = %i[crm_data supplementaries].freeze
  CONDITIONAL_FIELDS = %i[
    full_name oab_id state city situation profession address zip_code
    phone_number_1 phone_number_2
    phone_1_has_whatsapp phone_2_has_whatsapp
    email specialty bio instagram website is_procstudio
  ].freeze

  def initialize(lawyer)
    @lawyer = lawyer
  end

  def as_json
    return nil unless @lawyer

    hash = {}
    CONDITIONAL_FIELDS.each do |field|
      value = @lawyer.public_send(field)
      hash[field] = value unless blank_for_emit?(value)
    end
    hash[:crm_data] = @lawyer.crm_data || {}
    hash[:supplementaries] = []  # filled in by Task 3
    hash[:societies] = []        # filled in by Task 4+
    hash
  end

  private

  # Drop nil and empty strings only. Boolean false must survive.
  def blank_for_emit?(value)
    value.nil? || value == ""
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/serializers/lawyer_crm_serializer_spec.rb`
Expected: PASS — all 5 examples green.

- [ ] **Step 5: Commit**

```bash
git add app/serializers/lawyer_crm_serializer.rb spec/serializers/lawyer_crm_serializer_spec.rb
git commit -m "feat: LawyerCrmSerializer base fields with null-filter rule"
```

---

## Task 3: `LawyerCrmSerializer` — supplementaries handling

**Files:**
- Modify: `app/serializers/lawyer_crm_serializer.rb`
- Modify: `spec/serializers/lawyer_crm_serializer_spec.rb`

- [ ] **Step 1: Write the failing supplementaries spec**

Append to `spec/serializers/lawyer_crm_serializer_spec.rb` inside the top-level describe block:

```ruby
describe '#as_json — supplementaries' do
  it 'returns empty array when no supplementaries' do
    lawyer = create(:lawyer, oab_id: "PR_50000")
    result = described_class.new(lawyer).as_json
    expect(result[:supplementaries]).to eq([])
  end

  it 'returns oab_id strings when lawyer is principal' do
    principal = create(:lawyer, oab_id: "DF_40007")
    create(:lawyer, oab_id: "PR_131010", principal_lawyer: principal)
    create(:lawyer, oab_id: "SP_222222", principal_lawyer: principal)

    result = described_class.new(principal.reload).as_json
    expect(result[:supplementaries]).to match_array(["PR_131010", "SP_222222"])
  end
end
```

> Note: when `show_crm` receives a supplementary OAB it walks to the principal *in the controller* before serializing. The serializer always treats its input as the principal. The serializer itself does not need to handle the supplementary-as-input case.

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bundle exec rspec spec/serializers/lawyer_crm_serializer_spec.rb`
Expected: 1 PASS (empty case — current stub returns `[]`), 1 FAIL (principal case — stub doesn't populate).

- [ ] **Step 3: Implement supplementaries**

In `app/serializers/lawyer_crm_serializer.rb`, replace the `as_json` method body:

```ruby
def as_json
  return nil unless @lawyer

  hash = {}
  CONDITIONAL_FIELDS.each do |field|
    value = @lawyer.public_send(field)
    hash[field] = value unless blank_for_emit?(value)
  end
  hash[:crm_data] = @lawyer.crm_data || {}
  hash[:supplementaries] = supplementary_oab_ids
  hash[:societies] = []  # filled in by Task 4+
  hash
end

private

def supplementary_oab_ids
  @lawyer.supplementary_lawyers.map(&:oab_id)
end

def blank_for_emit?(value)
  value.nil? || value == ""
end
```

- [ ] **Step 4: Run tests to verify all pass**

Run: `bundle exec rspec spec/serializers/lawyer_crm_serializer_spec.rb`
Expected: PASS — all base + supplementaries examples green.

- [ ] **Step 5: Commit**

```bash
git add app/serializers/lawyer_crm_serializer.rb spec/serializers/lawyer_crm_serializer_spec.rb
git commit -m "feat: LawyerCrmSerializer supplementaries as oab_id strings"
```

---

## Task 4: `LawyerCrmPartnerSerializer` + society rendering with sorted partners

**Files:**
- Create: `app/serializers/lawyer_crm_partner_serializer.rb`
- Modify: `app/serializers/lawyer_crm_serializer.rb`
- Modify: `spec/serializers/lawyer_crm_serializer_spec.rb`

- [ ] **Step 1: Write failing society + partner specs**

Append to `spec/serializers/lawyer_crm_serializer_spec.rb`:

```ruby
describe '#as_json — societies and partners' do
  it 'returns empty societies array when none' do
    lawyer = create(:lawyer, oab_id: "PR_88888")
    result = described_class.new(lawyer).as_json
    expect(result[:societies]).to eq([])
  end

  it 'renders society identity and the principal\'s partnership_type' do
    principal = create(:lawyer, oab_id: "PR_54159")
    society = create(:society, name: "PELLIZZETTI E WALBER", oab_id: "12345/6", inscricao: 567890,
                              state: "PR", city: "CURITIBA", address: "Sala 502", phone: "(41) 3333-4444",
                              situacao: "Ativo", number_of_partners: 2)
    create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)

    result = described_class.new(principal.reload).as_json
    soc = result[:societies].first

    expect(soc[:name]).to eq("PELLIZZETTI E WALBER")
    expect(soc[:oab_id]).to eq("12345/6")
    expect(soc[:inscricao]).to eq(567890)
    expect(soc[:state]).to eq("PR")
    expect(soc[:city]).to eq("CURITIBA")
    expect(soc[:address]).to eq("Sala 502")
    expect(soc[:phone]).to eq("(41) 3333-4444")
    expect(soc[:situacao]).to eq("Ativo")
    expect(soc[:number_of_partners]).to eq(2)
    expect(soc[:partnership_type]).to eq("socio")
  end

  it 'excludes the queried principal from partners' do
    principal = create(:lawyer, oab_id: "PR_54159", full_name: "BRUNO")
    walber    = create(:lawyer, oab_id: "PR_88231", full_name: "WALBER")
    society = create(:society, name: "PELLIZZETTI E WALBER", number_of_partners: 2)
    create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)
    create(:lawyer_society, lawyer: walber,    society: society, partnership_type: :socio)

    result = described_class.new(principal.reload).as_json
    soc = result[:societies].first

    expect(soc[:partners].length).to eq(1)
    expect(soc[:partners].first[:full_name]).to eq("WALBER")
    expect(soc[:partners].first[:oab_id]).to eq("PR_88231")
    expect(soc[:partners].first[:partnership_type]).to eq("socio")
  end

  it 'sorts partners by partnership_type bucket then oab_id ASC' do
    principal = create(:lawyer, oab_id: "PR_00001")
    society = create(:society, number_of_partners: 6)
    create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)

    a = create(:lawyer, oab_id: "PR_00100")
    b = create(:lawyer, oab_id: "PR_00200")
    c = create(:lawyer, oab_id: "PR_00300")
    d = create(:lawyer, oab_id: "PR_00400")
    e = create(:lawyer, oab_id: "PR_00500")

    # Mix the order at insertion time to prove the sort is real
    create(:lawyer_society, lawyer: c, society: society, partnership_type: :associado)
    create(:lawyer_society, lawyer: a, society: society, partnership_type: :socio)
    create(:lawyer_society, lawyer: e, society: society, partnership_type: :socio_de_servico)
    create(:lawyer_society, lawyer: b, society: society, partnership_type: :socio)
    create(:lawyer_society, lawyer: d, society: society, partnership_type: :socio_de_servico)

    result = described_class.new(principal.reload).as_json
    partner_oabs = result[:societies].first[:partners].map { |p| p[:oab_id] }

    # socio (PR_00100, PR_00200) -> socio_de_servico (PR_00400, PR_00500) -> associado (PR_00300)
    expect(partner_oabs).to eq(["PR_00100", "PR_00200", "PR_00400", "PR_00500", "PR_00300"])
  end

  it 'partners use null-filter rule (boolean false emitted, nil omitted)' do
    principal = create(:lawyer, oab_id: "PR_00001")
    partner = create(:lawyer, oab_id: "PR_00002", phone_2_has_whatsapp: false, website: nil, instagram: "@p")
    society = create(:society, number_of_partners: 2)
    create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)
    create(:lawyer_society, lawyer: partner,   society: society, partnership_type: :socio)

    result = described_class.new(principal.reload).as_json
    p = result[:societies].first[:partners].first
    expect(p[:instagram]).to eq("@p")
    expect(p[:phone_2_has_whatsapp]).to eq(false)
    expect(p).not_to have_key(:website)
  end

  it 'partners include their own crm_data and supplementaries oab_id list' do
    principal = create(:lawyer, oab_id: "PR_00001")
    partner = create(:lawyer, oab_id: "PR_00002", crm_data: { "outreach" => { "stage" => "new" } })
    create(:lawyer, oab_id: "SP_55555", principal_lawyer: partner)

    society = create(:society, number_of_partners: 2)
    create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)
    create(:lawyer_society, lawyer: partner,   society: society, partnership_type: :socio)

    result = described_class.new(principal.reload).as_json
    p = result[:societies].first[:partners].first
    expect(p[:crm_data]).to eq({ "outreach" => { "stage" => "new" } })
    expect(p[:supplementaries]).to eq(["SP_55555"])
  end

  it 'partners do not recurse into societies' do
    principal = create(:lawyer, oab_id: "PR_00001")
    partner = create(:lawyer, oab_id: "PR_00002")
    society = create(:society, number_of_partners: 2)
    create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)
    create(:lawyer_society, lawyer: partner,   society: society, partnership_type: :socio)

    result = described_class.new(principal.reload).as_json
    p = result[:societies].first[:partners].first
    expect(p).not_to have_key(:societies)
  end
end
```

- [ ] **Step 2: Run to confirm failures**

Run: `bundle exec rspec spec/serializers/lawyer_crm_serializer_spec.rb`
Expected: empty-societies passes; everything else fails — `societies` is still hardcoded `[]`.

- [ ] **Step 3: Create the partner sub-serializer**

Create `app/serializers/lawyer_crm_partner_serializer.rb`:

```ruby
class LawyerCrmPartnerSerializer
  # Same conditional fields as the principal — see LawyerCrmSerializer::CONDITIONAL_FIELDS
  CONDITIONAL_FIELDS = LawyerCrmSerializer::CONDITIONAL_FIELDS

  def initialize(lawyer, partnership_type:)
    @lawyer = lawyer
    @partnership_type = partnership_type
  end

  def as_json
    hash = {}
    CONDITIONAL_FIELDS.each do |field|
      value = @lawyer.public_send(field)
      hash[field] = value unless blank_for_emit?(value)
    end
    hash[:partnership_type] = @partnership_type if @partnership_type
    hash[:crm_data] = @lawyer.crm_data || {}
    hash[:supplementaries] = @lawyer.supplementary_lawyers.map(&:oab_id)
    hash
  end

  private

  def blank_for_emit?(value)
    value.nil? || value == ""
  end
end
```

- [ ] **Step 4: Implement society rendering in `LawyerCrmSerializer`**

Replace the `as_json` method (and add society/partner helpers) in `app/serializers/lawyer_crm_serializer.rb`. The full file should now be:

```ruby
class LawyerCrmSerializer
  PARTNER_LIMIT = 6

  # Sort buckets by partnership_type — must match LawyerSociety enum keys.
  PARTNERSHIP_SORT_ORDER = {
    "socio"            => 0,
    "socio_de_servico" => 1,
    "associado"        => 2
  }.freeze

  ALWAYS_EMIT_FIELDS = %i[crm_data supplementaries].freeze
  CONDITIONAL_FIELDS = %i[
    full_name oab_id state city situation profession address zip_code
    phone_number_1 phone_number_2
    phone_1_has_whatsapp phone_2_has_whatsapp
    email specialty bio instagram website is_procstudio
  ].freeze

  SOCIETY_CONDITIONAL_FIELDS = %i[
    state city address phone situacao number_of_partners partnership_type
  ].freeze

  def initialize(lawyer)
    @lawyer = lawyer
  end

  def as_json
    return nil unless @lawyer

    hash = {}
    CONDITIONAL_FIELDS.each do |field|
      value = @lawyer.public_send(field)
      hash[field] = value unless blank_for_emit?(value)
    end
    hash[:crm_data] = @lawyer.crm_data || {}
    hash[:supplementaries] = @lawyer.supplementary_lawyers.map(&:oab_id)
    hash[:societies] = serialize_societies
    hash
  end

  private

  def blank_for_emit?(value)
    value.nil? || value == ""
  end

  def serialize_societies
    @lawyer.lawyer_societies.map { |ls| serialize_society(ls) }
  end

  def serialize_society(ls)
    society = ls.society
    soc_hash = {
      name: society.name,
      oab_id: society.oab_id,
      inscricao: society.inscricao
    }

    # Always-emit identity fields done above. Conditional society fields next.
    {
      state: society.state,
      city: society.city,
      address: society.address,
      phone: society.phone,
      situacao: society.situacao,
      number_of_partners: society.number_of_partners,
      partnership_type: ls.partnership_type
    }.each do |key, value|
      soc_hash[key] = value unless blank_for_emit?(value)
    end

    sorted = sorted_other_partners(society)
    soc_hash[:partners] = sorted.first(PARTNER_LIMIT).map { |partner_ls|
      LawyerCrmPartnerSerializer.new(partner_ls.lawyer, partnership_type: partner_ls.partnership_type).as_json
    }
    soc_hash[:truncated_partners] = sorted.length > PARTNER_LIMIT
    soc_hash[:truncated_partner_oabs] = if sorted.length > PARTNER_LIMIT
      sorted.drop(PARTNER_LIMIT).map { |partner_ls| { oab_id: partner_ls.lawyer.oab_id } }
    else
      []
    end

    soc_hash
  end

  def sorted_other_partners(society)
    society.lawyer_societies
      .reject { |partner_ls| partner_ls.lawyer_id == @lawyer.id }
      .sort_by { |partner_ls|
        [
          PARTNERSHIP_SORT_ORDER.fetch(partner_ls.partnership_type, 99),
          partner_ls.lawyer.oab_id.to_s
        ]
      }
  end
end
```

> The `sort_by` reads `partner_ls.lawyer.oab_id` — this triggers an N+1 unless the controller eager-loads `lawyer_societies: { society: { lawyer_societies: :lawyer } }`. Task 6 wires that up in `show_crm`.

- [ ] **Step 5: Run all serializer specs**

Run: `bundle exec rspec spec/serializers/lawyer_crm_serializer_spec.rb`
Expected: all examples PASS.

- [ ] **Step 6: Commit**

```bash
git add app/serializers/lawyer_crm_partner_serializer.rb app/serializers/lawyer_crm_serializer.rb spec/serializers/lawyer_crm_serializer_spec.rb
git commit -m "feat: LawyerCrmPartnerSerializer + society rendering with sorted partners"
```

---

## Task 5: Truncation logic for societies with >6 other partners

**Files:**
- Modify: `spec/serializers/lawyer_crm_serializer_spec.rb`

> The implementation in Task 4 already handles truncation. This task locks in the boundary behavior with explicit tests.

- [ ] **Step 1: Write failing truncation specs**

Append to `spec/serializers/lawyer_crm_serializer_spec.rb`:

```ruby
describe '#as_json — partner truncation' do
  let(:principal) { create(:lawyer, oab_id: "PR_00001") }

  def setup_society_with_other_partners(other_partner_count)
    society = create(:society, number_of_partners: other_partner_count + 1)
    create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)
    other_partner_count.times do |i|
      partner = create(:lawyer, oab_id: "PR_#{format('%05d', 10000 + i)}")
      create(:lawyer_society, lawyer: partner, society: society, partnership_type: :socio)
    end
    society
  end

  it 'returns truncated_partners=false when exactly 6 other partners' do
    setup_society_with_other_partners(6)
    result = described_class.new(principal.reload).as_json
    soc = result[:societies].first
    expect(soc[:partners].length).to eq(6)
    expect(soc[:truncated_partners]).to eq(false)
    expect(soc[:truncated_partner_oabs]).to eq([])
  end

  it 'returns truncated_partners=true when 7 other partners; 1 stub' do
    setup_society_with_other_partners(7)
    result = described_class.new(principal.reload).as_json
    soc = result[:societies].first
    expect(soc[:partners].length).to eq(6)
    expect(soc[:truncated_partners]).to eq(true)
    expect(soc[:truncated_partner_oabs].length).to eq(1)
    expect(soc[:truncated_partner_oabs].first).to have_key(:oab_id)
  end

  it 'returns truncated_partners=true when 10 other partners; 4 stubs' do
    setup_society_with_other_partners(10)
    result = described_class.new(principal.reload).as_json
    soc = result[:societies].first
    expect(soc[:partners].length).to eq(6)
    expect(soc[:truncated_partner_oabs].length).to eq(4)
    expect(soc[:truncated_partner_oabs].all? { |s| s.keys == [:oab_id] }).to eq(true)
  end

  it 'truncated stubs continue the same sort order as partners' do
    setup_society_with_other_partners(8)
    result = described_class.new(principal.reload).as_json
    soc = result[:societies].first
    rendered_oabs = soc[:partners].map { |p| p[:oab_id] }
    truncated_oabs = soc[:truncated_partner_oabs].map { |s| s[:oab_id] }
    # Concatenated sequence is sorted ASC for the all-socio bucket
    full = rendered_oabs + truncated_oabs
    expect(full).to eq(full.sort)
  end
end
```

- [ ] **Step 2: Run truncation specs**

Run: `bundle exec rspec spec/serializers/lawyer_crm_serializer_spec.rb -e "partner truncation"`
Expected: PASS — implementation from Task 4 already covers this.

> If any spec fails, the bug is in `LawyerCrmSerializer#serialize_society` truncation arithmetic. Fix there, then re-run.

- [ ] **Step 3: Commit**

```bash
git add spec/serializers/lawyer_crm_serializer_spec.rb
git commit -m "test: lock partner truncation boundaries (6/7/10 + sort order)"
```

---

## Task 6: `show_crm` — full happy-path request specs + N+1 guard

**Files:**
- Modify: `app/controllers/api/v1/lawyers_controller.rb`
- Modify: `spec/requests/api/v1/lawyer_crm_spec.rb`

- [ ] **Step 1: Write failing happy-path + N+1 + status-check specs**

Append to `spec/requests/api/v1/lawyer_crm_spec.rb` inside the top-level describe block:

```ruby
describe "happy path" do
  before do
    @principal = create(:lawyer,
      oab_id: "PR_54159", full_name: "BRUNO PELLIZZETTI", state: "PR", city: "CURITIBA",
      situation: "situação regular", profession: "ADVOGADO", address: "RUA EXEMPLO 123",
      zip_code: "80010000", phone_number_1: "(41) 3333-4444", phone_number_2: "(41) 99999-8888",
      email: "bruno@example.com", instagram: "@bruno",
      crm_data: { "scraper" => { "scraped" => true } }
    )
  end

  it "returns 200 with principal envelope" do
    get "/api/v1/lawyer/PR_54159/crm", headers: headers
    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json).to have_key("principal")
    expect(json["principal"]["full_name"]).to eq("BRUNO PELLIZZETTI")
    expect(json["principal"]["oab_id"]).to eq("PR_54159")
    expect(json["principal"]["crm_data"]).to eq({ "scraper" => { "scraped" => true } })
    expect(json["principal"]["supplementaries"]).to eq([])
    expect(json["principal"]["societies"]).to eq([])
  end

  it "walks supplementary -> principal when querying supplementary OAB" do
    create(:lawyer, oab_id: "SP_99999", principal_lawyer: @principal)
    get "/api/v1/lawyer/SP_99999/crm", headers: headers
    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["principal"]["oab_id"]).to eq("PR_54159")
    expect(json["principal"]["supplementaries"]).to eq(["SP_99999"])
  end
end

describe "status validation" do
  it "returns 422 when principal is cancelled" do
    create(:lawyer, oab_id: "PR_88888", situation: "cancelado")
    get "/api/v1/lawyer/PR_88888/crm", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to include("Status Inválido")
  end

  it "returns 422 when principal is deceased" do
    create(:lawyer, oab_id: "PR_77777", situation: "falecido")
    get "/api/v1/lawyer/PR_77777/crm", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

describe "N+1 guard" do
  it "stays within a query budget regardless of society size" do
    principal = create(:lawyer, oab_id: "PR_30001")
    society = create(:society, number_of_partners: 8)
    create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)
    7.times do |i|
      partner = create(:lawyer, oab_id: "PR_3010#{i}")
      create(:lawyer_society, lawyer: partner, society: society, partnership_type: :socio)
    end

    query_count = 0
    counter = ->(_, _, _, _, payload) { query_count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get "/api/v1/lawyer/PR_30001/crm", headers: headers
    end

    # Expected queries: api_key auth (~2) + lawyer + principal + supplementaries + lawyer_societies
    # + societies + societies' lawyer_societies + their lawyers. Allow generous headroom.
    expect(query_count).to be < 20
    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 2: Run to confirm failures**

Run: `bundle exec rspec spec/requests/api/v1/lawyer_crm_spec.rb`
Expected: 401/404 PASS (from Task 1). Happy-path FAILS — `LawyerCrmSerializer` lookup fails on a non-eager-loaded record (`@lawyer.supplementary_lawyers` triggers fresh queries) and the action probably renders OK but the N+1 guard exceeds budget.

> Actually the 200 happy path should already pass since Task 4 made the serializer work end-to-end. The failures we want to fix here are the N+1 budget and the supplementary-walking case (controller hands `@lawyer` to the serializer; for a supplementary record, `@lawyer.principal_lawyer` triggers another fetch unless eager-loaded).

- [ ] **Step 3: Add eager loading in `show_crm`**

Edit `app/controllers/api/v1/lawyers_controller.rb`. Replace the `set_lawyer` helper to support eager-loading specifically for `show_crm` — but to avoid side effects on `_debug`/`update_lawyer`/`update_crm`, instead refresh the record with includes inside `show_crm` itself.

Replace the `show_crm` method body:

```ruby
def show_crm
  unless @lawyer
    render json: { error: "Advogado Não Encontrado - Verifique o OAB ID" }, status: :not_found
    return
  end

  # Re-fetch with eager loading so the serializer doesn't N+1.
  base_relation = Lawyer.includes(
    :supplementary_lawyers,
    :principal_lawyer,
    lawyer_societies: { society: { lawyer_societies: :lawyer } }
  )
  loaded = base_relation.find_by(id: @lawyer.id)

  principal_lawyer = loaded.principal_lawyer_id.present? ? loaded.principal_lawyer : loaded
  # When walking principal -> reload principal with the same eager set so partner societies are loaded.
  if loaded.principal_lawyer_id.present?
    principal_lawyer = base_relation.find_by(id: loaded.principal_lawyer_id)
  end

  unless principal_lawyer
    Rails.logger.error("Data Integrity: supplementary lawyer #{loaded.id} has principal_lawyer_id #{loaded.principal_lawyer_id} but principal not found")
    render json: { error: "Erro interno: Registro principal associado não encontrado.", request_id: request.request_id }, status: :internal_server_error
    return
  end

  status_check = verify_lawyer_status(principal_lawyer)
  unless status_check[:valid]
    render json: { error: "Status Inválido (Principal): #{status_check[:message]}" }, status: :unprocessable_entity
    return
  end

  render json: { principal: LawyerCrmSerializer.new(principal_lawyer).as_json }, status: :ok
rescue => e
  Rails.logger.error("Error in show_crm for OAB #{params[:oab]}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
  error_details = Rails.env.production? ? nil : { message: e.message, backtrace: e.backtrace&.first(5) }
  render json: {
    error: "Erro interno ao buscar advogado",
    error_type: e.class.name,
    details: error_details,
    request_id: request.request_id
  }, status: :internal_server_error
end
```

- [ ] **Step 4: Run all show_crm specs**

Run: `bundle exec rspec spec/requests/api/v1/lawyer_crm_spec.rb`
Expected: all PASS — auth, 404, happy path, supplementary walk, 422 cancelled/deceased, N+1 budget.

> If the N+1 guard fails, raise the budget cautiously to ~25 only after inspecting `query_count` and confirming no per-partner repetition. The structural fix is in eager loading, not in raising the limit.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/lawyers_controller.rb spec/requests/api/v1/lawyer_crm_spec.rb
git commit -m "feat: show_crm action with eager loading and supplementary walk"
```

---

## Task 7: `deep_permit_hash` helper + extend `update_crm` permits

**Files:**
- Modify: `app/controllers/api/v1/lawyers_controller.rb`
- Create: `spec/requests/api/v1/lawyer_update_crm_spec.rb`

- [ ] **Step 1: Write failing nested-permit specs**

Create `spec/requests/api/v1/lawyer_update_crm_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe "POST /api/v1/lawyer/:oab/crm", type: :request do
  let(:user) do
    User.create(email: "crm_writer@example.com", password: "password", admin: true)  # admin needed for authorize_write!
  end
  let(:api_key) { ApiKey.create(user: user, key: "test_key_update_crm", active: true) }
  let(:headers) { { "X-API-KEY" => api_key.key, "CONTENT_TYPE" => "application/json" } }
  let!(:lawyer) { create(:lawyer, oab_id: "PR_60001", crm_data: {}) }

  describe "nested scraper hash" do
    it "persists a flat scraper sub-hash" do
      post "/api/v1/lawyer/PR_60001/crm",
        params: { scraper: { scraped: true, lead_score: 75 } }.to_json,
        headers: headers
      expect(response).to have_http_status(:ok)
      lawyer.reload
      expect(lawyer.crm_data["scraper"]).to eq({ "scraped" => true, "lead_score" => 75 })
    end

    it "deep-merges sequential scraper updates (preserves existing keys)" do
      post "/api/v1/lawyer/PR_60001/crm",
        params: { scraper: { sources: ["instagram"] } }.to_json,
        headers: headers
      post "/api/v1/lawyer/PR_60001/crm",
        params: { scraper: { lead_score: 80 } }.to_json,
        headers: headers
      lawyer.reload
      expect(lawyer.crm_data["scraper"]).to include("sources" => ["instagram"], "lead_score" => 80)
    end

    it "replaces array values (does not concatenate)" do
      post "/api/v1/lawyer/PR_60001/crm",
        params: { scraper: { sources: ["instagram"] } }.to_json,
        headers: headers
      post "/api/v1/lawyer/PR_60001/crm",
        params: { scraper: { sources: ["linkedin"] } }.to_json,
        headers: headers
      lawyer.reload
      expect(lawyer.crm_data["scraper"]["sources"]).to eq(["linkedin"])
    end

    it "persists 2-level deep nesting (deep_permit_hash works)" do
      post "/api/v1/lawyer/PR_60001/crm",
        params: { scraper: { social: { instagram: "@foo", linkedin: "u/bar" } } }.to_json,
        headers: headers
      lawyer.reload
      expect(lawyer.crm_data["scraper"]["social"]).to eq({ "instagram" => "@foo", "linkedin" => "u/bar" })
    end
  end

  describe "outreach + signals hashes" do
    it "persists outreach.stage" do
      post "/api/v1/lawyer/PR_60001/crm",
        params: { outreach: { stage: "contacted", contacted_at: "2026-04-25" } }.to_json,
        headers: headers
      lawyer.reload
      expect(lawyer.crm_data["outreach"]).to eq({ "stage" => "contacted", "contacted_at" => "2026-04-25" })
    end

    it "persists signals.has_website" do
      post "/api/v1/lawyer/PR_60001/crm",
        params: { signals: { has_website: true, has_linkedin: false } }.to_json,
        headers: headers
      lawyer.reload
      expect(lawyer.crm_data["signals"]).to eq({ "has_website" => true, "has_linkedin" => false })
    end
  end

  describe "key removal limitation" do
    it "ignores explicit nil at the deep level (existing value preserved)" do
      post "/api/v1/lawyer/PR_60001/crm",
        params: { scraper: { lead_score: 75 } }.to_json,
        headers: headers
      post "/api/v1/lawyer/PR_60001/crm",
        params: { scraper: { lead_score: nil } }.to_json,
        headers: headers
      lawyer.reload
      # Per spec: deep-key deletion is intentionally not supported in this iteration.
      expect(lawyer.crm_data["scraper"]).to have_key("lead_score")
    end
  end

  describe "preserves existing flat fields when sending nested" do
    it "does not wipe top-level researched flag when patching scraper" do
      lawyer.update!(crm_data: { "researched" => true, "scraper" => { "scraped" => false } })
      post "/api/v1/lawyer/PR_60001/crm",
        params: { scraper: { scraped: true } }.to_json,
        headers: headers
      lawyer.reload
      expect(lawyer.crm_data["researched"]).to eq(true)
      expect(lawyer.crm_data["scraper"]["scraped"]).to eq(true)
    end
  end
end
```

> The user fixture sets `admin: true` because `authorize_write!` (in `ApiAuthentication`) requires it. Verify the existing concern's contract — if a different mechanism is used (e.g., per-key write scope), match that pattern instead. Look at `app/controllers/concerns/api_authentication.rb` if `admin: true` is rejected.

- [ ] **Step 2: Run to confirm failures**

Run: `bundle exec rspec spec/requests/api/v1/lawyer_update_crm_spec.rb`
Expected: deep-nesting test FAILS — `permit(scraper: {})` drops the inner `social` hash silently. Other tests may pass partially since `permit(scraper: {})` accepts a flat sub-hash.

- [ ] **Step 3: Add `deep_permit_hash` helper and extend `update_crm`**

Edit `app/controllers/api/v1/lawyers_controller.rb`. In the `update_crm` method, replace the body with:

```ruby
def update_crm
  unless @lawyer
    render json: { error: "Advogado não encontrado" }, status: :not_found
    return
  end

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

  if crm_params.empty?
    render json: { error: "Nenhum parâmetro CRM fornecido" }, status: :bad_request
    return
  end

  begin
    current_crm = @lawyer.crm_data || {}
    new_crm = current_crm.deep_merge(crm_params.compact)

    if @lawyer.update(crm_data: new_crm)
      render json: {
        message: "Dados CRM atualizados com sucesso",
        oab_id: @lawyer.oab_id,
        crm_data: @lawyer.crm_data
      }, status: :ok
    else
      render json: {
        error: "Erro ao atualizar dados CRM",
        details: @lawyer.errors.full_messages
      }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error("Error updating CRM for lawyer #{@lawyer.oab_id}: #{e.message}")
    error_details = Rails.env.production? ? nil : { message: e.message, backtrace: e.backtrace&.first(5) }
    render json: {
      error: "Erro interno ao atualizar dados CRM",
      error_type: e.class.name,
      details: error_details,
      request_id: request.request_id
    }, status: :internal_server_error
  end
end
```

Add the `deep_permit_hash` private method just after `set_lawyer` (around line 489):

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

- [ ] **Step 4: Run update_crm specs**

Run: `bundle exec rspec spec/requests/api/v1/lawyer_update_crm_spec.rb`
Expected: all examples PASS.

> If `admin: true` is not the right mechanism for `authorize_write!`, the spec returns 403/401 on every POST. Inspect `app/controllers/concerns/api_authentication.rb`, adjust the `let(:user)` setup, and re-run. Do not change `authorize_write!` itself — match its contract from the spec side.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/lawyers_controller.rb spec/requests/api/v1/lawyer_update_crm_spec.rb
git commit -m "feat: extend update_crm with nested scraper/outreach/signals via deep_permit_hash"
```

---

## Task 8: `LawyerCrmListSerializer` for the listing endpoint

**Files:**
- Create: `app/serializers/lawyer_crm_list_serializer.rb`

> No dedicated test file for this — it's exercised through `crm_index` request specs in Task 9. Pure data-shape serializer; if `crm_index` request specs pass, this works.

- [ ] **Step 1: Create the list serializer**

Create `app/serializers/lawyer_crm_list_serializer.rb`:

```ruby
class LawyerCrmListSerializer
  CONDITIONAL_FIELDS = %i[
    full_name oab_id state city
    phone_number_1 phone_number_2 email
    instagram website
    has_society
  ].freeze

  def initialize(lawyer)
    @lawyer = lawyer
  end

  def as_json
    return nil unless @lawyer

    hash = {}
    CONDITIONAL_FIELDS.each do |field|
      value = @lawyer.public_send(field)
      hash[field] = value unless blank_for_emit?(value)
    end
    hash[:crm_data] = @lawyer.crm_data || {}
    hash
  end

  private

  def blank_for_emit?(value)
    value.nil? || value == ""
  end
end
```

- [ ] **Step 2: Sanity-check the file loads**

Run: `bundle exec rails runner 'puts LawyerCrmListSerializer.new(Lawyer.first).as_json.inspect'`
Expected: prints a hash without raising. (If no lawyers exist locally, skip — Task 9 will exercise the serializer.)

- [ ] **Step 3: Commit**

```bash
git add app/serializers/lawyer_crm_list_serializer.rb
git commit -m "feat: LawyerCrmListSerializer for crm_index list rows"
```

---

## Task 9: `crm_index` — happy path, default scope, state filter

**Files:**
- Modify: `app/controllers/api/v1/lawyers_controller.rb`
- Create: `spec/requests/api/v1/lawyers_crm_index_spec.rb`

- [ ] **Step 1: Write failing happy-path + default-scope specs**

Create `spec/requests/api/v1/lawyers_crm_index_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe "GET /api/v1/lawyers/crm", type: :request do
  let(:user)    { User.create(email: "crm_idx@example.com", password: "password", admin: false) }
  let(:api_key) { ApiKey.create(user: user, key: "test_key_crm_index", active: true) }
  let(:headers) { { "X-API-KEY" => api_key.key } }

  describe "auth + happy path" do
    before do
      create(:lawyer, oab_id: "PR_70001", state: "PR", crm_data: { "scraper" => { "scraped" => "true" } })
    end

    it "returns 401 without API key" do
      get "/api/v1/lawyers/crm", headers: { "X-API-KEY" => "invalid" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 with lawyers + meta envelope" do
      get "/api/v1/lawyers/crm", headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to have_key("lawyers")
      expect(json).to have_key("meta")
      expect(json["meta"]).to have_key("returned")
      expect(json["meta"]).to have_key("next_from_oab")
      expect(json["meta"]).to have_key("filters_applied")
    end
  end

  describe "default scope: principals only, no procstudio" do
    before do
      @principal = create(:lawyer, oab_id: "PR_71001", state: "PR")
      create(:lawyer, oab_id: "SP_71002", state: "SP", principal_lawyer: @principal)
      create(:lawyer, oab_id: "PR_71003", state: "PR", is_procstudio: true)
      create(:lawyer, oab_id: "PR_71004", state: "PR", is_procstudio: nil)
      create(:lawyer, oab_id: "PR_71005", state: "PR", is_procstudio: false)
    end

    it "excludes supplementary records" do
      get "/api/v1/lawyers/crm", headers: headers
      json = JSON.parse(response.body)
      oab_ids = json["lawyers"].map { |l| l["oab_id"] }
      expect(oab_ids).not_to include("SP_71002")
    end

    it "excludes is_procstudio = true" do
      get "/api/v1/lawyers/crm", headers: headers
      json = JSON.parse(response.body)
      oab_ids = json["lawyers"].map { |l| l["oab_id"] }
      expect(oab_ids).not_to include("PR_71003")
      expect(oab_ids).to include("PR_71001", "PR_71004", "PR_71005")
    end
  end

  describe "state filter" do
    before do
      create(:lawyer, oab_id: "PR_72001", state: "PR")
      create(:lawyer, oab_id: "SP_72002", state: "SP")
    end

    it "filters by state" do
      get "/api/v1/lawyers/crm", params: { state: "PR" }, headers: headers
      json = JSON.parse(response.body)
      oab_ids = json["lawyers"].map { |l| l["oab_id"] }
      expect(oab_ids).to include("PR_72001")
      expect(oab_ids).not_to include("SP_72002")
    end

    it "returns 400 for invalid state" do
      get "/api/v1/lawyers/crm", params: { state: "XX" }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "row shape" do
    before { create(:lawyer, oab_id: "PR_73001", state: "PR", instagram: "@foo", website: nil, crm_data: { "outreach" => { "stage" => "new" } }) }

    it "renders LawyerCrmListSerializer fields and emits crm_data" do
      get "/api/v1/lawyers/crm", headers: headers
      json = JSON.parse(response.body)
      row = json["lawyers"].find { |l| l["oab_id"] == "PR_73001" }
      expect(row).to have_key("full_name")
      expect(row).to have_key("crm_data")
      expect(row["crm_data"]).to eq({ "outreach" => { "stage" => "new" } })
      expect(row["instagram"]).to eq("@foo")
      expect(row).not_to have_key("website")  # null-filtered
    end
  end
end
```

- [ ] **Step 2: Run to confirm failures**

Run: `bundle exec rspec spec/requests/api/v1/lawyers_crm_index_spec.rb`
Expected: tests fail — stub `crm_index` from Task 1 returns empty.

- [ ] **Step 3: Implement `crm_index` with default scope + state filter**

Edit `app/controllers/api/v1/lawyers_controller.rb`. Replace the stub `crm_index` from Task 1 with:

```ruby
def crm_index
  state = params[:state]&.upcase

  if state.present? && !VALID_STATES.include?(state)
    render json: { error: "Estado inválido. Estados válidos: #{VALID_STATES.join(', ')}" }, status: :bad_request
    return
  end

  limit = [[params.fetch(:limit, 50).to_i, 1].max, 100].min

  lawyers = Lawyer
    .where("is_procstudio IS NULL OR is_procstudio = false")
    .where(principal_lawyer_id: nil)

  lawyers = lawyers.where(state: state) if state.present?

  lawyers = lawyers.order(oab_id: :desc).limit(limit + 1)

  records = lawyers.to_a
  has_more = records.length > limit
  page = has_more ? records.first(limit) : records

  serialized = page.map { |l| LawyerCrmListSerializer.new(l).as_json }
  next_from_oab = has_more ? page.last.oab_id : nil

  render json: {
    lawyers: serialized,
    meta: {
      returned: serialized.length,
      next_from_oab: next_from_oab,
      filters_applied: filters_applied_summary
    }
  }, status: :ok
rescue => e
  Rails.logger.error("Error in crm_index: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
  render json: {
    error: "Erro interno ao listar advogados (CRM)",
    error_type: e.class.name,
    request_id: request.request_id
  }, status: :internal_server_error
end
```

Add a private helper just below `set_lawyer`:

```ruby
def filters_applied_summary
  {
    state: params[:state]&.upcase,
    scraped: params[:scraped],
    stage: params[:stage],
    min_lead_score: params[:min_lead_score],
    has_instagram: params[:has_instagram],
    has_website: params[:has_website],
    from_oab: params[:from_oab]
  }.compact
end
```

- [ ] **Step 4: Run crm_index specs**

Run: `bundle exec rspec spec/requests/api/v1/lawyers_crm_index_spec.rb`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/lawyers_controller.rb spec/requests/api/v1/lawyers_crm_index_spec.rb
git commit -m "feat: crm_index basic listing with default scope and state filter"
```

---

## Task 10: `crm_index` — JSONB filters: scraped, stage, has_instagram, has_website

**Files:**
- Modify: `app/controllers/api/v1/lawyers_controller.rb`
- Modify: `spec/requests/api/v1/lawyers_crm_index_spec.rb`

- [ ] **Step 1: Write failing JSONB-filter specs**

Append to `spec/requests/api/v1/lawyers_crm_index_spec.rb`:

```ruby
describe "scraped filter" do
  before do
    create(:lawyer, oab_id: "PR_74001", state: "PR", crm_data: { "scraper" => { "scraped" => "true" } })
    create(:lawyer, oab_id: "PR_74002", state: "PR", crm_data: { "scraper" => { "scraped" => "false" } })
    create(:lawyer, oab_id: "PR_74003", state: "PR", crm_data: {})
  end

  it "returns only rows with crm_data.scraper.scraped = 'true' when scraped=true" do
    get "/api/v1/lawyers/crm", params: { scraped: "true" }, headers: headers
    oab_ids = JSON.parse(response.body)["lawyers"].map { |l| l["oab_id"] }
    expect(oab_ids).to include("PR_74001")
    expect(oab_ids).not_to include("PR_74002", "PR_74003")
  end
end

describe "stage filter" do
  before do
    create(:lawyer, oab_id: "PR_75001", state: "PR", crm_data: { "outreach" => { "stage" => "contacted" } })
    create(:lawyer, oab_id: "PR_75002", state: "PR", crm_data: { "outreach" => { "stage" => "new" } })
  end

  it "filters by exact stage match" do
    get "/api/v1/lawyers/crm", params: { stage: "contacted" }, headers: headers
    oab_ids = JSON.parse(response.body)["lawyers"].map { |l| l["oab_id"] }
    expect(oab_ids).to include("PR_75001")
    expect(oab_ids).not_to include("PR_75002")
  end
end

describe "has_instagram filter" do
  before do
    create(:lawyer, oab_id: "PR_76001", state: "PR", instagram: "@foo")
    create(:lawyer, oab_id: "PR_76002", state: "PR", instagram: nil)
    create(:lawyer, oab_id: "PR_76003", state: "PR", instagram: "")
  end

  it "returns only rows with non-empty instagram when has_instagram=true" do
    get "/api/v1/lawyers/crm", params: { has_instagram: "true" }, headers: headers
    oab_ids = JSON.parse(response.body)["lawyers"].map { |l| l["oab_id"] }
    expect(oab_ids).to eq(["PR_76001"])
  end
end

describe "has_website filter" do
  before do
    create(:lawyer, oab_id: "PR_77001", state: "PR", website: "https://x.com")
    create(:lawyer, oab_id: "PR_77002", state: "PR", website: nil)
    create(:lawyer, oab_id: "PR_77003", state: "PR", website: "")
  end

  it "returns only rows with non-empty website when has_website=true" do
    get "/api/v1/lawyers/crm", params: { has_website: "true" }, headers: headers
    oab_ids = JSON.parse(response.body)["lawyers"].map { |l| l["oab_id"] }
    expect(oab_ids).to eq(["PR_77001"])
  end
end

describe "filter combination" do
  before do
    create(:lawyer, oab_id: "PR_78001", state: "PR", instagram: "@a",
           crm_data: { "scraper" => { "scraped" => "true" }, "outreach" => { "stage" => "contacted" } })
    create(:lawyer, oab_id: "PR_78002", state: "PR", instagram: "@b",
           crm_data: { "scraper" => { "scraped" => "true" }, "outreach" => { "stage" => "new" } })
  end

  it "ANDs filters together" do
    get "/api/v1/lawyers/crm",
      params: { scraped: "true", stage: "contacted", has_instagram: "true" },
      headers: headers
    oab_ids = JSON.parse(response.body)["lawyers"].map { |l| l["oab_id"] }
    expect(oab_ids).to eq(["PR_78001"])
  end
end
```

- [ ] **Step 2: Run to confirm failures**

Run: `bundle exec rspec spec/requests/api/v1/lawyers_crm_index_spec.rb`
Expected: new specs fail — filters not yet implemented.

- [ ] **Step 3: Add filter chains to `crm_index`**

In `app/controllers/api/v1/lawyers_controller.rb`, modify `crm_index`. Insert these lines **after** the `lawyers = lawyers.where(state: state) if state.present?` line and **before** the `lawyers = lawyers.order(...)` line:

```ruby
if params[:scraped] == "true"
  lawyers = lawyers.where("crm_data->'scraper'->>'scraped' = 'true'")
end

if params[:stage].present?
  lawyers = lawyers.where("crm_data->'outreach'->>'stage' = ?", params[:stage])
end

if params[:has_instagram] == "true"
  lawyers = lawyers.where("instagram IS NOT NULL AND instagram != ''")
end

if params[:has_website] == "true"
  lawyers = lawyers.where("website IS NOT NULL AND website != ''")
end
```

- [ ] **Step 4: Run all crm_index specs**

Run: `bundle exec rspec spec/requests/api/v1/lawyers_crm_index_spec.rb`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/lawyers_controller.rb spec/requests/api/v1/lawyers_crm_index_spec.rb
git commit -m "feat: crm_index filters — scraped, stage, has_instagram, has_website"
```

---

## Task 11: `crm_index` — `min_lead_score` with regex pre-filter

**Files:**
- Modify: `app/controllers/api/v1/lawyers_controller.rb`
- Modify: `spec/requests/api/v1/lawyers_crm_index_spec.rb`

- [ ] **Step 1: Write failing min_lead_score specs**

Append to `spec/requests/api/v1/lawyers_crm_index_spec.rb`:

```ruby
describe "min_lead_score filter" do
  before do
    create(:lawyer, oab_id: "PR_79001", state: "PR", crm_data: { "scraper" => { "lead_score" => 90 } })
    create(:lawyer, oab_id: "PR_79002", state: "PR", crm_data: { "scraper" => { "lead_score" => 50 } })
    create(:lawyer, oab_id: "PR_79003", state: "PR", crm_data: { "scraper" => { "lead_score" => "not-a-number" } })
    create(:lawyer, oab_id: "PR_79004", state: "PR", crm_data: {})
  end

  it "returns rows with numeric lead_score >= threshold" do
    get "/api/v1/lawyers/crm", params: { min_lead_score: "70" }, headers: headers
    oab_ids = JSON.parse(response.body)["lawyers"].map { |l| l["oab_id"] }
    expect(oab_ids).to eq(["PR_79001"])
  end

  it "does not raise when a row has a non-numeric lead_score" do
    expect {
      get "/api/v1/lawyers/crm", params: { min_lead_score: "10" }, headers: headers
    }.not_to raise_error
    expect(response).to have_http_status(:ok)
    oab_ids = JSON.parse(response.body)["lawyers"].map { |l| l["oab_id"] }
    expect(oab_ids).to match_array(["PR_79001", "PR_79002"])  # PR_79003 excluded by regex
  end

  it "returns 400 when min_lead_score is non-numeric" do
    get "/api/v1/lawyers/crm", params: { min_lead_score: "abc" }, headers: headers
    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)["error"]).to include("min_lead_score")
  end
end
```

- [ ] **Step 2: Run to confirm failures**

Run: `bundle exec rspec spec/requests/api/v1/lawyers_crm_index_spec.rb`
Expected: 3 new examples fail.

- [ ] **Step 3: Add min_lead_score with regex pre-filter**

In `crm_index`, just below the `state` validation block (after the `if state.present? && !VALID_STATES.include?(state)` guard, before the `limit = ...` line), add:

```ruby
min_lead_score = params[:min_lead_score]
if min_lead_score.present?
  unless min_lead_score.to_s.match?(/\A\d+\z/)
    render json: { error: "min_lead_score deve ser numérico" }, status: :bad_request
    return
  end
end
```

Then in the filter chain (added in Task 10), add:

```ruby
if min_lead_score.present?
  lawyers = lawyers.where(
    "crm_data->'scraper'->>'lead_score' ~ '^\\d+$' AND (crm_data->'scraper'->>'lead_score')::int >= ?",
    min_lead_score.to_i
  )
end
```

> Place this filter alongside the others in the chain (after `has_website`, before `lawyers.order(...)`).

- [ ] **Step 4: Run min_lead_score specs**

Run: `bundle exec rspec spec/requests/api/v1/lawyers_crm_index_spec.rb`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/lawyers_controller.rb spec/requests/api/v1/lawyers_crm_index_spec.rb
git commit -m "feat: crm_index min_lead_score with regex pre-filter and 400 validation"
```

---

## Task 12: `crm_index` — cursor pagination + limit clamp

**Files:**
- Modify: `app/controllers/api/v1/lawyers_controller.rb`
- Modify: `spec/requests/api/v1/lawyers_crm_index_spec.rb`

- [ ] **Step 1: Write failing pagination + limit-clamp specs**

Append to `spec/requests/api/v1/lawyers_crm_index_spec.rb`:

```ruby
describe "cursor pagination" do
  before do
    create(:lawyer, oab_id: "PR_80004", state: "PR")
    create(:lawyer, oab_id: "PR_80003", state: "PR")
    create(:lawyer, oab_id: "PR_80002", state: "PR")
    create(:lawyer, oab_id: "PR_80001", state: "PR")
  end

  it "paginates with from_oab" do
    get "/api/v1/lawyers/crm", params: { state: "PR", limit: 2 }, headers: headers
    json = JSON.parse(response.body)
    expect(json["lawyers"].map { |l| l["oab_id"] }).to eq(["PR_80004", "PR_80003"])
    expect(json["meta"]["next_from_oab"]).to eq("PR_80003")

    get "/api/v1/lawyers/crm",
      params: { state: "PR", limit: 2, from_oab: json["meta"]["next_from_oab"] },
      headers: headers
    json2 = JSON.parse(response.body)
    expect(json2["lawyers"].map { |l| l["oab_id"] }).to eq(["PR_80002", "PR_80001"])
    expect(json2["meta"]["next_from_oab"]).to be_nil
  end

  it "clamps limit to 100" do
    get "/api/v1/lawyers/crm", params: { state: "PR", limit: 999 }, headers: headers
    json = JSON.parse(response.body)
    expect(json["lawyers"].length).to be <= 100
  end

  it "clamps limit to 1 minimum" do
    get "/api/v1/lawyers/crm", params: { state: "PR", limit: 0 }, headers: headers
    json = JSON.parse(response.body)
    expect(json["lawyers"].length).to eq(1)
  end
end
```

- [ ] **Step 2: Run to confirm failures**

Run: `bundle exec rspec spec/requests/api/v1/lawyers_crm_index_spec.rb`
Expected: pagination test fails — `from_oab` is not honored yet.

- [ ] **Step 3: Add `from_oab` cursor**

In `crm_index`, just before `lawyers = lawyers.order(oab_id: :desc).limit(limit + 1)`, add:

```ruby
from_oab = params[:from_oab]
lawyers = lawyers.where("oab_id < ?", from_oab) if from_oab.present?
```

The limit clamp formula in the existing implementation already handles 0→1 and 999→100 — verify by re-reading `limit = [[params.fetch(:limit, 50).to_i, 1].max, 100].min`.

- [ ] **Step 4: Run pagination specs**

Run: `bundle exec rspec spec/requests/api/v1/lawyers_crm_index_spec.rb`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/lawyers_controller.rb spec/requests/api/v1/lawyers_crm_index_spec.rb
git commit -m "feat: crm_index cursor pagination via from_oab"
```

---

## Task 13: Final cross-check — full test suite + N+1 audit + manual smoke

**Files:** none modified — verification only.

- [ ] **Step 1: Run the full RSpec suite**

Run: `bundle exec rspec`
Expected: zero failures across the full suite (including pre-existing specs).

> If any pre-existing spec breaks (e.g., a spec for the old `update_crm` that asserts `params.empty?` returns 400 in the absence of nested keys), inspect and update only that spec — do not change `update_crm` behavior unless the spec was correct and the implementation drifted.

- [ ] **Step 2: Manual smoke test — `show_crm` happy path**

Boot the server (`bin/rails s` in another terminal), then:

```bash
# Substitute a real API key for the X-API-KEY header
curl -s http://localhost:3000/api/v1/lawyer/PR_54159/crm \
  -H "X-API-KEY: <key>" | jq .
```

Expected: `{ "principal": { ... } }` with the lean shape from the spec. Verify a society with multiple partners renders `partners[]` and `truncated_partners`.

- [ ] **Step 3: Manual smoke test — `update_crm` deep nesting**

```bash
curl -s -X POST http://localhost:3000/api/v1/lawyer/PR_54159/crm \
  -H "X-API-KEY: <key>" -H "Content-Type: application/json" \
  -d '{"scraper":{"scraped":true,"social":{"instagram":"@bruno"}}}' | jq .
```

Expected: response includes `crm_data.scraper.social.instagram = "@bruno"`. Verify by re-fetching with `GET /lawyer/:oab/crm` — `crm_data` reflects the deep merge.

- [ ] **Step 4: Manual smoke test — `crm_index` with combined filters**

```bash
curl -s "http://localhost:3000/api/v1/lawyers/crm?scraped=true&min_lead_score=50&has_instagram=true&limit=5" \
  -H "X-API-KEY: <key>" | jq '.meta'
```

Expected: `meta.filters_applied` reflects the inputs; `meta.next_from_oab` is set if more rows exist.

- [ ] **Step 5: Final commit (only if any cleanup happened)**

```bash
git status   # should show no changes if all is well
# If anything was tweaked during the smoke pass:
git add -p
git commit -m "chore: post-implementation cleanup for lawyer CRM endpoints"
```

- [ ] **Step 6: Update backlog task with implementation notes**

If a `backlog` task tracks this work, append PR-style notes summarizing what shipped:

```bash
backlog task edit <id> --append-notes "Shipped: GET /lawyer/:oab/crm (lean read), extended POST /lawyer/:oab/crm (nested scraper/outreach/signals), GET /lawyers/crm (filtered listing with cursor pagination)"
backlog task edit <id> -s Done
```

---

## Self-Review Checklist (post-plan)

- ✅ Spec coverage: every section in `2026-04-25-lawyer-crm-endpoint-design.md` maps to at least one task. `show_crm` (Tasks 1, 2, 3, 4, 5, 6); `update_crm` extension (Task 7); `crm_index` (Tasks 8–12); auth + routing (Task 1); testing strategy (every task is TDD).
- ✅ No placeholders: every code block is concrete; no "TODO", "TBD", or hand-waving.
- ✅ Type consistency: `LawyerCrmSerializer::CONDITIONAL_FIELDS` is referenced from `LawyerCrmPartnerSerializer` and matches; `PARTNER_LIMIT = 6` is used consistently in the truncation logic and tests.
- ✅ Bite-sized steps: each task has 4–6 steps in the 2–5 minute range.
- ✅ Frequent commits: one commit per task at minimum.
