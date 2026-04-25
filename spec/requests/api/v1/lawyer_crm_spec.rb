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
