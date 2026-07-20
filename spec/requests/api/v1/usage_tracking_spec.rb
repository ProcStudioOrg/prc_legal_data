require 'rails_helper'

RSpec.describe "Usage tracking", type: :request do
  let(:user) { User.create(email: "usage@example.com", password: "password", admin: false) }
  let(:api_key) { ApiKey.create(user: user, key: "test_key_usage", active: true) }
  let(:headers) { { "X-API-KEY" => api_key.key } }

  before do
    ENV['USAGE_IP_SALT'] = "test_salt"
    # ApiLog's Geocoder lookup hits the network for public IPs; WebMock's
    # NetConnectNotAllowedError inherits from Exception and bypasses its rescue.
    allow(Geocoder).to receive(:search).and_return([])
    create(:lawyer, oab_id: "PR_777", oab_number: "777", state: "PR", situation: "situação regular")
  end

  after { ENV.delete('USAGE_IP_SALT') }

  describe "capture on consulta endpoints" do
    it "records a UsageEvent hashing the first X-Forwarded-For IP with the salt" do
      expect {
        get "/api/v1/lawyers", params: { state: "PR" },
                               headers: headers.merge("X-Forwarded-For" => "203.0.113.7, 10.0.0.1")
      }.to change(UsageEvent, :count).by(1)

      expect(response).to have_http_status(:ok)

      event = UsageEvent.last
      expect(event.event_type).to eq("consulta")
      expect(event.ip_hash).to eq(Digest::SHA256.hexdigest("203.0.113.7test_salt"))
    end

    it "falls back to remote_ip when X-Forwarded-For is absent" do
      get "/api/v1/lawyers", params: { state: "PR" }, headers: headers

      expect(UsageEvent.last.ip_hash)
        .to eq(Digest::SHA256.hexdigest("127.0.0.1test_salt"))
    end

    it "does not record events for write endpoints" do
      expect {
        post "/api/v1/lawyer/create", params: {}, headers: headers
      }.not_to change(UsageEvent, :count)
    end

    it "does not record events for unauthenticated requests" do
      expect {
        get "/api/v1/lawyers", params: { state: "PR" }, headers: { "X-API-KEY" => "invalid" }
      }.not_to change(UsageEvent, :count)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "fire-and-forget" do
    it "responds normally when the tracking INSERT raises" do
      allow(UsageEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")
      allow(Rails.logger).to receive(:error).and_call_original

      get "/api/v1/lawyers", params: { state: "PR" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["lawyers"]).to be_an(Array)
      expect(Rails.logger).to have_received(:error).with(/UsageTracking/)
    end
  end
end
