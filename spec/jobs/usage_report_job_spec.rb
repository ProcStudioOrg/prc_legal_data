require 'rails_helper'

RSpec.describe UsageReportJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:webhook_url) { "https://webhook.example.com/usage" }
  let(:tz) { ActiveSupport::TimeZone["America/Sao_Paulo"] }

  before do
    ENV['USAGE_WEBHOOK_URL'] = webhook_url
    travel_to tz.local(2026, 7, 19, 0, 5, 0)
  end

  after do
    ENV.delete('USAGE_WEBHOOK_URL')
    travel_back
  end

  def create_event(ip_hash, at)
    UsageEvent.create!(event_type: "consulta", ip_hash: ip_hash, created_at: at)
  end

  describe "aggregation" do
    it "aggregates yesterday (America/Sao_Paulo) with repeats, ignoring today's events" do
      yesterday_noon = tz.local(2026, 7, 18, 12, 0, 0)

      # aaaa... appears 3x, bbbb... 2x, cccc... and dddd... once each
      3.times { create_event("a" * 64, yesterday_noon) }
      2.times { create_event("b" * 64, yesterday_noon + 1.hour) }
      create_event("c" * 64, tz.local(2026, 7, 18, 0, 0, 1))   # start of day
      create_event("d" * 64, tz.local(2026, 7, 18, 23, 59, 59)) # end of day

      # Outside the window: today and two days ago
      create_event("e" * 64, tz.local(2026, 7, 19, 0, 1, 0))
      create_event("f" * 64, tz.local(2026, 7, 17, 23, 59, 59))

      stub = stub_request(:post, webhook_url).with(
        headers: { "Content-Type" => "application/json" },
        body: {
          service: "legal_data",
          date: "2026-07-18",
          events: 7,
          unique_users: 4,
          top_repeats: [
            { user: "aaaaaaaa", count: 3 },
            { user: "bbbbbbbb", count: 2 }
          ]
        }.to_json
      ).to_return(status: 200)

      described_class.perform_now

      expect(stub).to have_been_requested
    end

    it "sends a zeroed payload as heartbeat when the day had no events" do
      stub = stub_request(:post, webhook_url).with(
        body: {
          service: "legal_data",
          date: "2026-07-18",
          events: 0,
          unique_users: 0,
          top_repeats: []
        }.to_json
      ).to_return(status: 200)

      described_class.perform_now

      expect(stub).to have_been_requested
    end

    it "caps top_repeats at 5 ip_hashes, ordered by count desc" do
      yesterday_noon = tz.local(2026, 7, 18, 12, 0, 0)
      ("a".."g").each_with_index do |char, index|
        (index + 2).times { create_event(char * 64, yesterday_noon) }
      end

      body = nil
      stub_request(:post, webhook_url).with { |req| body = JSON.parse(req.body) }.to_return(status: 200)

      described_class.perform_now

      expect(body["top_repeats"].length).to eq(5)
      expect(body["top_repeats"].first).to eq({ "user" => "gggggggg", "count" => 8 })
      expect(body["top_repeats"].map { |r| r["count"] }).to eq([8, 7, 6, 5, 4])
    end
  end

  describe "delivery" do
    it "retries by re-enqueuing itself when the webhook fails" do
      stub_request(:post, webhook_url).to_return(status: 500)

      expect { described_class.perform_now }
        .to have_enqueued_job(described_class)
    end

    it "does not POST and logs a warning when USAGE_WEBHOOK_URL is not set" do
      ENV.delete('USAGE_WEBHOOK_URL')
      allow(Rails.logger).to receive(:warn)

      described_class.perform_now

      expect(Rails.logger).to have_received(:warn).with(/USAGE_WEBHOOK_URL/)
      expect(WebMock).not_to have_requested(:post, webhook_url)
    end
  end
end
