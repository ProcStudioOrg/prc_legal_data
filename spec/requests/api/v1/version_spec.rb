require 'rails_helper'

RSpec.describe "Api::V1::Version", type: :request do
  describe "GET /api/v1/version" do
    it "responds without an API key" do
      get "/api/v1/version"

      expect(response).to have_http_status(:ok)
    end

    it "exposes the current version, the commit and the changelog" do
      get "/api/v1/version"
      body = JSON.parse(response.body)

      expect(body["version"]).to eq(AppVersion.current[:version])
      expect(body["commit"]).to be_present
      expect(body["environment"]).to eq("test")
      expect(body["changelog"]).to be_an(Array).and be_present
    end

    it "reports the newest changelog entry as the current version" do
      get "/api/v1/version"
      body = JSON.parse(response.body)

      newest = body["changelog"].first
      expect(body["version"]).to eq(newest["version"])
      expect(body["note"]).to eq(newest["note"])
    end
  end

  describe "GET /up" do
    it "responds without an API key" do
      get "/up"

      expect(response).to have_http_status(:ok)
    end
  end
end
