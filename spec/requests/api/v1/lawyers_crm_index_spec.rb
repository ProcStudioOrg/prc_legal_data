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
