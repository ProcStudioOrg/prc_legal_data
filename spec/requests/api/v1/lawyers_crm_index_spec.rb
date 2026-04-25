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
end
