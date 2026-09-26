require 'rails_helper'

RSpec.describe 'Classifier candidates', type: :request do
  let(:key) { create(:api_key) }
  let(:headers) { { 'X-API-KEY' => key.key } }
  let(:filters) { { state: 'PR', city: ' são   josé ', min_oab: 9, max_oab: 100, order: 'asc', limit: 1 } }
  def candidate(number, **attrs)
    create(:lawyer, oab_id: "PR_#{number}", oab_number: number.to_s, state: 'PR', city: 'São José', **attrs)
  end
  it 'normalizes city, includes bounds and paginates numerically within UF' do
    candidate(9); candidate(100); candidate(10, city: 'Toledo'); candidate(101)
    get '/api/v1/lawyers/classifier-candidates', params: filters, headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['contract']).to eq('classifier-candidates-v1')
    expect(body['lawyers'].map { |r| r['matched_oab_id'] }).to eq(['PR_9'])
    get '/api/v1/lawyers/classifier-candidates', params: filters.merge(cursor: body['next_cursor']), headers: headers
    expect(JSON.parse(response.body)['lawyers'].map { |r| r['matched_oab_id'] }).to eq(['PR_100'])
  end
  it 'deduplicates the person by ordered matched registration and exposes all aliases' do
    principal = create(:lawyer, oab_id: 'SP_999', oab_number: '999', state: 'SP')
    candidate(20, principal_lawyer: principal); candidate(80, principal_lawyer: principal); candidate(60)
    get '/api/v1/lawyers/classifier-candidates', params: filters.merge(order: 'desc', limit: 10), headers: headers
    expect(response).to have_http_status(:ok)
    rows = JSON.parse(response.body)['lawyers']
    expect(rows.map { |r| r['matched_oab_id'] }).to eq(%w[PR_80 PR_60])
    expect(rows[0]['oab_id']).to eq('SP_999')
    expect(rows[0]).to include('city' => 'São José', 'state' => 'PR', 'canonical_city' => 'São Paulo', 'canonical_state' => 'SP')
    expect(rows[0]['registrations']).to match_array(%w[SP_999 PR_20 PR_80])
  end
  it 'excludes customers anywhere in cluster and cancelled registrations' do
    principal = candidate(20)
    candidate(80, principal_lawyer: principal, is_procstudio: true)
    candidate(30, situation: 'cancelado')
    get '/api/v1/lawyers/classifier-candidates', params: filters.merge(limit: 10), headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['lawyers']).to eq([])
  end
  it 'rejects invalid selection and requires authentication' do
    get '/api/v1/lawyers/classifier-candidates', params: filters.merge(min_oab: 101), headers: headers
    expect(response).to have_http_status(:bad_request)
    get '/api/v1/lawyers/classifier-candidates', params: filters, headers: { 'X-API-KEY' => 'invalid' }
    expect(response).to have_http_status(:unauthorized)
  end
  it 'rejects a cursor from another filter and skips malformed numeric registrations' do
    candidate(9); candidate(10)
    create(:lawyer, oab_id: 'PR_11', oab_number: 'invalid', state: 'PR', city: 'São José')
    get '/api/v1/lawyers/classifier-candidates', params: filters, headers: headers
    expect(response).to have_http_status(:ok)
    cursor = JSON.parse(response.body)['next_cursor']
    get '/api/v1/lawyers/classifier-candidates', params: filters.merge(order: 'desc', cursor: cursor), headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  it 'keeps absent principal city unknown when selecting a supplementary location' do
    principal = create(:lawyer, oab_id: 'SP_999', oab_number: '999', state: 'SP', city: nil)
    candidate(9, principal_lawyer: principal)
    get '/api/v1/lawyers/classifier-candidates', params: filters, headers: headers
    expect(response).to have_http_status(:ok)
    row = JSON.parse(response.body)['lawyers'].first
    expect(row).to include('city' => 'São José', 'canonical_city' => nil, 'canonical_state' => 'SP')
  end

end
