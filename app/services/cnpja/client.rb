# frozen_string_literal: true

require 'net/http'
require 'json'

module Cnpja
  # Cliente do CNPJA. Header `Authorization: <token>` cru, sem "Bearer".
  #
  # CRÉDITO É CARO: 1 crédito = 1 CNPJ retornado. Uma busca que devolve 10
  # estabelecimentos custa 10. Por isso todo método aqui pede `limit` explícito
  # e o default é o menor possível — nunca use limit alto para "garantir".
  #
  # Rate limit medido (PLANO-CNPJA.md §4): token bucket de ~16 de burst com
  # refil de ~1/min ≈ 1.440 requests/dia.
  class Client
    HOST = 'api.cnpja.com'
    # Sociedade de advogados. Filtrar por CNAE evita pagar por homônimo de
    # outro ramo ("LUIZA BARCELOS CALCADOS S/A" apareceu no dry run).
    CNAE_ADVOCACIA = 6_911_701
    BACKOFF = [30, 60, 90, 120, 150].freeze

    class RateLimited < StandardError; end
    class Error < StandardError; end

    # Créditos gastos nesta instância. 1 crédito = 1 CNPJ devolvido, então o
    # contador soma os registros de cada resposta — é o gasto REAL, não o teto
    # do `limit`. Sem isso o orçamento vira chute: uma busca com limit=3 que
    # devolve 1 registro custa 1, não 3.
    attr_reader :credits_used

    def initialize(token: ENV.fetch('CNPJA'), logger: Rails.logger)
      @token = token
      @logger = logger
      @credits_used = 0
    end

    # Busca por nome, restrita a advocacia e à UF. `limit` é o teto de crédito
    # gasto nesta chamada.
    def search_by_name(name, uf:, limit: 5)
      get('/office', {
            'mainActivity.id.in' => CNAE_ADVOCACIA,
            'address.state.in' => uf,
            'names.in' => name,
            'head.eq' => 'true', # só matriz; filial baixada polui o match
            'limit' => limit
          })
    end

    def office(cnpj, simples: false, geocoding: false)
      params = {}
      params['simples'] = 'true' if simples
      params['geocoding'] = 'true' if geocoding
      get("/office/#{cnpj}", params)
    end

    private

    def get(path, params)
      uri = URI::HTTPS.build(host: HOST, path: path)
      uri.query = URI.encode_www_form(params) if params.any?

      attempt = 0
      begin
        response = perform(uri)
        case response.code.to_i
        when 200
          body = JSON.parse(response.body)
          @credits_used += count_records(body)
          body
        when 429
          raise RateLimited, "429 em #{path}"
        else
          raise Error, "#{response.code} em #{path}: #{response.body.to_s[0, 200]}"
        end
      rescue RateLimited
        wait = BACKOFF[attempt]
        raise if wait.nil?

        @logger.warn("[cnpja] 429, aguardando #{wait}s (tentativa #{attempt + 1})")
        sleep(wait)
        attempt += 1
        retry
      end
    end

    # /office?<filtros> devolve {"records": [...]}; /office/{cnpj} devolve um
    # objeto só. Nos dois casos o custo é o número de CNPJs que voltaram.
    def count_records(body)
      return body['records'].size if body.is_a?(Hash) && body['records'].is_a?(Array)
      return body.size if body.is_a?(Array)

      1
    end

    def perform(uri)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = @token
      request['Accept'] = 'application/json'

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 45) do |http|
        http.request(request)
      end
    end
  end
end
