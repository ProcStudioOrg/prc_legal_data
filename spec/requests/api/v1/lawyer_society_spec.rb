require 'rails_helper'

RSpec.describe "Api::V1::LawyerSocieties", type: :request do
  let(:user) { User.create(email: "test@example.com", password: "password", admin: false) }
  let(:api_key) { ApiKey.create(user: user, key: "test_key", active: true) }
  let(:headers) { { "X-API-KEY" => api_key.key } }

  let(:lawyer) {
    Lawyer.create(
      full_name: "John Doe",
      oab_number: "123456",
      state: "SP",
      oab_id: "SP_123456",
      has_society: false
    )
  }

  let(:society) {
    Society.create(
      inscricao: "12345",
      name: "Smith & Associates",
      state: "SP",
      number_of_partners: 5,
      oab_id: "SP_SOC_12345"
    )
  }

  describe "POST /api/v1/lawyer_societies" do
    let(:valid_attributes) {
      {
        lawyer_id: lawyer.id,
        society_id: society.id,
        partnership_type: "Sócio",
        cna_link: "https://example.com/cna/doc123"
      }
    }

    context "with valid parameters" do
      it "creates a new lawyer-society relationship" do
        expect {
          post "/api/v1/lawyer_societies", params: valid_attributes, headers: headers
        }.to change(LawyerSociety, :count).by(1)

        expect(response).to have_http_status(:created)

        json_response = JSON.parse(response.body)
        expect(json_response["message"]).to eq("Relação entre advogado e sociedade criada com sucesso")
        expect(json_response["lawyer_society"]["lawyer_id"]).to eq(lawyer.id)
        expect(json_response["lawyer_society"]["society_id"]).to eq(society.id)
        expect(json_response["lawyer_society"]["partnership_type"]).to eq("Sócio")

        # Check that lawyer's has_society field was updated
        lawyer.reload
        expect(lawyer.has_society).to be true
        expect(lawyer.society_id).to eq(society.id)
      end
    end

    context "with invalid parameters" do
      it "does not create a relationship without lawyer_id" do
        invalid_attributes = valid_attributes.except(:lawyer_id)

        expect {
          post "/api/v1/lawyer_societies", params: invalid_attributes, headers: headers
        }.not_to change(LawyerSociety, :count)

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("obrigatórios")
      end

      it "does not create a relationship without society_id" do
        invalid_attributes = valid_attributes.except(:society_id)

        expect {
          post "/api/v1/lawyer_societies", params: invalid_attributes, headers: headers
        }.not_to change(LawyerSociety, :count)

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("obrigatórios")
      end

      it "does not create a relationship without partnership_type" do
        invalid_attributes = valid_attributes.except(:partnership_type)

        expect {
          post "/api/v1/lawyer_societies", params: invalid_attributes, headers: headers
        }.not_to change(LawyerSociety, :count)

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("obrigatórios")
      end
    end

    context "with non-existent lawyer" do
      it "returns not found error" do
        invalid_attributes = valid_attributes.merge(lawyer_id: 99999)

        expect {
          post "/api/v1/lawyer_societies", params: invalid_attributes, headers: headers
        }.not_to change(LawyerSociety, :count)

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("Advogado não encontrado")
      end
    end

    context "with non-existent society" do
      it "returns not found error" do
        invalid_attributes = valid_attributes.merge(society_id: 99999)

        expect {
          post "/api/v1/lawyer_societies", params: invalid_attributes, headers: headers
        }.not_to change(LawyerSociety, :count)

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("Sociedade não encontrada")
      end
    end

    context "with duplicate relationship" do
      before do
        LawyerSociety.create(
          lawyer_id: lawyer.id,
          society_id: society.id,
          partnership_type: "Associado"
        )
      end

      it "returns conflict error for duplicate relationship" do
        expect {
          post "/api/v1/lawyer_societies", params: valid_attributes, headers: headers
        }.not_to change(LawyerSociety, :count)

        expect(response).to have_http_status(:conflict)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("já existe")
      end
    end

    context "with society at capacity" do
      let(:full_society) {
        Society.create(
          inscricao: "54321",
          name: "Full Society",
          state: "SP",
          number_of_partners: 1,
          oab_id: "SP_SOC_54321"
        )
      }

      before do
        other_lawyer = Lawyer.create(
          full_name: "Jane Doe",
          oab_number: "654321",
          state: "SP",
          oab_id: "SP_654321"
        )

        LawyerSociety.create(
          lawyer_id: other_lawyer.id,
          society_id: full_society.id,
          partnership_type: "Sócio"
        )
      end

      it "returns unprocessable_entity when society is at capacity" do
        attributes = valid_attributes.merge(society_id: full_society.id)

        expect {
          post "/api/v1/lawyer_societies", params: attributes, headers: headers
        }.not_to change(LawyerSociety, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("Erro ao criar relação")
        expect(json_response["details"].first).to include("full capacity")
      end
    end

    context "with invalid authentication" do
      it "returns unauthorized without valid API key" do
        post "/api/v1/lawyer_societies", params: valid_attributes, headers: { "X-API-KEY" => "invalid_key" }

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Invalid API Key")
      end
    end
  end

  describe "DELETE /api/v1/lawyer_societies/:id" do
    let!(:lawyer_society) {
      ls = LawyerSociety.create(
        lawyer_id: lawyer.id,
        society_id: society.id,
        partnership_type: "Sócio"
      )
      lawyer.update(has_society: true, society_id: society.id)
      ls
    }

    it "removes the relationship" do
      expect {
        delete "/api/v1/lawyer_societies/#{lawyer_society.id}", headers: headers
      }.to change(LawyerSociety, :count).by(-1)

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["message"]).to include("removida com sucesso")

      # Check that lawyer's has_society field was updated
      lawyer.reload
      expect(lawyer.has_society).to be false
      expect(lawyer.society_id).to be_nil
    end

    it "returns not found for non-existent relationship" do
      delete "/api/v1/lawyer_societies/99999", headers: headers

      expect(response).to have_http_status(:not_found)
      json_response = JSON.parse(response.body)
      expect(json_response["error"]).to include("não encontrada")
    end
  end

  describe "GET /api/v1/lawyer_societies/:id" do
    let!(:lawyer_society) {
      LawyerSociety.create(
        lawyer_id: lawyer.id,
        society_id: society.id,
        partnership_type: "Sócio"
      )
    }

    it "returns the relationship details" do
      get "/api/v1/lawyer_societies/#{lawyer_society.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["lawyer_society"]["id"]).to eq(lawyer_society.id)
      expect(json_response["lawyer"]["id"]).to eq(lawyer.id)
      expect(json_response["society"]["id"]).to eq(society.id)
    end

    it "returns not found for non-existent relationship" do
      get "/api/v1/lawyer_societies/99999", headers: headers

      expect(response).to have_http_status(:not_found)
      json_response = JSON.parse(response.body)
      expect(json_response["error"]).to include("não encontrada")
    end
  end

  describe "PATCH /api/v1/lawyer_societies/:id" do
    let!(:lawyer_society) {
      LawyerSociety.create(
        lawyer_id: lawyer.id,
        society_id: society.id,
        partnership_type: "Sócio"
      )
    }

    it "updates the relationship" do
      patch "/api/v1/lawyer_societies/#{lawyer_society.id}",
        params: { partnership_type: "Associado", cna_link: "https://updated-link.com" },
        headers: headers

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["message"]).to include("atualizada com sucesso")

      lawyer_society.reload
      expect(lawyer_society.partnership_type).to eq("Associado")
      expect(lawyer_society.cna_link).to eq("https://updated-link.com")
    end

    it "returns bad request when no update parameters are provided" do
      patch "/api/v1/lawyer_societies/#{lawyer_society.id}", params: {}, headers: headers

      expect(response).to have_http_status(:bad_request)
      json_response = JSON.parse(response.body)
      expect(json_response["error"]).to include("Nenhum parâmetro")
    end

    it "returns not found for non-existent relationship" do
      patch "/api/v1/lawyer_societies/99999",
        params: { partnership_type: "Associado" },
        headers: headers

      expect(response).to have_http_status(:not_found)
      json_response = JSON.parse(response.body)
      expect(json_response["error"]).to include("não encontrada")
    end
  end
end
