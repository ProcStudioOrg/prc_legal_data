module Djen
  # Global throttle for every request to comunicaapi, shared across all jobs
  # via Redis. Two mechanisms:
  #
  #   - spacing: a minimum interval between consecutive requests (SET NX lock),
  #     so concurrent jobs never burst past the CNJ window;
  #   - cooldown: set from the API's own x-ratelimit-remaining header (source
  #     of truth — the limit is never hardcoded) or after a 429.
  #
  # Degrades to a no-op (with a warning) if Redis is unreachable, so a Redis
  # outage slows nothing besides losing cross-process coordination.
  class RateLimiter
    SPACING_KEY = "djen:rate_limiter:spacing".freeze
    COOLDOWN_KEY = "djen:rate_limiter:cooldown".freeze

    def initialize(redis: nil, min_interval: ENV.fetch("DJEN_MIN_REQUEST_INTERVAL", 3).to_f, sleeper: ->(s) { sleep(s) })
      @redis = redis || Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
      @min_interval = min_interval
      @sleeper = sleeper
    end

    # Blocks until a request slot is available.
    def acquire!
      loop do
        wait = cooldown_remaining
        if wait.positive?
          @sleeper.call(wait)
          next
        end

        break if claim_slot
        @sleeper.call(@min_interval / 2.0)
      end
    rescue Redis::BaseError => e
      Rails.logger.warn("Djen::RateLimiter degraded (Redis unavailable): #{e.message}")
    end

    def throttle!(seconds)
      @redis.set(COOLDOWN_KEY, "1", ex: seconds.ceil)
    rescue Redis::BaseError => e
      Rails.logger.warn("Djen::RateLimiter degraded (Redis unavailable): #{e.message}")
    end

    # Called with the response headers of every DJEN request.
    def update_from_headers(headers)
      remaining = headers["x-ratelimit-remaining"]
      return if remaining.nil?

      throttle!(60) if remaining.to_i.zero?
    end

    private

    def claim_slot
      @redis.set(SPACING_KEY, "1", nx: true, px: (@min_interval * 1000).to_i)
    end

    def cooldown_remaining
      ttl = @redis.ttl(COOLDOWN_KEY)
      ttl.positive? ? ttl : 0
    end
  end
end
