require 'rails_helper'

RSpec.describe "Api::V1::Lawyers", type: :request do
  let(:user) { User.create(email: "test@example.com", password: "password", admin: false) }
  let(:api_key) { ApiKey.create(user: user, key: "test_key", active: true) }
  let(:headers) { { "X-API-KEY" => api_key.key } }

  describe "POST /api/v1/lawyer/create" do
    let(:valid_attributes) {
      {
        full_name: "John Doe",
        oab_number: "123456",
        state: "SP",
        city: "São Paulo",
        address: "Av. Paulista, 1000",
        zip_code: "01310-100",
        phone_number_1: "(11) 99999-9999",
        situation: "Regular",
        profession: "Advogado"
      }
    }

    context "with valid parameters" do
      it "creates a new lawyer" do
        expect {
          post "/api/v1/lawyer/create", params: valid_attributes, headers: headers
        }.to change(Lawyer, :count).by(1)

        expect(response).to have_http_status(:created)

        json_response = JSON.parse(response.body)
        expect(json_response["message"]).to eq("Advogado criado com sucesso")
        expect(json_response["lawyer"]["full_name"]).to eq("John Doe")
        expect(json_response["lawyer"]["oab_id"]).to eq("SP_123456")
      end
    end

    context "with invalid parameters" do
      it "does not create a lawyer without oab_number" do
        invalid_attributes = valid_attributes.except(:oab_number)

        expect {
          post "/api/v1/lawyer/create", params: invalid_attributes, headers: headers
        }.not_to change(Lawyer, :count)

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("obrigatórios")
      end

      it "does not create a lawyer without state" do
        invalid_attributes = valid_attributes.except(:state)

        expect {
          post "/api/v1/lawyer/create", params: invalid_attributes, headers: headers
        }.not_to change(Lawyer, :count)

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("obrigatórios")
      end
    end

    context "with duplicate oab_id" do
      before do
        Lawyer.create(
          full_name: "Existing Lawyer",
          oab_number: "123456",
          state: "SP",
          oab_id: "SP_123456"
        )
      end

      it "returns conflict error for duplicate OAB" do
        expect {
          post "/api/v1/lawyer/create", params: valid_attributes, headers: headers
        }.not_to change(Lawyer, :count)

        expect(response).to have_http_status(:conflict)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("já cadastrado")
      end
    end

    context "with invalid authentication" do
      it "returns unauthorized without valid API key" do
        post "/api/v1/lawyer/create", params: valid_attributes, headers: { "X-API-KEY" => "invalid_key" }

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid API Key")
      end
    end
  end
end
