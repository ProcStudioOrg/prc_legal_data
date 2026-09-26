require 'rails_helper'

RSpec.describe 'Versioned ProcStudio relationship', type: :request do
  let(:user) { User.create!(email: 'relationship@example.com', password: 'password') }
  let(:key) { ApiKey.create!(user: user, key: 'relationship-test-key', role: 'admin', active: true) }
  let(:headers) { { 'X-API-KEY' => key.key, 'CONTENT_TYPE' => 'application/json' } }
  let!(:lawyer) { create(:lawyer, oab_id: 'SP_540001', crm_data: { signals: { keep: true }, outreach: { other: 'kept' } }) }
  def fact(version = 1, at = '2026-09-26T12:00:00.000Z')
    { 'schema_version' => 1, 'source_id' => 'procstudio:user:1', 'canonical_oab' => 'SP_540001',
      'version' => version, 'event_id' => "event-#{version}", 'observed_at' => at,
      'historical' => { 'tried' => true }, 'inactivity' => { 'status' => 'possible_abandonment', 'threshold_days' => 40 } }
  end
  def deliver(payload)
    post '/api/v1/lawyer/SP_540001/crm', params: { outreach: { procstudio_relationship: payload } }.to_json, headers: headers
  end
  it 'confirms its guarded contract, is idempotent, and preserves unrelated namespaces' do
    deliver(fact)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['relationship_contract']).to eq('procstudio-relationship-v1')
    deliver(fact)
    expect(response).to have_http_status(:ok)
    expect(lawyer.reload.crm_data).to include('signals' => { 'keep' => true })
    expect(lawyer.crm_data['outreach']['other']).to eq('kept')
  end
  it 'rejects stale, conflicting same-version and different source deliveries' do
    deliver(fact(2))
    deliver(fact(1))
    expect(response).to have_http_status(:conflict)
    deliver(fact(2).merge('event_id' => 'other'))
    expect(response).to have_http_status(:conflict)
    deliver(fact(3).merge('source_id' => 'procstudio:user:2'))
    expect(response).to have_http_status(:conflict)
    expect(lawyer.reload.crm_data.dig('outreach', 'procstudio_relationship', 'version')).to eq(2)
  end
  it 'rejects older observations even when their version increases' do
    deliver(fact)
    deliver(fact(2, '2026-09-25T12:00:00.000Z'))
    expect(response).to have_http_status(:conflict)
  end
  it 'requires valid metadata and preserves historical trial truth' do
    deliver({ 'version' => 1 })
    expect(response).to have_http_status(:unprocessable_content)
    deliver(fact)
    deliver(fact(2).merge('historical' => { 'tried' => false }))
    expect(response).to have_http_status(:conflict)
  end
  it 'refreshes a preloaded generic writer inside the lock before merging' do
    # Simulates another request committing after set_lawyer read this instance.
    stale = Lawyer.find(lawyer.id)
    allow(Lawyer).to receive(:find_by).with(oab_id: 'SP_540001').and_return(stale)
    lawyer.update!(crm_data: lawyer.crm_data.deep_merge('outreach' => { 'procstudio_relationship' => fact }))
    post '/api/v1/lawyer/SP_540001/crm', params: { signals: { extra: true } }.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    expect(lawyer.reload.crm_data.dig('outreach', 'procstudio_relationship')).to eq(fact)
    expect(lawyer.crm_data['signals']).to eq('keep' => true, 'extra' => true)
  end
  it 'exposes a dedicated guarded path so older servers cannot silently accept unguarded writes' do
    post '/api/v1/lawyer/SP_540001/procstudio-relationship', params: { outreach: { procstudio_relationship: fact } }.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['relationship_contract']).to eq('procstudio-relationship-v1')
  end
end
