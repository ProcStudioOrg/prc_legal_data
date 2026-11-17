require 'rails_helper'

RSpec.describe 'Lawyer CNA identity', type: :request do
  let(:key) { create(:api_key) }
  let(:headers) { { 'X-API-KEY' => key.key } }

  it 'reports the requested slash suffix registration separately from the resolved principal' do
    principal = create(:lawyer, oab_id: 'PR_123', oab_number: '123', state: 'PR', cna_scraped_at: nil)
    supplementary = create(:lawyer, oab_id: 'MT_38280/A', oab_number: '38280/A', state: 'MT',
      suplementary: true, principal_lawyer: principal, cna_scraped_at: Time.utc(2026, 11, 17, 10),
      crm_data: { 'cna_app' => { 'tipo_inscricao' => 'SUPLEMENTAR', 'inscription_date' => '01/11/2026' },
                  'outreach' => { 'private_note' => 'internal only' } })
    get '/api/v1/lawyer/MT_38280%2FA', headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['principal']).to include('oab_id' => 'PR_123', 'cna_scraped_at' => nil, 'principal_lawyer_id' => nil)
    expect(body['requested_registration']).to include('oab_id' => 'MT_38280/A', 'oab_number' => '38280/A',
      'suplementary' => true, 'principal_lawyer_id' => principal.id, 'tipo_inscricao' => 'SUPLEMENTAR',
      'inscription_date' => '01/11/2026', 'cna_scraped_at' => '2026-11-17T10:00:00.000Z')
    expect(body['supplementaries'].first).to include('oab_id' => supplementary.oab_id, 'principal_lawyer_id' => principal.id)
    expect(response.body).not_to include('internal only', 'private_note', 'crm_data')
  end

  it 'keeps an unresolved supplement explicitly supplemental in the requested registration' do
    create(:lawyer, oab_id: 'SC_80757-A', oab_number: '80757-A', state: 'SC', suplementary: true,
      cna_scraped_at: Time.current, crm_data: { 'cna_app' => { 'tipo_inscricao' => 'SUPLEMENTAR' } })
    get '/api/v1/lawyer/SC_80757-A', headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['requested_registration']).to include('oab_id' => 'SC_80757-A',
      'suplementary' => true, 'principal_lawyer_id' => nil, 'tipo_inscricao' => 'SUPLEMENTAR')
  end
end
