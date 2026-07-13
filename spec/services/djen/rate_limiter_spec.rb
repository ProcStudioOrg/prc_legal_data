require 'rails_helper'

RSpec.describe Djen::RateLimiter do
  let(:redis) { instance_double(Redis) }
  let(:sleeps) { [] }
  let(:limiter) do
    described_class.new(redis: redis, min_interval: 3, sleeper: ->(s) { sleeps << s })
  end

  describe "#acquire!" do
    it "claims a slot immediately when nothing is throttled" do
      allow(redis).to receive(:ttl).and_return(-2)
      allow(redis).to receive(:set).with(described_class::SPACING_KEY, "1", nx: true, px: 3000)
                                   .and_return(true)

      limiter.acquire!

      expect(sleeps).to be_empty
    end

    it "waits out an active cooldown before claiming" do
      allow(redis).to receive(:ttl).and_return(5, -2)
      allow(redis).to receive(:set).and_return(true)

      limiter.acquire!

      expect(sleeps).to eq([ 5 ])
    end

    it "spaces out contending claims across processes" do
      allow(redis).to receive(:ttl).and_return(-2, -2)
      allow(redis).to receive(:set).and_return(false, true)

      limiter.acquire!

      expect(sleeps).to eq([ 1.5 ]) # min_interval / 2
    end

    it "degrades to a no-op when Redis is unreachable" do
      allow(redis).to receive(:ttl).and_raise(Redis::CannotConnectError)

      expect { limiter.acquire! }.not_to raise_error
      expect(sleeps).to be_empty
    end
  end

  describe "#throttle!" do
    it "sets a cooldown with the given expiry" do
      expect(redis).to receive(:set).with(described_class::COOLDOWN_KEY, "1", ex: 75)

      limiter.throttle!(75)
    end

    it "degrades to a no-op when Redis is unreachable" do
      allow(redis).to receive(:set).and_raise(Redis::CannotConnectError)

      expect { limiter.throttle!(60) }.not_to raise_error
    end
  end

  describe "#update_from_headers" do
    it "throttles when x-ratelimit-remaining hits zero" do
      expect(redis).to receive(:set).with(described_class::COOLDOWN_KEY, "1", ex: 60)

      limiter.update_from_headers({ "x-ratelimit-remaining" => "0" })
    end

    it "does nothing while quota remains" do
      expect(redis).not_to receive(:set)

      limiter.update_from_headers({ "x-ratelimit-remaining" => "42" })
    end

    it "does nothing when the header is absent" do
      expect(redis).not_to receive(:set)

      limiter.update_from_headers({})
    end
  end
end
