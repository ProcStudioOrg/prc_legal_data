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
      create(:lawyer, oab_id: "PR_300", oab_number: "300", state: "PR", situation: "situação regular")
      create(:lawyer, oab_id: "PR_200", oab_number: "200", state: "PR", situation: "situação regular")
      create(:lawyer, oab_id: "PR_100", oab_number: "100", state: "PR", situation: "situação regular")

      create(:lawyer, oab_id: "SP_400", oab_number: "400", state: "SP", situation: "situação regular")
      create(:lawyer, oab_id: "PR_500", oab_number: "500", state: "PR", situation: "cancelado")
      create(:lawyer, oab_id: "PR_600", oab_number: "600", state: "PR", situation: "situação regular", is_procstudio: true)
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

      get "/api/v1/lawyers", params: { state: "PR", limit: 2, from_oab: json["meta"]["next_from_oab"] }, headers: headers
      json2 = JSON.parse(response.body)

      expect(json2["lawyers"].map { |l| l["oab_id"] }).to eq(["PR_30", "PR_20"])
      expect(json2["meta"]["next_from_oab"]).to be_nil
    end

    it "caps limit at 100" do
      get "/api/v1/lawyers", params: { state: "PR", limit: 999 }, headers: headers
      json = JSON.parse(response.body)
      expect(json["lawyers"].length).to eq(4)
    end
  end

  describe "scraped filter" do
    before do
      create(:lawyer, oab_id: "PR_10", oab_number: "10", state: "PR", situation: "situação regular", crm_data: { "scraped" => "true" })
      create(:lawyer, oab_id: "PR_20", oab_number: "20", state: "PR", situation: "situação regular", crm_data: {})
      create(:lawyer, oab_id: "PR_30", oab_number: "30", state: "PR", situation: "situação regular", crm_data: {})
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
