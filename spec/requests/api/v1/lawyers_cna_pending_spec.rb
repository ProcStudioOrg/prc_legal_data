require 'rails_helper'

RSpec.describe 'GET /api/v1/lawyers?cna_pending=true', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { create(:api_key, user: user, role: 'read', active: true) }
  let(:headers) { { 'X-API-KEY' => api_key.key } }

  before do
    create(:lawyer, oab_id: 'PR_100001', oab_number: '100001', state: 'PR', situation: 'situação regular', cna_scraped_at: Time.current)
    create(:lawyer, oab_id: 'PR_135522', oab_number: '135522', state: 'PR', situation: nil, cna_scraped_at: nil,
                    discovered_via: 'receita+djen', city: 'FOZ DO IGUAÇU', city_source: 'receita')
    create(:lawyer, oab_id: 'PR_134341', oab_number: '134341', state: 'PR', situation: nil, cna_scraped_at: nil, discovered_via: 'coadvogado')
    create(:lawyer, oab_id: 'SC_1', oab_number: '1', state: 'SC', situation: nil, cna_scraped_at: nil, discovered_via: 'coadvogado')
  end

  it 'lista só os pendentes da UF, em ordem decrescente, com os campos de descoberta' do
    get '/api/v1/lawyers', params: { state: 'PR', cna_pending: 'true' }, headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['lawyers'].map { |l| l['oab_id'] }).to eq(%w[PR_135522 PR_134341])
    expect(body['lawyers'].first).to include('discovered_via' => 'receita+djen', 'city_source' => 'receita', 'cna_scraped_at' => nil)
    expect(body['meta']['cna_pending']).to eq(true)
  end

  it 'sem o filtro, pendentes sem situação não aparecem' do
    get '/api/v1/lawyers', params: { state: 'PR' }, headers: headers
    expect(JSON.parse(response.body)['lawyers'].map { |l| l['oab_id'] }).to eq(%w[PR_100001])
  end
end
