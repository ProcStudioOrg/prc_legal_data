require 'rails_helper'

RSpec.describe "Api::V1::Djen::Monitorings", type: :request do
  let(:user) { User.create!(email: "djen@example.com", password: "password") }
  let(:api_key) { ApiKey.create!(user: user, role: "admin", active: true) }
  let(:headers) { { "X-API-KEY" => api_key.key } }
  let!(:lawyer) { create(:lawyer, oab_id: "PR_54159", oab_number: "54159", state: "PR") }

  describe "POST /api/v1/djen/monitorings" do
    it "creates a monitoring and enqueues onboarding" do
      expect {
        post "/api/v1/djen/monitorings", params: { oab: "PR_54159" }, headers: headers
      }.to change(DjenMonitoring, :count).by(1)
        .and have_enqueued_job(Djen::OnboardJob)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["oab_id"]).to eq("PR_54159")
      expect(body["active"]).to be(true)
      expect(body["source"]).to eq("procstudio")
    end

    it "is idempotent: re-posting an active watch returns 200 without duplicating" do
      create(:djen_monitoring, :onboarded, lawyer: lawyer)

      expect {
        post "/api/v1/djen/monitorings", params: { oab: "PR_54159" }, headers: headers
      }.not_to change(DjenMonitoring, :count)

      expect(response).to have_http_status(:ok)
    end

    it "reactivates an inactive watch without re-onboarding" do
      create(:djen_monitoring, :inactive, :onboarded, lawyer: lawyer)

      expect {
        post "/api/v1/djen/monitorings", params: { oab: "PR_54159" }, headers: headers
      }.not_to have_enqueued_job(Djen::OnboardJob)

      expect(response).to have_http_status(:ok)
      expect(lawyer.reload.djen_monitoring.active).to be(true)
    end

    it "resolves a supplementary OAB to the principal lawyer" do
      supplementary = create(:lawyer, oab_id: "SC_99001", oab_number: "99001", state: "SC",
                                      suplementary: true, principal_lawyer: lawyer)

      post "/api/v1/djen/monitorings", params: { oab: supplementary.oab_id }, headers: headers

      expect(response).to have_http_status(:created)
      expect(DjenMonitoring.last.lawyer).to eq(lawyer)
      body = JSON.parse(response.body)
      expect(body["oab_id"]).to eq("PR_54159")
      expect(body["monitored_oabs"]).to contain_exactly("PR_54159", "SC_99001")
    end

    it "returns 404 for an unknown lawyer" do
      post "/api/v1/djen/monitorings", params: { oab: "XX_00000" }, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 400 without an oab param" do
      post "/api/v1/djen/monitorings", params: {}, headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it "requires an admin key" do
      read_key = ApiKey.create!(user: user, role: "read", active: true)

      post "/api/v1/djen/monitorings", params: { oab: "PR_54159" },
           headers: { "X-API-KEY" => read_key.key }

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects requests without a valid API key" do
      post "/api/v1/djen/monitorings", params: { oab: "PR_54159" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/djen/monitorings/:oab" do
    it "returns monitoring status with counts" do
      monitoring = create(:djen_monitoring, :onboarded, lawyer: lawyer)
      create(:djen_comunicacao, :pushed, djen_monitoring: monitoring)
      create(:djen_comunicacao, djen_monitoring: monitoring)

      get "/api/v1/djen/monitorings/PR_54159", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["comunicacoes"]).to eq(
        "total" => 2, "pending_push" => 1, "cancelled" => 0
      )
    end

    it "returns 404 when the lawyer is not monitored" do
      get "/api/v1/djen/monitorings/PR_54159", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/djen/monitorings/:oab" do
    it "deactivates the monitoring but keeps history" do
      monitoring = create(:djen_monitoring, lawyer: lawyer)
      create(:djen_comunicacao, djen_monitoring: monitoring)

      delete "/api/v1/djen/monitorings/PR_54159", headers: headers

      expect(response).to have_http_status(:ok)
      expect(monitoring.reload.active).to be(false)
      expect(monitoring.djen_comunicacoes.count).to eq(1)
    end
  end
end
