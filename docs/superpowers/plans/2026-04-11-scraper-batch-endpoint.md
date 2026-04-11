# Scraper Batch Lawyers Endpoint — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `GET /api/v1/lawyers` batch endpoint with cursor pagination, dedicated serializer (compact societies + supplementary OABs), Bruno collection request, and rake task to flag enterprise societies.

**Architecture:** New `index` action in existing `LawyersController` + new `ScraperLawyerSerializer` that handles society member threshold (≤6 list members, >6 flag enterprise). Rake task to pre-compute enterprise_society in crm_data.

**Tech Stack:** Rails 8.1, PostgreSQL, RSpec, FactoryBot, Bruno API collections

**Spec:** `docs/superpowers/specs/2026-04-11-scraper-api-batch-endpoint-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `app/serializers/scraper_lawyer_serializer.rb` | Compact serialization with societies/supplementaries |
| Modify | `app/controllers/api/v1/lawyers_controller.rb` | Add `index` action |
| Modify | `config/routes.rb` | Add `GET /api/v1/lawyers` route |
| Create | `spec/requests/api/v1/lawyers_index_spec.rb` | Request specs for index endpoint |
| Create | `spec/serializers/scraper_lawyer_serializer_spec.rb` | Unit specs for serializer |
| Create | `lib/tasks/flag_enterprise_societies.rake` | Rake task to flag enterprise societies |
| Create | `spec/tasks/flag_enterprise_societies_spec.rake` | Rake task spec |
| Create | `collection/LegalDataAPI/Lawyers/Listar Advogados (Scraper).bru` | Bruno collection request |

---

## Task 1: ScraperLawyerSerializer — base fields + supplementary_oabs

**Files:**
- Create: `spec/serializers/scraper_lawyer_serializer_spec.rb`
- Create: `app/serializers/scraper_lawyer_serializer.rb`

- [ ] **Step 1: Write failing test for base fields**

```ruby
# spec/serializers/scraper_lawyer_serializer_spec.rb
require 'rails_helper'

RSpec.describe ScraperLawyerSerializer do
  let(:lawyer) do
    create(:lawyer,
      full_name: "MARIA SILVA",
      oab_number: "50000",
      oab_id: "PR_50000",
      state: "PR",
      city: "CURITIBA",
      situation: "situação regular",
      address: "Rua Teste, 123",
      phone_number_1: "(41) 99999-9999",
      phone_number_2: nil,
      email: "maria@test.com",
      instagram: "@maria",
      website: "https://maria.com",
      is_procstudio: false,
      has_society: false,
      crm_data: { "researched" => true }
    )
  end

  describe '#as_json' do
    it 'returns base fields' do
      result = described_class.new(lawyer).as_json

      expect(result[:id]).to eq(lawyer.id)
      expect(result[:full_name]).to eq("MARIA SILVA")
      expect(result[:oab_number]).to eq("50000")
      expect(result[:oab_id]).to eq("PR_50000")
      expect(result[:state]).to eq("PR")
      expect(result[:city]).to eq("CURITIBA")
      expect(result[:situation]).to eq("situação regular")
      expect(result[:address]).to eq("Rua Teste, 123")
      expect(result[:phone_number_1]).to eq("(41) 99999-9999")
      expect(result[:phone_number_2]).to be_nil
      expect(result[:email]).to eq("maria@test.com")
      expect(result[:instagram]).to eq("@maria")
      expect(result[:website]).to eq("https://maria.com")
      expect(result[:has_society]).to eq(false)
      expect(result[:crm_data]).to eq({ "researched" => true })
    end

    it 'returns empty supplementary_oabs when no supplementaries' do
      result = described_class.new(lawyer).as_json
      expect(result[:supplementary_oabs]).to eq([])
    end
  end

  describe '#as_json supplementary_oabs' do
    it 'returns supplementary oab_ids when lawyer is principal' do
      supp1 = create(:lawyer, oab_id: "SP_12345", principal_lawyer: lawyer)
      supp2 = create(:lawyer, oab_id: "RJ_67890", principal_lawyer: lawyer)

      result = described_class.new(lawyer.reload).as_json

      expect(result[:supplementary_oabs]).to match_array(["SP_12345", "RJ_67890"])
    end

    it 'returns principal + sibling oab_ids when lawyer is supplementary' do
      principal = create(:lawyer, oab_id: "MT_11111")
      supp_self = create(:lawyer, oab_id: "PR_22222", principal_lawyer: principal)
      supp_sibling = create(:lawyer, oab_id: "SP_33333", principal_lawyer: principal)

      result = described_class.new(supp_self).as_json

      expect(result[:supplementary_oabs]).to match_array(["MT_11111", "SP_33333"])
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/serializers/scraper_lawyer_serializer_spec.rb`
Expected: FAIL — `uninitialized constant ScraperLawyerSerializer`

- [ ] **Step 3: Implement ScraperLawyerSerializer with base fields + supplementary_oabs**

```ruby
# app/serializers/scraper_lawyer_serializer.rb
class ScraperLawyerSerializer
  ENTERPRISE_THRESHOLD = 6

  def initialize(lawyer)
    @lawyer = lawyer
  end

  def as_json
    {
      id: @lawyer.id,
      full_name: @lawyer.full_name,
      oab_number: @lawyer.oab_number,
      oab_id: @lawyer.oab_id,
      situation: @lawyer.situation,
      city: @lawyer.city,
      state: @lawyer.state,
      address: @lawyer.address,
      phone_number_1: @lawyer.phone_number_1,
      phone_number_2: @lawyer.phone_number_2,
      email: @lawyer.email,
      instagram: @lawyer.instagram,
      website: @lawyer.website,
      has_society: @lawyer.has_society,
      supplementary_oabs: supplementary_oabs,
      societies: [],
      crm_data: @lawyer.crm_data || {}
    }
  end

  private

  def supplementary_oabs
    if @lawyer.principal_lawyer_id.present?
      # Lawyer is supplementary — return principal + siblings
      principal = @lawyer.principal_lawyer
      siblings = principal.supplementary_lawyers.where.not(id: @lawyer.id)
      [principal.oab_id] + siblings.pluck(:oab_id)
    else
      # Lawyer is principal — return all supplementaries
      @lawyer.supplementary_lawyers.pluck(:oab_id)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/serializers/scraper_lawyer_serializer_spec.rb`
Expected: All 4 examples PASS

- [ ] **Step 5: Commit**

```bash
git add app/serializers/scraper_lawyer_serializer.rb spec/serializers/scraper_lawyer_serializer_spec.rb
git commit -m "feat: add ScraperLawyerSerializer with base fields and supplementary_oabs"
```

---

## Task 2: ScraperLawyerSerializer — society serialization with member threshold

**Files:**
- Modify: `spec/serializers/scraper_lawyer_serializer_spec.rb`
- Modify: `app/serializers/scraper_lawyer_serializer.rb`

- [ ] **Step 1: Write failing tests for society serialization**

Add to `spec/serializers/scraper_lawyer_serializer_spec.rb`:

```ruby
describe '#as_json societies' do
  it 'lists members for small society (<=6 members)' do
    society = create(:society, name: "SMALL ADVOCACIA")
    member1 = create(:lawyer, full_name: "JOAO SILVA", oab_id: "PR_11111")
    member2 = create(:lawyer, full_name: "MARIA SOUZA", oab_id: "PR_22222")
    create(:lawyer_society, lawyer: lawyer, society: society)
    create(:lawyer_society, lawyer: member1, society: society)
    create(:lawyer_society, lawyer: member2, society: society)

    result = described_class.new(lawyer.reload).as_json

    expect(result[:societies].length).to eq(1)
    soc = result[:societies].first
    expect(soc[:name]).to eq("SMALL ADVOCACIA")
    expect(soc[:enterprise]).to be_nil
    expect(soc[:members]).to match_array([
      { name: "JOAO SILVA", oab_id: "PR_11111" },
      { name: "MARIA SOUZA", oab_id: "PR_22222" },
      { name: "MARIA SILVA", oab_id: "PR_50000" }
    ])
  end

  it 'returns enterprise flag for large society (>6 members)' do
    society = create(:society, name: "MEGA ADVOCACIA", :with_lawyers, lawyers_count: 8)
    create(:lawyer_society, lawyer: lawyer, society: society)

    result = described_class.new(lawyer.reload).as_json

    soc = result[:societies].first
    expect(soc[:name]).to eq("MEGA ADVOCACIA")
    expect(soc[:enterprise]).to eq(true)
    expect(soc[:member_count]).to eq(9) # 8 from trait + the lawyer itself
    expect(soc[:members]).to be_nil
  end

  it 'handles lawyer with no societies' do
    result = described_class.new(lawyer).as_json
    expect(result[:societies]).to eq([])
  end

  it 'handles lawyer with multiple societies of different sizes' do
    small_soc = create(:society, name: "SMALL SOC")
    create(:lawyer_society, lawyer: lawyer, society: small_soc)
    create(:lawyer_society, lawyer: create(:lawyer), society: small_soc)

    big_soc = create(:society, name: "BIG SOC", :with_lawyers, lawyers_count: 7)
    create(:lawyer_society, lawyer: lawyer, society: big_soc)

    result = described_class.new(lawyer.reload).as_json

    names = result[:societies].map { |s| s[:name] }
    expect(names).to match_array(["SMALL SOC", "BIG SOC"])

    small = result[:societies].find { |s| s[:name] == "SMALL SOC" }
    expect(small[:members]).to be_an(Array)
    expect(small[:enterprise]).to be_nil

    big = result[:societies].find { |s| s[:name] == "BIG SOC" }
    expect(big[:enterprise]).to eq(true)
    expect(big[:member_count]).to eq(8) # 7 + lawyer
    expect(big[:members]).to be_nil
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/serializers/scraper_lawyer_serializer_spec.rb`
Expected: New society tests FAIL (societies always returns `[]`)

- [ ] **Step 3: Implement society serialization**

In `app/serializers/scraper_lawyer_serializer.rb`, replace `societies: []` with `societies: serialize_societies` and add the private method:

```ruby
def serialize_societies
  @lawyer.lawyer_societies.includes(society: { lawyer_societies: :lawyer }).map do |ls|
    society = ls.society
    member_count = society.lawyer_societies.size

    if member_count > ENTERPRISE_THRESHOLD
      { name: society.name, enterprise: true, member_count: member_count }
    else
      members = society.lawyer_societies.map do |member_ls|
        { name: member_ls.lawyer.full_name, oab_id: member_ls.lawyer.oab_id }
      end
      { name: society.name, members: members }
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/serializers/scraper_lawyer_serializer_spec.rb`
Expected: All examples PASS

- [ ] **Step 5: Commit**

```bash
git add app/serializers/scraper_lawyer_serializer.rb spec/serializers/scraper_lawyer_serializer_spec.rb
git commit -m "feat: add society serialization with enterprise threshold to ScraperLawyerSerializer"
```

---

## Task 3: Route + Controller index action

**Files:**
- Create: `spec/requests/api/v1/lawyers_index_spec.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/api/v1/lawyers_controller.rb`

- [ ] **Step 1: Write failing request specs**

```ruby
# spec/requests/api/v1/lawyers_index_spec.rb
require 'rails_helper'

RSpec.describe "GET /api/v1/lawyers", type: :request do
  let(:user) { User.create(email: "test@example.com", password: "password", admin: false) }
  let(:api_key) { ApiKey.create(user: user, key: "test_key_index", active: true) }
  let(:headers) { { "X-API-KEY" => api_key.key } }

  describe "parameter validation" do
    it "returns 400 when state is missing" do
      get "/api/v1/lawyers", headers: headers
      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json["error"]).to include("Estado")
    end

    it "returns 400 when state is invalid" do
      get "/api/v1/lawyers", params: { state: "XX" }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 401 without valid API key" do
      get "/api/v1/lawyers", params: { state: "PR" }, headers: { "X-API-KEY" => "invalid" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "basic query" do
    before do
      # Regular lawyers in PR — use explicit oab_numbers for ordering
      create(:lawyer, oab_id: "PR_300", oab_number: "300", state: "PR", situation: "situação regular")
      create(:lawyer, oab_id: "PR_200", oab_number: "200", state: "PR", situation: "situação regular")
      create(:lawyer, oab_id: "PR_100", oab_number: "100", state: "PR", situation: "situação regular")

      # Should be excluded:
      create(:lawyer, oab_id: "SP_400", oab_number: "400", state: "SP", situation: "situação regular") # wrong state
      create(:lawyer, oab_id: "PR_500", oab_number: "500", state: "PR", situation: "cancelado")         # wrong situation
      create(:lawyer, oab_id: "PR_600", oab_number: "600", state: "PR", situation: "situação regular", is_procstudio: true) # procstudio
    end

    it "returns lawyers ordered by oab_number DESC, filtered by state and situation" do
      get "/api/v1/lawyers", params: { state: "PR" }, headers: headers
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      oab_ids = json["lawyers"].map { |l| l["oab_id"] }
      expect(oab_ids).to eq(["PR_300", "PR_200", "PR_100"])
    end

    it "excludes procstudio, non-regular, and other states" do
      get "/api/v1/lawyers", params: { state: "PR" }, headers: headers
      json = JSON.parse(response.body)
      oab_ids = json["lawyers"].map { |l| l["oab_id"] }

      expect(oab_ids).not_to include("SP_400", "PR_500", "PR_600")
    end
  end

  describe "cursor pagination" do
    before do
      create(:lawyer, oab_id: "PR_50", oab_number: "50", state: "PR", situation: "situação regular")
      create(:lawyer, oab_id: "PR_40", oab_number: "40", state: "PR", situation: "situação regular")
      create(:lawyer, oab_id: "PR_30", oab_number: "30", state: "PR", situation: "situação regular")
      create(:lawyer, oab_id: "PR_20", oab_number: "20", state: "PR", situation: "situação regular")
    end

    it "paginates with from_oab" do
      get "/api/v1/lawyers", params: { state: "PR", limit: 2 }, headers: headers
      json = JSON.parse(response.body)

      expect(json["lawyers"].length).to eq(2)
      expect(json["lawyers"].map { |l| l["oab_id"] }).to eq(["PR_50", "PR_40"])
      expect(json["meta"]["next_from_oab"]).to eq("40")

      # Second page
      get "/api/v1/lawyers", params: { state: "PR", limit: 2, from_oab: json["meta"]["next_from_oab"] }, headers: headers
      json2 = JSON.parse(response.body)

      expect(json2["lawyers"].map { |l| l["oab_id"] }).to eq(["PR_30", "PR_20"])
      expect(json2["meta"]["next_from_oab"]).to be_nil # last page
    end

    it "caps limit at 100" do
      get "/api/v1/lawyers", params: { state: "PR", limit: 999 }, headers: headers
      json = JSON.parse(response.body)
      # Should not crash — just returns what's available (4 lawyers, capped query at 100)
      expect(json["lawyers"].length).to eq(4)
    end
  end

  describe "scraped filter" do
    before do
      create(:lawyer, oab_id: "PR_10", oab_number: "10", state: "PR", situation: "situação regular", crm_data: { "scraped" => "true" })
      create(:lawyer, oab_id: "PR_20", oab_number: "20", state: "PR", situation: "situação regular", crm_data: {})
      create(:lawyer, oab_id: "PR_30", oab_number: "30", state: "PR", situation: "situação regular", crm_data: nil)
    end

    it "returns only unscraped when scraped=false" do
      get "/api/v1/lawyers", params: { state: "PR", scraped: "false" }, headers: headers
      json = JSON.parse(response.body)
      oab_ids = json["lawyers"].map { |l| l["oab_id"] }

      expect(oab_ids).to match_array(["PR_20", "PR_30"])
      expect(oab_ids).not_to include("PR_10")
    end
  end

  describe "meta" do
    before do
      create(:lawyer, oab_id: "PR_100", oab_number: "100", state: "PR", situation: "situação regular")
      create(:lawyer, oab_id: "PR_200", oab_number: "200", state: "PR", situation: "situação regular")
    end

    it "returns correct meta fields" do
      get "/api/v1/lawyers", params: { state: "PR", limit: 1 }, headers: headers
      json = JSON.parse(response.body)

      expect(json["meta"]["returned"]).to eq(1)
      expect(json["meta"]["state"]).to eq("PR")
      expect(json["meta"]["next_from_oab"]).to eq("200")
    end

    it "returns null next_from_oab on last page" do
      get "/api/v1/lawyers", params: { state: "PR", limit: 10 }, headers: headers
      json = JSON.parse(response.body)

      expect(json["meta"]["returned"]).to eq(2)
      expect(json["meta"]["next_from_oab"]).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/requests/api/v1/lawyers_index_spec.rb`
Expected: FAIL — routing error, no route matches

- [ ] **Step 3: Add route**

In `config/routes.rb`, add the new route inside the `namespace :api do / namespace :v1 do` block, before the existing lawyer routes:

```ruby
# Rota batch para scraper
get 'lawyers', to: 'lawyers#index'
```

The full block becomes:

```ruby
namespace :api do
  namespace :v1 do
    # Rota batch para scraper
    get 'lawyers', to: 'lawyers#index'

    # Rotas de advogados
    get 'lawyer/:oab', to: 'lawyers#show_by_oab'
    # ... rest unchanged
```

- [ ] **Step 4: Implement the index action**

Add to `app/controllers/api/v1/lawyers_controller.rb`, as the first public method (before `create_lawyer`):

```ruby
# --- Batch fetch for scraper ---
def index
  state = params[:state]&.upcase

  unless state.present?
    render json: { error: "Estado obrigatório" }, status: :bad_request
    return
  end

  unless VALID_STATES.include?(state)
    render json: { error: "Estado inválido. Estados válidos: #{VALID_STATES.join(', ')}" }, status: :bad_request
    return
  end

  limit = [[params.fetch(:limit, 50).to_i, 1].max, 100].min
  from_oab = params[:from_oab]

  lawyers = Lawyer
    .where(state: state)
    .where("situation ILIKE ?", "%regular%")
    .where("is_procstudio IS NULL OR is_procstudio = false")

  if from_oab.present?
    lawyers = lawyers.where("CAST(oab_number AS INTEGER) < ?", from_oab.to_i)
  end

  if params[:scraped] == "false"
    lawyers = lawyers.where("crm_data->>'scraped' IS NULL OR crm_data->>'scraped' != 'true'")
  end

  lawyers = lawyers
    .order(Arel.sql("CAST(oab_number AS INTEGER) DESC"))
    .limit(limit)
    .includes(:supplementary_lawyers, :principal_lawyer, lawyer_societies: { society: { lawyer_societies: :lawyer } })

  serialized = lawyers.map { |l| ScraperLawyerSerializer.new(l).as_json }

  last_oab = serialized.any? ? serialized.last[:oab_number] : nil
  next_from_oab = (serialized.length == limit) ? last_oab : nil

  render json: {
    lawyers: serialized,
    meta: {
      returned: serialized.length,
      state: state,
      from_oab: from_oab,
      next_from_oab: next_from_oab
    }
  }, status: :ok
rescue => e
  Rails.logger.error("Error in lawyers#index: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
  render json: {
    error: "Erro interno ao listar advogados",
    error_type: e.class.name,
    request_id: request.request_id
  }, status: :internal_server_error
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/requests/api/v1/lawyers_index_spec.rb`
Expected: All examples PASS

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/lawyers_controller.rb spec/requests/api/v1/lawyers_index_spec.rb
git commit -m "feat: add GET /api/v1/lawyers batch endpoint with cursor pagination"
```

---

## Task 4: Rake task — flag_enterprise_societies

**Files:**
- Create: `lib/tasks/flag_enterprise_societies.rake`

- [ ] **Step 1: Write the rake task**

```ruby
# lib/tasks/flag_enterprise_societies.rake
namespace :data do
  desc "Flag lawyers in societies with >6 members as enterprise_society in crm_data"
  task flag_enterprise_societies: :environment do
    threshold = ScraperLawyerSerializer::ENTERPRISE_THRESHOLD

    puts "Finding societies with more than #{threshold} members..."

    large_societies = Society
      .joins(:lawyer_societies)
      .group("societies.id")
      .having("COUNT(lawyer_societies.id) > ?", threshold)

    total_societies = large_societies.count.length
    puts "Found #{total_societies} large societies"

    flagged_count = 0

    large_societies.find_each do |society|
      lawyer_ids = society.lawyer_societies.pluck(:lawyer_id)

      Lawyer.where(id: lawyer_ids).find_each do |lawyer|
        crm = lawyer.crm_data || {}
        next if crm["enterprise_society"] == true

        crm["enterprise_society"] = true
        lawyer.update_column(:crm_data, crm)
        flagged_count += 1
      end

      print "."
    end

    puts "\nDone! Flagged #{flagged_count} lawyers across #{total_societies} societies"
  end
end
```

- [ ] **Step 2: Verify the task loads correctly**

Run: `bundle exec rake -T data:flag_enterprise_societies`
Expected: Shows `rake data:flag_enterprise_societies  # Flag lawyers in societies with >6 members...`

- [ ] **Step 3: Commit**

```bash
git add lib/tasks/flag_enterprise_societies.rake
git commit -m "feat: add rake task to flag enterprise society members in crm_data"
```

---

## Task 5: Bruno collection request

**Files:**
- Create: `collection/LegalDataAPI/Lawyers/Listar Advogados (Scraper).bru`

- [ ] **Step 1: Create the Bruno request file**

```bru
meta {
  name: Listar Advogados (Scraper)
  type: http
  seq: 7
}

get {
  url: {{base_url}}/lawyers?state={{state}}&limit={{limit}}
  body: none
  auth: none
}

headers {
  X-API-KEY: {{api_key}}
  Content-Type: application/json
}

vars:pre-request {
  state: PR
  limit: 20
}

settings {
  encodeUrl: true
  timeout: 0
}

docs {
  ### Listar Advogados para Scraper (Batch)

  Retorna advogados em lote, ordenados por número OAB decrescente (mais novos primeiro).
  Utilizado pelo scraper AI para processar advogados em batch.

  **Query Parameters:**
  - `state` (obrigatório): Sigla do estado (ex: PR, SP, MG)
  - `from_oab` (opcional): Cursor — retorna advogados com OAB < este número
  - `limit` (opcional, default 50, max 100): Quantidade de advogados por página
  - `scraped` (opcional): Filtrar por status de scraping. `false` = apenas não-scraped

  **Headers obrigatórios:**
  - `X-API-KEY`: Chave de API válida

  **Resposta de sucesso (200):**

  ``` json
  {
    "lawyers": [
      {
        "id": 1,
        "full_name": "BRUNO PELLIZZETTI",
        "oab_id": "PR_30145",
        "situation": "REGULAR",
        "supplementary_oabs": ["AC_3901"],
        "societies": [
          {
            "name": "PELLIZZETTI E WALBER",
            "members": [
              {"name": "JOAO SILVA", "oab_id": "PR_59010"}
            ]
          }
        ],
        "crm_data": {}
      }
    ],
    "meta": {
      "returned": 20,
      "state": "PR",
      "from_oab": null,
      "next_from_oab": "130960"
    }
  }
  ```

  **Paginação por cursor:**
  Use `next_from_oab` do response como `from_oab` do próximo request.
  Quando `next_from_oab` é null, é a última página.

  **Erros possíveis:**
  - 400: Estado ausente ou inválido
  - 401: API key inválida ou ausente
}
```

- [ ] **Step 2: Commit**

```bash
git add "collection/LegalDataAPI/Lawyers/Listar Advogados (Scraper).bru"
git commit -m "docs: add Bruno collection request for scraper batch endpoint"
```

---

## Task 6: Verification against real data

Run the 6 test cases from the spec against the running server.

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All tests pass, no regressions

- [ ] **Step 2: Start rails console and verify Test Case 1 — small society**

```bash
bin/rails runner "
lawyer = Lawyer.find_by(oab_id: 'MG_183893')
puts ScraperLawyerSerializer.new(lawyer).as_json.to_json
"
```

Expected: Society `SOARES DONATO ADVOGADOS ASSOCIADOS` with individual members listed, no `enterprise` flag.

- [ ] **Step 3: Verify Test Case 2 — large society**

```bash
bin/rails runner "
lawyer = Lawyer.find_by(oab_id: 'MG_198236')
puts ScraperLawyerSerializer.new(lawyer).as_json.to_json
"
```

Expected: Society `ANANIAS JUNQUEIRA FERRAZ E ADVOGADOS ASSOCIADOS` with `enterprise: true`, `member_count: 136`.

- [ ] **Step 4: Verify Test Case 3 — supplementary OABs**

```bash
bin/rails runner "
lawyer = Lawyer.find_by(oab_id: 'PR_72713')
result = ScraperLawyerSerializer.new(lawyer).as_json
puts 'supplementary_oabs: ' + result[:supplementary_oabs].inspect
"
```

Expected: Includes `MT_29604` (principal).

- [ ] **Step 5: Verify Test Case 4 — massive society (URBANO VITALINO)**

```bash
bin/rails runner "
lawyer = Lawyer.joins(:lawyer_societies).where(lawyer_societies: { society_id: 350798 }).where('situation ILIKE ?', '%regular%').first
result = ScraperLawyerSerializer.new(lawyer).as_json
soc = result[:societies].find { |s| s[:name]&.include?('URBANO') }
puts soc.to_json
"
```

Expected: `enterprise: true`, `member_count: 466`, no `members` array.

- [ ] **Step 6: Verify Test Case 5 — cursor pagination (via rails runner simulating controller logic)**

```bash
bin/rails runner "
lawyers = Lawyer.where(state: 'PR').where('situation ILIKE ?', '%regular%').where('is_procstudio IS NULL OR is_procstudio = false').order(Arel.sql('CAST(oab_number AS INTEGER) DESC')).limit(3)
page1 = lawyers.pluck(:oab_id, :oab_number)
puts 'Page 1: ' + page1.inspect

last_oab = page1.last[1]
lawyers2 = Lawyer.where(state: 'PR').where('situation ILIKE ?', '%regular%').where('is_procstudio IS NULL OR is_procstudio = false').where('CAST(oab_number AS INTEGER) < ?', last_oab.to_i).order(Arel.sql('CAST(oab_number AS INTEGER) DESC')).limit(3)
page2 = lawyers2.pluck(:oab_id, :oab_number)
puts 'Page 2: ' + page2.inspect

overlap = page1.map(&:first) & page2.map(&:first)
puts 'Overlap: ' + overlap.inspect
puts overlap.empty? ? 'PASS: no overlap' : 'FAIL: overlap detected'
"
```

Expected: Two distinct pages, no overlap.

- [ ] **Step 7: Commit final state if any fixes were needed**

```bash
git add -A
git commit -m "fix: adjustments from real data verification" # only if changes were made
```
