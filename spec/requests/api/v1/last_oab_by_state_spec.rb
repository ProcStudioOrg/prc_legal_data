require 'rails_helper'

RSpec.describe 'GET /api/v1/lawyer/state/:state/last', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { create(:api_key, user: user, role: 'read', active: true) }
  let(:headers) { { 'X-API-KEY' => api_key.key } }

  it 'inclui o teto preciso da UF ao lado da maior inscrição da base' do
    create(:lawyer, oab_id: 'PR_100001', oab_number: '100001', state: 'PR', cna_scraped_at: Time.current)
    get '/api/v1/lawyer/state/pr/last', headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include('oab_number' => '100001', 'ceiling' => 138_358, 'ceiling_checked_at' => '2026-11-07')
  end

  it 'traz o teto mesmo sem advogados na UF' do
    get '/api/v1/lawyer/state/RR/last', headers: headers
    expect(JSON.parse(response.body)).to include('total_lawyers' => 0, 'ceiling' => 3463)
  end
end
