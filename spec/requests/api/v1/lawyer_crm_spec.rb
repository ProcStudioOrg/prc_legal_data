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

      # Eager loading caps query count regardless of society size or PARTNER_LIMIT.
      # Each partner's supplementary_lawyers are loaded in batch, not per-partner.
      # Baseline after fix: ~20 queries (api_key auth + set_lawyer + two eager base_relation
      # fetches covering supplementary_lawyers, principal_lawyer, lawyer_societies,
      # societies, nested lawyer_societies+lawyers, and partners' supplementary_lawyers).
      expect(query_count).to be < 23
      expect(response).to have_http_status(:ok)
    end
  end
end
