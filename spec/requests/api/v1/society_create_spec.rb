require 'rails_helper'

RSpec.describe "Api::V1::Societies", type: :request do
  let(:user) { User.create(email: "test@example.com", password: "password", admin: false) }
  let(:api_key) { ApiKey.create(user: user, key: "test_key", active: true) }
  let(:headers) { { "X-API-KEY" => api_key.key } }

  describe "POST /api/v1/society/create" do
    let(:valid_attributes) {
      {
        inscricao: "12345",
        name: "Smith & Associates",
        state: "SP",
        number_of_partners: 5,
        city: "São Paulo",
        address: "Av. Paulista, 1000",
        zip_code: "01310-100",
        phone: "(11) 99999-9999"
      }
    }

    context "with valid parameters" do
      it "creates a new society" do
        expect {
          post "/api/v1/society/create", params: valid_attributes, headers: headers
        }.to change(Society, :count).by(1)

        expect(response).to have_http_status(:created)

        json_response = JSON.parse(response.body)
        expect(json_response["message"]).to eq("Sociedade criada com sucesso")
        expect(json_response["society"]["name"]).to eq("Smith & Associates")
        expect(json_response["society"]["inscricao"]).to eq("12345")
        expect(json_response["society"]["oab_id"]).to eq("SP_SOC_12345")
      end
    end

    context "with invalid parameters" do
      it "does not create a society without inscricao" do
        invalid_attributes = valid_attributes.except(:inscricao)

        expect {
          post "/api/v1/society/create", params: invalid_attributes, headers: headers
        }.not_to change(Society, :count)

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("obrigatórios")
      end

      it "does not create a society without name" do
        invalid_attributes = valid_attributes.except(:name)

        expect {
          post "/api/v1/society/create", params: invalid_attributes, headers: headers
        }.not_to change(Society, :count)

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("obrigatórios")
      end

      it "does not create a society without state" do
        invalid_attributes = valid_attributes.except(:state)

        expect {
          post "/api/v1/society/create", params: invalid_attributes, headers: headers
        }.not_to change(Society, :count)

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("obrigatórios")
      end

      it "does not create a society without number_of_partners" do
        invalid_attributes = valid_attributes.except(:number_of_partners)

        expect {
          post "/api/v1/society/create", params: invalid_attributes, headers: headers
        }.not_to change(Society, :count)

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("obrigatórios")
      end
    end

    context "with duplicate inscricao" do
      before do
        Society.create(
          inscricao: "12345",
          name: "Existing Society",
          state: "SP",
          number_of_partners: 3
        )
      end

      it "returns conflict error for duplicate inscricao" do
        expect {
          post "/api/v1/society/create", params: valid_attributes, headers: headers
        }.not_to change(Society, :count)

        expect(response).to have_http_status(:conflict)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("já cadastrada")
      end
    end

    context "with invalid authentication" do
      it "returns unauthorized without valid API key" do
        post "/api/v1/society/create", params: valid_attributes, headers: { "X-API-KEY" => "invalid_key" }

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid API Key")
      end
    end
  end
end
