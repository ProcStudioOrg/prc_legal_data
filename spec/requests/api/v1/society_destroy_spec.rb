require 'rails_helper'

RSpec.describe 'Api::V1::Societies#destroy', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { create(:api_key, user: user) }
  let(:headers) { { 'X-API-KEY' => api_key.key, 'Content-Type' => 'application/json' } }

  describe 'DELETE /api/v1/society/:inscricao' do
    context 'with valid API key' do
      it 'destroys the society' do
        society = create(:society)

        expect {
          delete "/api/v1/society/#{society.inscricao}", headers: headers
        }.to change(Society, :count).by(-1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['message']).to eq('Sociedade excluída com sucesso')
        expect(json['deleted_society']['inscricao']).to eq(society.inscricao)
      end

      it 'cascade deletes lawyer_societies' do
        society = create(:society, :with_lawyers, lawyers_count: 2)

        expect {
          delete "/api/v1/society/#{society.inscricao}", headers: headers
        }.to change(LawyerSociety, :count).by(-2)
      end

      it 'does not delete the lawyers themselves' do
        society = create(:society, :with_lawyers, lawyers_count: 2)

        expect {
          delete "/api/v1/society/#{society.inscricao}", headers: headers
        }.not_to change(Lawyer, :count)
      end

      it 'returns the count of removed lawyer associations' do
        society = create(:society, :with_lawyers, lawyers_count: 3)

        delete "/api/v1/society/#{society.inscricao}", headers: headers

        json = JSON.parse(response.body)
        expect(json['deleted_society']['lawyers_removed']).to eq(3)
      end

      it 'returns 404 when society not found' do
        delete '/api/v1/society/999999', headers: headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Sociedade não encontrada')
      end
    end

    context 'without API key' do
      it 'returns 401 unauthorized' do
        society = create(:society)

        delete "/api/v1/society/#{society.inscricao}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid API key' do
      it 'returns 401 unauthorized' do
        society = create(:society)

        delete "/api/v1/society/#{society.inscricao}", headers: { 'X-API-KEY' => 'invalid' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
