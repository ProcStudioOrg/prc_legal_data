require 'rails_helper'

RSpec.describe "POST /api/v1/society/:inscricao/crm", type: :request do
  let(:user) do
    User.create(email: "society_crm_writer@example.com", password: "password", admin: false)
  end
  let(:api_key) { ApiKey.create(user: user, key: "test_key_society_crm", active: true, role: "admin") }
  let(:headers) { { "X-API-KEY" => api_key.key, "CONTENT_TYPE" => "application/json" } }
  let!(:society) { create(:society, inscricao: 990001, crm_data: {}) }
  let(:path) { "/api/v1/society/990001/crm" }

  describe "campos escalares" do
    it "persiste os campos de topo do store_accessor" do
      post path,
        params: { researched: true, contacted: true, contact_notes: "retornar em agosto" }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      society.reload
      expect(society.crm_data).to include(
        "researched" => true,
        "contacted" => true,
        "contact_notes" => "retornar em agosto"
      )
    end

    it "expõe os campos via store_accessor no model" do
      post path, params: { researched: true, contacted_by: "bruno" }.to_json, headers: headers

      society.reload
      expect(society.researched).to eq(true)
      expect(society.contacted_by).to eq("bruno")
    end

    it "persiste mail_marketing_origin como array" do
      post path, params: { mail_marketing_origin: ["oab", "site"] }.to_json, headers: headers

      society.reload
      expect(society.crm_data["mail_marketing_origin"]).to eq(["oab", "site"])
    end
  end

  describe "sub-hashes livres" do
    it "persiste um scraper plano" do
      post path, params: { scraper: { scraped: true, lead_score: 75 } }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      society.reload
      expect(society.crm_data["scraper"]).to eq({ "scraped" => true, "lead_score" => 75 })
    end

    it "faz deep-merge entre chamadas sequenciais" do
      post path, params: { scraper: { sources: ["site"] } }.to_json, headers: headers
      post path, params: { scraper: { lead_score: 80 } }.to_json, headers: headers

      society.reload
      expect(society.crm_data["scraper"]).to include("sources" => ["site"], "lead_score" => 80)
    end

    it "persiste aninhamento de 2 níveis" do
      post path,
        params: { scraper: { social: { instagram: "@banca", linkedin: "company/banca" } } }.to_json,
        headers: headers

      society.reload
      expect(society.crm_data["scraper"]["social"]).to eq(
        { "instagram" => "@banca", "linkedin" => "company/banca" }
      )
    end

    it "persiste outreach e signals" do
      post path,
        params: { outreach: { stage: "contacted" }, signals: { has_website: true } }.to_json,
        headers: headers

      society.reload
      expect(society.crm_data["outreach"]).to eq({ "stage" => "contacted" })
      expect(society.crm_data["signals"]).to eq({ "has_website" => true })
    end

    it "não apaga campos de topo ao gravar um sub-hash" do
      society.update!(crm_data: { "researched" => true })
      post path, params: { scraper: { scraped: true } }.to_json, headers: headers

      society.reload
      expect(society.crm_data["researched"]).to eq(true)
      expect(society.crm_data["scraper"]["scraped"]).to eq(true)
    end
  end

  describe "isolamento em relação ao cnpja_data" do
    it "não toca no payload da Receita" do
      society.update!(cnpja_data: { "company" => { "name" => "BANCA LTDA" } })
      post path, params: { scraper: { scraped: true } }.to_json, headers: headers

      society.reload
      expect(society.cnpja_data).to eq({ "company" => { "name" => "BANCA LTDA" } })
      expect(society.crm_data["scraper"]).to eq({ "scraped" => true })
    end
  end

  describe "sociedade do portal da OAB-MG (sem inscrição)" do
    let!(:portal_society) { create(:society, :from_portal, oab_id: "MG_206787_SOCIEDADE", crm_data: {}) }

    it "é encontrada pelo oab_id" do
      post "/api/v1/society/MG_206787_SOCIEDADE/crm",
        params: { scraper: { scraped: true } }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      portal_society.reload
      expect(portal_society.crm_data["scraper"]).to eq({ "scraped" => true })
    end

    it "devolve oab_id e inscricao nula na resposta" do
      post "/api/v1/society/MG_206787_SOCIEDADE/crm",
        params: { researched: true }.to_json,
        headers: headers

      json = JSON.parse(response.body)
      expect(json["oab_id"]).to eq("MG_206787_SOCIEDADE")
      expect(json["inscricao"]).to be_nil
    end
  end

  describe "erros" do
    it "404 para chave inexistente" do
      post "/api/v1/society/999999/crm", params: { researched: true }.to_json, headers: headers

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("Sociedade não encontrada")
    end

    it "400 quando nenhum parâmetro de CRM é enviado" do
      post path, params: { foo: "bar" }.to_json, headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("Nenhum parâmetro CRM fornecido")
    end
  end

  describe "autorização" do
    it "403 com key read" do
      read_key = ApiKey.create!(user: user, key: "test_key_society_crm_read", role: "read", active: true)

      post path,
        params: { researched: true }.to_json,
        headers: { "X-API-KEY" => read_key.key, "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:forbidden)
    end

    it "401 sem key" do
      post path, params: { researched: true }.to_json, headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "leitura" do
    it "expõe crm_data no GET /society/:inscricao" do
      society.update!(crm_data: { "researched" => true })

      get "/api/v1/society/990001", headers: { "X-API-KEY" => api_key.key }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["crm_data"]).to eq({ "researched" => true })
    end

    it "devolve crm_data vazio como {} e não nil" do
      get "/api/v1/society/990001", headers: { "X-API-KEY" => api_key.key }

      expect(JSON.parse(response.body)["crm_data"]).to eq({})
    end
  end
end
