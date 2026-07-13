require "net/http"

module Djen
  # HTTP client for the DJEN public API (comunicaapi.pje.jus.br).
  #
  # Pagination stops on an empty page — the API's `count` field is unreliable
  # on deep pages and must never be used as a stop criterion.
  class Client
    Error = Class.new(StandardError)
    ServerError = Class.new(Error)

    PER_PAGE = 100
    RATE_LIMIT_WAIT = 60         # seconds after a 429, plus jitter
    RATE_LIMIT_RETRIES = 5       # then raise: solid_queue's retry_on takes over
    SERVER_ERROR_RETRIES = 3
    SERVER_ERROR_BASE_WAIT = 5   # 5s, 25s, 125s

    def initialize(base_url: ENV.fetch("DJEN_BASE_URL", "https://comunicaapi.pje.jus.br"),
                   rate_limiter: RateLimiter.new,
                   sleeper: ->(s) { sleep(s) })
      @base_url = base_url
      @rate_limiter = rate_limiter
      @sleeper = sleeper
    end

    # Yields every comunicação item for one OAB over a date window,
    # transparently paginating.
    def each_comunicacao(numero_oab:, uf_oab:, data_inicio:, data_fim:)
      return enum_for(:each_comunicacao, numero_oab: numero_oab, uf_oab: uf_oab,
                      data_inicio: data_inicio, data_fim: data_fim) unless block_given?

      pagina = 1
      loop do
        body = get_json(
          numeroOab: numero_oab,
          ufOab: uf_oab,
          dataDisponibilizacaoInicio: data_inicio.to_s,
          dataDisponibilizacaoFim: data_fim.to_s,
          itensPorPagina: PER_PAGE,
          pagina: pagina
        )

        items = body["items"] || []
        break if items.empty?

        items.each { |item| yield item }
        pagina += 1
      end
    end

    private

    def get_json(params)
      uri = URI("#{@base_url}/api/v1/comunicacao")
      uri.query = URI.encode_www_form(params)

      response = request_with_retries(uri)
      body = JSON.parse(response.body)
      raise Error, "DJEN returned a non-object body: #{body.class}" unless body.is_a?(Hash)
      raise Error, "DJEN returned non-array items" unless body.fetch("items", []).is_a?(Array)

      body
    rescue JSON::ParserError => e
      raise Error, "DJEN returned invalid JSON: #{e.message}"
    end

    def request_with_retries(uri)
      attempts = 0
      rate_limited = 0

      loop do
        @rate_limiter.acquire!
        response = perform_request(uri)
        @rate_limiter.update_from_headers(response)

        case response.code.to_i
        when 200..299
          return response
        when 429
          rate_limited += 1
          # Sem teto o job seguraria um worker do solid_queue para sempre.
          raise Error, "DJEN still rate-limiting after #{rate_limited} attempts" if rate_limited > RATE_LIMIT_RETRIES

          wait = RATE_LIMIT_WAIT + rand(0..15)
          Rails.logger.warn("Djen::Client 429 — backing off #{wait}s")
          @rate_limiter.throttle!(wait)
          @sleeper.call(wait)
        when 500..599
          attempts += 1
          raise ServerError, "DJEN #{response.code} after #{attempts} attempts" if attempts > SERVER_ERROR_RETRIES

          wait = SERVER_ERROR_BASE_WAIT**attempts
          Rails.logger.warn("Djen::Client #{response.code} — retry #{attempts} in #{wait}s")
          @sleeper.call(wait)
        else
          raise Error, "DJEN unexpected response #{response.code}: #{response.body&.first(200)}"
        end
      end
    end

    def perform_request(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: 10, read_timeout: 60) do |http|
        http.get(uri.request_uri, { "Accept" => "application/json" })
      end
    rescue SystemCallError, Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError => e
      raise Error, "DJEN request failed: #{e.class}: #{e.message}"
    end
  end
end
