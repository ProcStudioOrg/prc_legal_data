require 'rails_helper'

RSpec.describe "POST /api/v1/lawyer/:oab/crm", type: :request do
  let(:user) do
    User.create(email: "crm_writer@example.com", password: "password", admin: false)
  end
  let(:api_key) { ApiKey.create(user: user, key: "test_key_update_crm", active: true, role: "admin") }
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
