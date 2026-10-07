require 'rails_helper'

RSpec.describe 'Api::V1::Cnpj', type: :request do
  let(:user) { User.create!(email: 'cnpj@example.com', password: 'password', admin: false) }
  let(:api_key) { ApiKey.create!(user: user, active: true, role: 'read') }
  let(:headers) { { 'X-API-KEY' => api_key.key } }

  it 'exige API key' do
    get '/api/v1/cnpj/11222333000181'
    expect(response).to have_http_status(:unauthorized)
  end

  it 'devolve 422 em pt-BR para CNPJ inválido' do
    get '/api/v1/cnpj/11222333000182', headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('CNPJ inválido')
  end

  it 'devolve a empresa do dump no formato do ReceitaCompanySerializer, aceitando máscara' do
    company = create(:receita_company, cnpj: '11222333000181')
    create(:receita_partner, receita_company: company, nome_socio: 'SOCIA UM', last_seen_release: company.release)

    get '/api/v1/cnpj/11.222.333.0001-81', headers: headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['cnpj']).to eq('11222333000181')
    expect(body['endereco']['municipio']).to eq('CASCAVEL')
    expect(body['partners'].first['nome']).to eq('SOCIA UM')
    expect(UsageEvent.count).to eq(1)
  end

  it 'devolve 404 quando a API pública não conhece o CNPJ' do
    stub_request(:get, 'https://api.opencnpj.org/11222333000181').to_return(status: 404)
    get '/api/v1/cnpj/11222333000181', headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('CNPJ não encontrado na Receita')
  end

  it 'devolve 503 com retry_after quando a API pública limita' do
    stub_request(:get, 'https://api.opencnpj.org/11222333000181').to_return(status: 429, headers: { 'Retry-After' => '45' })
    get '/api/v1/cnpj/11222333000181', headers: headers
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to include('error' => 'Receita indisponível no momento', 'retry_after' => 45)
  end
end
